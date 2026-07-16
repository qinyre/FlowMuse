# FlowMuse 实时协作：综合诊断与优化方案

> 本文档整合了三份独立调研（zcode、codex、claude）的分析，取各方之长，消除重复与矛盾，形成一份可直接指导实施的统一方案。
>
> 范围：实时元素同步、断线恢复、快照持久化、在线状态。不改变端到端加密和 Excalidraw 元素兼容性。
>
> 代码路径对应 `markdraw-harmonyos-probe` 分支。

---

## 一、摘要

协同测试中暴露两个核心症状：**实时同步慢**和**连接频繁断开**。

三份调研一致认为：当前架构骨架（元素级 LWW + Excalidraw 兼容 + E2E 加密 + Socket.IO 中继）是正确的选择，不需要替换为 CRDT 或 OT。问题出在工程实现——每一笔画布变更同时触发本地持久化、实时广播、远端快照三条重路径，且全部无节流、无批处理、无可靠性保证。

推荐路径：**有界频率的增量实时通道 + 本地 outbox 可靠投递 + 低频串行快照 + 明确的重连状态机**。这比替换成 Yjs/Automerge 风险小一个数量级，能直接解决当前主要问题。

---

## 二、现有协作架构

```
编辑器 (MarkdrawController)
  └─ onSceneChanged / onPointerPresence
       └─ WhiteboardPage (ConsumerState)
            ├─ WhiteboardCollaborationAdapter   ← 控制器 ↔ ExcalidrawScene 桥接
            └─ CollaborationRepository           ← 编排层
                 ├─ SocketIoRealtimeTransport     ← 加密帧的中继通道
                 ├─ HttpEncryptedSceneStore       ← 快照持久化（乐观锁 409）
                 ├─ HttpCollaborationFileStore    ← 图片二进制存储
                 ├─ CollaborationCrypto            ← AES-GCM-128
                 └─ SceneReconciler                ← 逐元素 LWW 合并
```

**协议模型**：全场景广播 + 逐元素 LWW 合并。没有 OT，没有 CRDT，没有操作码。删除表示为 `{isDeleted: true}`。增量靠客户端记录 `_broadcastedElementVersions[id]→version`，只发版本号前进的元素——但每个被发的元素是完整 JSON，没有字段级 diff。

**服务端角色**：纯加密字节中继。服务端永远拿不到明文，无法 diff、无法 merge、无法限流。只做两件事：校验发送者在房间内 + 帧不超过 8 MiB，然后 `client.To(room).Emit()` 转发。

**当前变更热路径**（每次 `onSceneChanged` 触发）：

```
WhiteboardPage._saveMarkdrawScene()
  ├─ serializeScene(全场景)          ← 本地持久化
  ├─ SQLite saveScene + 生成封面 + 更新资料库
  └─ CollaborationRepository.broadcastScene()
      ├─ getSyncableElements()        ← O(n) 过滤
      ├─ _changedElements()           ← O(n) 版本对比
      ├─ CollaborationMessage.toBytes() ← JSON 序列化
      ├─ _crypto.encrypt()            ← AES-GCM 加密
      ├─ _transport.send()            ← Socket.IO emit
      └─ unawaited(_saveSceneSnapshot()) ← 全量 HTTP PUT（乐观锁）
```

一笔书写会在一秒内触发几十次这条完整链路。随着笔迹增长，单次操作的数据量和 CPU/IO 成本线性增加。

---

## 三、根因分析

### 问题 A：实时同步慢

#### A1. 出站无节流，每次编辑都触发全链路工作

**证据**：`whiteboard_page.dart:1373` 的 `onSceneChanged` 直接链到 `_saveMarkdrawScene()` → `_broadcastCurrentScene()`。repository 层没有任何 debounce/coalesce——唯一门控是 `sceneVersion <= _lastBroadcastedOrReceivedSceneVersion` 的版本判断，但拖拽过程中元素 version 每帧都在涨，所以每次都过。

**影响**：一次拖拽一秒内触发几十次「序列化 → 本地写库 → 生成封面 → 加密 → emit → 异步快照 PUT」。CPU 被占满，主线程卡顿，网络被密集帧挤满。

**对比**：Figma 用 33ms 批处理窗口（30fps），Yjs 用 16ms 事务合并，Google Docs 用 ACK 规则自然合并。FlowMuse 当前无任何批处理。

#### A2. 实时通道无压缩，纯 JSON + AES-GCM 上线

**证据**：`_send` 路径是 `message.toBytes()` = `utf8.encode(jsonEncode(...))`，**没有 zlib/gzip 压缩**。项目里已有 `ExcalidrawBinaryCodec`（zlib + AES-GCM），但只被 `HttpCollaborationFileStore` 用于图片，实时通道完全没用上。

Excalidraw 元素 JSON 冗余度极高——大量重复字段名和默认值字符串。1000 个元素的画板 JSON 可达数百 KB，gzip 后通常只剩 10-20%。

**注意**：压缩必须在加密**之前**对明文 JSON 做。AES-GCM 密文是高熵均匀随机的，对密文压缩几乎无效。

#### A3. 适配器的冗余 JSON 字符串往返

**证据**：`WhiteboardCollaborationAdapter.currentScene()` 的路径：

```
controller.serializeExcalidrawSceneJson()  → 整个场景序列化成 JSON 字符串
jsonDecode(...)                             → 再解析回 Map
ExcalidrawScene.fromJson(...)               → 再深拷贝
```

这个三段式往返在**每次出站广播**和**每次入站应用**各执行一次。`applyRemoteScene` 反向再做一遍。对于大画板，这是单次操作中最大的 CPU 开销——远超加密本身。根因是编辑器内核的数据模型和 `ExcalidrawScene`（协作用的中间表示）之间没有直接映射，必须经过 JSON 字符串中转。

#### A4. 接收端串行解密队列

**证据**：`collaboration_repository.dart:414-422`：

```dart
_messageDecodeQueue = _messageDecodeQueue
    .then((_) => _handleEncryptedPayload(room, payload))  // 串行
    .catchError(...);
```

每条收到的加密消息必须等前一条完全解密+解析+回调分发后才能开始处理。收到 3 条消息，每条解密 15ms，第三条的延迟 = 30ms 排队 + 15ms 解密 = 45ms。10 人房间队列深度轻易达到 5-10 条。

#### A5. 每次 3 次 O(n) 全量遍历

**证据**：`broadcastScene()` 每次做 `getSyncableElements()`（O(n) 过滤）+ `_changedElements()`（O(n) 版本对比）+ `getSceneVersion()`（O(n) fold）。1000+ 元素场景，每帧浪费数毫秒 CPU。没有维护脏元素集合（dirty set）。

#### A6. 每 20 秒无条件全量场景同步

**证据**：`collaboration_repository.dart:705`：

```dart
_fullSceneSyncTimer = Timer.periodic(fullSceneSyncInterval, (_) {
  unawaited(broadcastScene(room: room, scene: _latestScene, syncAll: true));
});
```

每 20 秒发送全部元素 JSON（`syncAll: true` 跳过增量计算）。即使场景没变也触发加密+发送链路。这是丢帧兜底机制，但对大画板产生周期性带宽尖峰，且与增量机制部分冗余。所有成熟产品（Figma、Yjs、Google Docs）的全量同步只发生在首次加入时，之后只发增量。

#### A7. 快照并发 409 风暴

**证据**：每次 `broadcastScene` 都 `unawaited(_saveSceneSnapshot())`——高频输入下多个全量加密快照 PUT 在飞行中。`_saveSceneResolvingConflict()` 在 409 冲突时做完整 round-trip：加载全量快照 → 全量 reconcile → 重新加密 → 重新 PUT。高频并发下形成额外的全量读写风暴，而不是收敛。

---

### 问题 B：连接频繁断开

#### B1. Socket.IO emit() 是 fire-and-forget，无投递保证

**证据**：Socket.IO 默认只保证有序投递，不保证断线期间的到达。`emit()` 返回不代表已送达。当前文档变更走 `server-broadcast` → 服务端 `forward()` → `client.To(room).Emit()`，全程无 ACK、无事件序号、无恢复确认。断线期间发送的增量永久丢失，依赖 20 秒全量同步修复——但全量同步本身可能也被断连打断。

这是最根本的可靠性缺陷。`volatile` 消息（光标/在线状态）丢就丢了，但文档元素走的是非 volatile 的 `server-broadcast`，用户预期是不丢的。

#### B2. 服务端无背压，慢客户端导致发送缓冲区膨胀

**证据**：`hub.go:147-182` 的 `forward`：

```go
operator := client.To(socket.Room(roomID))
if volatile { operator = operator.Volatile() }
operator.Emit(EventClientBroadcast, frame.EncryptedBuffer, frame.IV)
```

`operator.Emit` 往接收方的 engine.io 写缓冲区塞数据，**无缓冲区深度检查、无背压**。一个网络慢的接收者（手机信号差）的发送队列无限增长，最终引擎因内存压力或写超时断开连接。结合 A1（无节流）和 A2（无压缩），几秒内缓冲区可膨胀到几十 MB。

#### B3. 重连后无 rejoin 完成确认

**证据**：`socket_io_realtime_transport.dart:123-134`：

```dart
socket.onReconnect((_) {
  _emitStatus(RealtimeConnectionStatus.reconnecting);
  socket.emit(_eventJoinRoom, activeRoomId);
});
```

重连后只 emit 了 `join-room`，**不等 `room-user-change` 确认已重新加入房间**。status 直接跳到 `joined`。在 rejoin 未完成时发的广播会失败（服务端校验 `currentRoomID != roomID` 返回 `room-error`），客户端收到 error 后可能触发更多断连逻辑。

#### B4. Socket.IO 允许 polling 回退

**证据**：客户端 `.setTransports(['websocket', 'polling'])`。当 WebSocket 建立不稳定时回退到 HTTP long-polling——每个帧是一次完整 HTTP 请求，大帧极易超时。移动网络切换（WiFi↔蜂窝）时握手期间 polling 反复失败。

另外，polling 传输下二进制数据的编码效率低于 websocket 的原生二进制帧。强制 websocket-only 消除这个不确定因素。

#### B5. 服务端 join-room 每次读取整个加密场景

**证据**：`hub.go` 的 `joinRoom` 调用 `roomExists`，底层是 `SceneStore.Load`——**从 Postgres 读取整个 `encrypted_buffer` BYTEA**，只为判断行是否存在。5 MB 场景每次有人加入都读 5 MB。频繁断连重连时 DB 压力和 join 延迟叠加。

#### B6. 连接参数未针对移动网络调优

**证据**：客户端使用 `socket_io_client` 默认重连参数（`reconnectionDelayMax` = 5s，无限重试），服务端 `SetPingInterval(25s)` + `SetPingTimeout(20s)`。默认值的问题：

- 移动网络切换（WiFi↔4G/5G）IP 变化导致 TCP 直接断开，但 socket_io 需要等 ping 超时才发现——最多 25s + 20s = 45s。
- 无限重连耗尽电量。
- 无平台网络状态监听（Android `ConnectivityManager` / 鸿蒙 `NetManager`），不会在网络恢复时主动重连。
- 无 App 前后台生命周期管理。

---

## 四、成熟产品参考

| 维度 | Figma | Excalidraw/Yjs | Google Docs | FlowMuse 当前 |
|------|-------|---------------|-------------|--------------|
| 冲突算法 | LWW（属性级） | CRDT（YATA） | OT（Jupiter） | LWW（元素级）✅ |
| 全量同步 | 仅首次连接 | 仅首次连接 | 仅首次连接 | **每 20s** ❌ |
| 消息编码 | 二进制 | 二进制 Uint8Array | 二进制 | JSON（未压缩）⚠️ |
| 批处理 | 33ms 窗口 | 16ms 事务 | ACK 规则 | **无** ❌ |
| 存在感 | ephemeral | Awareness CRDT | ephemeral | volatile ✅ |
| 连接恢复 | 状态差量 | 状态向量差量 | revision log | **全量场景** ❌ |
| 投递保证 | 服务端权威 | CRDT 最终一致 | OT + revision | **无（fire-and-forget）** ❌ |
| 离线支持 | 有限 | 原生（Yjs） | Buffer+Reconcile | **无** |

### 关键启示

1. **LWW 对白板场景是正确的冲突粒度**——Figma 用属性级 LWW 支撑全球最大设计协作平台。FlowMuse 的元素级 LWW 对白板足够，不需要升级到 CRDT。当前痛点在工程实现（编码/批处理/连接），不在算法。

2. **批处理窗口 16-33ms 是延迟和带宽的最优权衡**——Figma 33ms、Yjs 16ms、Google Docs ACK 自然合并。FlowMuse 当前完全没有。

3. **Presence 与文档数据必须分离**——FlowMuse 已通过 volatile 标记做到了，这点正确。

4. **投递可靠性不能靠全量同步兜底**——所有成熟产品都有显式的恢复协议（状态差量、revision log、CRDT 状态向量）。FlowMuse 用 20 秒全量同步充当可靠性方案，既不可靠又浪费带宽。

5. **不推荐现阶段集成 Yjs**——Flutter 端 CRDT 生态薄弱（需 js bridge 或 port），跨语言 + E2E 加密 + Excalidraw 兼容的迁移成本极高。应先穷尽当前架构的简单优化。

---

## 五、优化方案

### P0：客户端即时优化（1-2 天，不改协议）

目标：显著降低实时路径的数据量和 CPU 开销，无协议破坏。

#### P0-1 出站广播节流 + 本地/快照路径拆分

将 `_saveMarkdrawScene()` 的三合一职责拆开：

```
ChangeAccumulator（新增，集中接收 scene 变化）
  ├─ 本地草稿保存：500ms debounce，离开/后台时 flush
  ├─ 协作增量发送：50ms batch，按 elementId 仅保留最新版本
  └─ 封面生成：仅显式保存或闲置时
```

`broadcastScene()` 不再立即发送，而是标记脏元素 + 记录最新场景引用，50ms 定时器触发时取最新场景做增量计算 + 加密 + 发送。50ms 内多次编辑合并为一次发送（~20fps 远端同步），CPU 和网络负载降低 10-20 倍。

`initial: true` 和 `syncAll: true` 的调用跳过节流，立即发送。

**关键改动点**：`collaboration_repository.dart` 的 `broadcastScene` 方法、`whiteboard_page.dart` 的 `_saveMarkdrawScene`。

#### P0-2 实时通道启用 zlib 压缩

在 `_send` 路径中，`message.toBytes()`（明文 JSON 字节）之后加 zlib 压缩，再 AES-GCM 加密。接收端解密后先 zlib 解压再 `fromBytes`。

项目已有 `ExcalidrawBinaryCodec` 中的 zlib 能力，抽出轻量 `compress`/`decompress` 工具函数复用，不需新依赖。

消息头加 `compressed: true` 标志，保证向后兼容（旧客户端收到压缩消息应忽略而非崩溃）。

**预期收益**：实时载荷体积降低 80%+。

#### P0-3 快照保存降频 + 串行化

`broadcastScene()` 不再每次都 `unawaited(_saveSceneSnapshot())`。改为：
- 最后一次本地变更后 2 秒保存。
- 最长每 30 秒一次。
- 同一房间只允许一个快照请求在飞行（flight guard），避免 409 风暴。

#### P0-4 指针位置节流到 30fps

`_broadcastPointerPresence` 加 33ms 节流（时间戳判断）。最后一次移动后补发一帧（trailing call），保证松手后最终位置被同步。

#### P0-5 Dirty Set 替代 O(n) 全量扫描

维护 `_dirtyElementIds` 集合，在 `applyResult` 或 `reconcileRemoteScene` 后标记。`_changedElements()` 只遍历 dirty set 而非全量元素。1000 元素场景下每帧 CPU 减少 2-5ms。

#### P0-6 接收端合并窗口

接收端改为 16-33ms 合并窗口后再 `applyRemoteScene`，同一元素只应用最新版本，避免 UI 队列积压。

#### P0-7 全量同步定时器改为版本哈希校验

替换 20 秒全量场景推送。改为每 10-15 秒发送一个极小的版本哈希（< 100 bytes，volatile），接收端比对后只在不一致时主动拉快照修复。消除周期性带宽尖峰。

**P0 验收标准**：两台设备连续书写 60 秒，实时帧率不因场景增长持续下降；每秒场景 HTTP PUT ≤ 1 次；Socket 批次数 ≤ 20 次/秒。

---

### P1：可靠传输与服务端加固（3-5 天）

目标：网络切换或短断后协作不需要重新加入、不丢本地编辑。

#### P1-1 加密 Outbox + ACK + opId

客户端新增 SQLite 加密 outbox：
- 入队必须先于发送（先持久化再上线）。
- 每个可靠帧生成 `opId = clientId:monotonicSequence`。
- 服务端对 reliable frame 回 ACK，以短 TTL 的 `socketId + opId` 去重。
- ACK 后才从 outbox 删除。
- 断线后先 resume（`join(roomId, lastAckedOpId, snapshotVersion)`），再重放未确认 outbox。

明文载荷扩展（不改变密文边界，服务端不解析）：

```json
{
  "opId": "clientId:42",
  "baseSnapshotVersion": 42,
  "elements": ["仅本批最新版本的元素"]
}
```

`opId` 不是 CRDT 替代品，只是可靠发送、幂等重放和指标关联的最小单位。元素冲突仍由 `SceneReconciler` 裁决。

#### P1-2 重连状态机

显式配置重连参数：

| 参数 | 当前值 | 建议值 |
|------|--------|--------|
| reconnectionDelay | 1s（默认） | 1s（start） |
| reconnectionDelayMax | 5s（默认） | 30s（移动网络容错） |
| reconnectionAttempts | 无限 | 10-15 |
| transports | websocket + polling | **websocket only** |

新增：
- 平台网络状态监听（Android `ConnectivityManager` / 鸿蒙 `NetManager`），网络恢复时主动 `socket.connect()`。
- App 生命周期管理：`resumed` 时检查连接，`paused` 时可选保持或断开。
- 重连后等待 `room-user-change` 确认 rejoin 完成（复用 `_waitForRoomJoin()`），确认后才将 status 切到 `joined`。等待期间 status 保持 `reconnecting`，广播请求自然缓冲在 P0-1 的 coalesce 机制中。
- 从 `joined` 到 `synced` 的状态升级：仅在「快照/漏包补齐 + outbox 清空」后才进入 `synced`，不要仅凭 socket 已连接显示正常。

#### P1-3 服务端背压

`forward` 中对每个接收方检查 engine.io 发送缓冲区大小。超过阈值（如 2 MiB）时：
- volatile 消息直接丢弃（符合语义）。
- 非 volatile 消息丢弃并向发送方回 `room-error: "接收方缓冲区满"`，让发送方降速。
- 缓冲区持续超过 10 MiB 时主动断开慢客户端让它重连。

#### P1-4 服务端 join-room 轻量化

新增 `SceneStore.RoomExists(roomID)` 方法（`SELECT 1 FROM excalidraw_scenes WHERE room_id = $1`），`joinRoom` 改调这个。缓存活动房间的 `exists/ended` 元数据，结束房间时失效缓存。快照数据只在客户端主动 `GET /api/rooms/{id}/scene` 时读。

#### P1-5 Per-socket 限流

`forward` 中维护 per-socket 令牌桶。非 volatile 消息限 20 次/秒（配合 P0-1 的 50ms 节流正常不触发），volatile 消息限 30 次/秒。超限时 volatile 直接丢，非 volatile 回 error。

---

### P2：深度优化（1-2 周）

#### P2-1 适配器直通：消除 JSON 字符串中转

在 `MarkdrawController` 新增直接产出 Map 结构的方法，不经过 JSON 字符串：

```dart
Map<String, dynamic> serializeExcalidrawSceneMap();
void applyRemoteExcalidrawSceneMap(Map<String, dynamic> scene);
```

`ExcalidrawJsonCodec.serialize` 的逻辑不变，只是中间产物从 `String` 改成 `Map`，省掉 `jsonEncode` 和 `jsonDecode` 两次字符串解析。大画板下单次广播 CPU 开销降低 50%+。

#### P2-2 区域化广播

FlowMuse 已有 paged 布局。广播时只携带变更元素所在页面的元素，接收端只 reconcile 对应页面。`CollaborationMessage` 加 `pageId` 字段。对多页 PDF 笔记场景，单次广播元素数从几百降到几十。不需改服务端。

#### P2-3 观测与指标

将 `CollaborationDebugLog` 从 `debugPrint` 升级为脱敏结构化指标：连接耗时、重连次数、outbox 长度、batch 元素数/密文字节、ACK RTT、快照耗时/409 数、接收合并丢弃数。不记录 roomKey、token 或明文场景。增加 `/metrics` 端点或最小日志聚合。先量化再调参数。

#### P2-4 大元素优化

大型 freedraw 元素在抬笔前只同步低频预览/分段点，抬笔时发送最终元素。不将每个 pointer 点都变成完整元素 JSON。图片继续走对象存储，实时帧只同步 `fileId/status`。

---

### P3：架构演进（远期）

#### P3-1 服务端水平扩展：Redis 适配器

`zishang520/socket.io` 支持 Redis 适配器。`main.go` 中接入后，把 `Hub` 的 in-memory map（`roomUsers`/`socketRooms`/`followRooms`）迁移到 Redis。当前用户量不大时可不做，但需在架构文档标记为已知限制。

#### P3-2 Yjs/CRDT 迁移评估

仅当 P0-P2 完成后，5+ 人协作 P95 延迟仍 > 200ms，或离线编辑成为硬需求时，再做独立 ADR 评估。Flutter/Go 与 JS CRDT 的跨语言、E2E 加密、Excalidraw 兼容和迁移成本很高，不应作为性能修复的前置条件。

---

## 六、实现约束

以下约束在任何优化中不可违反：

- **保持 AES-GCM 端到端加密**；服务端不解析 scene 内容，不落明文。压缩发生在加密前。
- **保持 Excalidraw 元素语义**：`id/version/versionNonce/index/isDeleted` 不变。远端应用必须标记为非本地编辑，避免回声广播。
- **`volatile` 仅用于 cursor、idle、visible bounds**；文档元素绝不走 volatile 通道。
- **outbox 和快照元数据使用现有 SQLite / secure storage**，不引入 `shared_preferences`。
- **平台差异不进入业务层**；Android / 鸿蒙的网络生命周期监听放在 transport 适配层。
- **不以全量元素每 20 秒广播作为可靠性方案**；可靠性由 ACK、幂等 opId、outbox 和恢复协议提供。
- **新消息字段保持向后兼容**；旧客户端收到不认识的字段应忽略而非崩溃。

---

## 七、测试与验收矩阵

| 层级 | 场景 | 必须证明 |
|------|------|----------|
| 单元测试 | ChangeAccumulator 同元素多次更新、删除墓碑、版本倒退 | 仅最新有效元素被发送，删除不复活 |
| 单元测试 | outbox ACK / 重放 / 去重 | 重发幂等、ACK 后删除、重启后可恢复 |
| 集成测试 | 两客户端同时编辑不同元素、同一元素 | 合并结果符合 `SceneReconciler` |
| 集成测试 | 发送中断、重复帧、乱序帧 | 最终场景一致，无重复、无崩溃 |
| 服务端测试 | opId 去重、ACK、resume、房间缓存失效 | 不重复转发，房间结束后不能恢复 |
| 网络测试 | 10% 丢包、300ms RTT、10 秒断网、网络切换 | 自动恢复，outbox 清空，场景一致 |
| 性能测试 | 2/5/10 人，1k/5k 元素，连续书写和拖动 | P50/P95 消息大小、RTT、应用耗时在预算内 |
| 跨端验收 | Android、鸿蒙、Web 至少各一端配对 | 加入、断线恢复、笔迹/图片/删除一致 |

**建议首轮 SLO**：
- 本地改动到对端可见 P95 < 250ms（良好网络，非图片）。
- 短断线恢复到 `synced` P95 < 5s。
- 正常编辑期间不丢确认过的场景操作。
- 远端快照保存 P95 < 2s 且不阻塞实时渲染。

---

## 八、优先级矩阵

| 优化项 | 解决症状 | 改动量 | 风险 | 收益 | 阶段 |
|--------|----------|--------|------|------|------|
| P0-1 出站节流 + 路径拆分 | 同步慢、断连 | 中 | 低 | 极高 | **P0** |
| P0-2 实时 zlib 压缩 | 同步慢、断连 | 小 | 低 | 极高 | **P0** |
| P0-3 快照降频 + 串行化 | 同步慢 | 小 | 低 | 高 | **P0** |
| P0-4 指针 30fps 节流 | CPU 占用 | 极小 | 极低 | 中 | **P0** |
| P0-5 Dirty Set | CPU 占用 | 小 | 低 | 中 | **P0** |
| P0-6 接收端合并窗口 | 同步慢 | 小 | 低 | 中 | **P0** |
| P0-7 版本哈希校验替代全量同步 | 同步慢 | 中 | 低 | 高 | **P0** |
| P1-1 Outbox + ACK + opId | 断连、丢数据 | 大 | 中 | 极高 | **P1** |
| P1-2 重连状态机 | 断连 | 中 | 中 | 高 | **P1** |
| P1-3 服务端背压 | 断连 | 中 | 中 | 高 | **P1** |
| P1-4 join 轻量化 | 断连、延迟 | 小 | 低 | 中 | **P1** |
| P1-5 Per-socket 限流 | 断连、稳定性 | 中 | 中 | 中 | **P1** |
| P2-1 适配器直通 | 同步慢 | 大 | 中 | 高 | **P2** |
| P2-2 区域化广播 | 同步慢 | 大 | 中 | 高 | **P2** |
| P2-3 观测指标 | 可诊断性 | 中 | 低 | 中 | **P2** |
| P2-4 大元素优化 | 同步慢 | 中 | 中 | 中 | **P2** |
| P3-1 Redis 适配器 | 扩展性 | 大 | 高 | 远期 | **P3** |
| P3-2 Yjs/CRDT 评估 | 并发正确性、离线 | 极大 | 极高 | 远期 | **P3** |

**执行顺序**：先做 P0 全部七项（1-2 天，纯客户端，立即见效），然后 P1 五项（3-5 天，需前后端联动但风险可控），P2 视 P0-P1 实际效果决定，P3 纳入远期规划。

---

## 九、关键代码文件索引

| 文件 | 职责 | 优化关联 |
|------|------|----------|
| `collaboration/services/socket_io_realtime_transport.dart` | Socket.IO 传输层 | P0-2, P1-2 |
| `collaboration/repositories/collaboration_repository.dart` | 协作核心协调器 | P0-1/3/5/6/7, P1-1 |
| `collaboration/services/scene_reconciler.dart` | 场景合并算法 | P0-5 |
| `collaboration/services/whiteboard_collaboration_adapter.dart` | 控制器桥接 | P2-1 |
| `collaboration/services/excalidraw_binary_codec.dart` | zlib 编解码（当前仅用于文件） | P0-2（复用） |
| `collaboration/services/encrypted_scene_store.dart` | 快照 HTTP 持久化 | P0-3 |
| `whiteboard/views/whiteboard_page.dart` | 集成层、队列、presence | P0-1/4/6 |
| `FlowMuse-Server/internal/collab/hub.go` | 服务端房间管理、转发 | P1-3/4/5 |
| `FlowMuse-Server/internal/collab/http_api.go` | 房间/场景 HTTP API | P1-4 |
| `FlowMuse-Server/internal/storage/scene_store.go` | PostgreSQL 场景存储 | P1-4 |

---

## 十、参考

- [Excalidraw P2P 协作技术博客](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature) — FlowMuse 协作层的原型
- [Excalidraw CRDT 迁移 RFC #3537](https://github.com/excalidraw/excalidraw/issues/3537) — 全场景广播的局限与 CRDT 替代方案讨论
- [Excalidraw live collaboration 讨论 #8487](https://github.com/excalidraw/excalidraw/discussions/8487) — 社区协作问题与经验
- [Socket.IO Delivery Guarantees](https://socket.io/docs/v4/delivery-guarantees/) — emit() 投递语义，ACK + retry 实现
- [Socket.IO Connection State Recovery](https://socket.io/docs/v4/connection-state-recovery/) — 短断线会话恢复
- [Yjs Documentation](https://docs.yjs.dev) — CRDT 文档/awareness 协议参考
- [Automerge Sync](https://automerge.org/docs/tutorial/network-sync/) — 离线同步参考
- Evan Wallace, "How Figma's multiplayer technology works" — 属性级 LWW + 分数索引
- [tldraw sync](https://tldraw.dev/docs/collaboration) — 基于 Yjs 的生产级 CRDT 同步
