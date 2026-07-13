# FlowMuse 实时协作：问题诊断与优化方案

## 背景

协同测试中暴露出两个核心症状：**实时同步慢**和**连接频繁被断开**。本文基于对客户端（`FlowMuse-App/lib/features/whiteboard/collaboration/`）和服务端（`FlowMuse-Server/internal/collab/`）全部代码的逐文件审查，定位根因，并给出一套分阶段、可落地的优化方案。

文中的文件路径和行号均对应 `markdraw-harmonyos-probe` 分支当前代码。

---

## 一、现有协作架构概述

FlowMuse 的协作层是 Excalidraw E2EE 房间协议的忠实移植：

```
编辑器 (MarkdrawController)
  └─ onSceneChanged / onPointerPresence
       └─ WhiteboardPage (ConsumerState)
            ├─ WhiteboardCollaborationAdapter   ← 控制器 ↔ ExcalidrawScene 桥接
            └─ CollaborationRepository           ← 编排层
                 ├─ SocketIoRealtimeTransport     ← 加密帧的中继通道
                 ├─ HttpEncryptedSceneStore       ← 快照持久化（乐观锁）
                 ├─ HttpCollaborationFileStore    ← 图片二进制存储
                 ├─ CollaborationCrypto            ← AES-GCM-128
                 └─ SceneReconciler                ← 逐元素合并
```

**协议模型**：全场景广播 + 逐元素 LWW 合并。没有 OT，没有 CRDT，没有操作码。删除表示为 `{isDeleted: true}`。增量靠客户端记录 `_broadcastedElementVersions[id]→version`，只发版本号前进的元素——但每个被发的元素是完整 JSON，没有字段级 diff。

**服务端角色**：纯加密字节中继。服务端永远拿不到明文，无法 diff、无法 merge、无法限流。它只做两件事：校验发送者在房间内 + 帧不超过 8 MiB，然后 `client.To(room).Emit()` 转发。

---

## 二、根因分析

### 问题 A：实时同步慢

#### A1. 实时通道无压缩，纯 JSON + AES-GCM 上线

`collaboration_repository.dart` 的 `_send` 路径：

```
CollaborationMessage (JSON) → utf8.encode → AES-GCM encrypt → socket.emit
```

实时消息走的是 `message.toBytes()` = `utf8.encode(jsonEncode(...))`，**没有 zlib/gzip 压缩**。而项目里明明有 `ExcalidrawBinaryCodec`（zlib + AES-GCM + 长度前缀拼接），但它只被 `HttpCollaborationFileStore` 用于图片上传/下载，实时通道完全没用上。

Excalidraw 元素 JSON 冗余度极高——大量重复的字段名（`id`、`type`、`x`、`y`、`width`、`height`、`strokeColor`、`backgroundColor`...）、重复的默认值字符串。实测 1000 个元素的画板，JSON 可达数百 KB，gzip 后通常只剩 10-20%。

**影响**：每次广播的有效载荷比实际需要大 5-10 倍。在移动网络下，这直接表现为同步延迟。

#### A2. 出站无节流，每次编辑都触发全场景序列化 + 加密 + 发送

`whiteboard_page.dart:1373` 的 `onSceneChanged` 回调直接链到 `_broadcastCurrentScene()`，后者调用 `_collaborationAdapter.currentScene()`，再调 `repository.broadcastScene()`。

`currentScene()` 的实现路径（`whiteboard_collaboration_adapter.dart`）：

```
controller.serializeExcalidrawSceneJson()   → 整个场景序列化成 JSON 字符串
jsonDecode(...)                              → 再解析回 Map
ExcalidrawScene.fromJson(...)                → 再深拷贝
```

一次拖拽操作会在一秒内触发几十次 `onSceneChanged`，每次都走完整的「序列化字符串 → 解析 → 深拷贝 → 加密 → emit」流程。repository 层**没有任何 debounce/coalesce**——唯一的门控是 `sceneVersion <= _lastBroadcastedOrReceivedSceneVersion` 的版本判断，但拖拽过程中元素 version 每帧都在涨，所以每次都会过。

**影响**：拖拽一个元素时，CPU 被全场景序列化和加密占满，主线程卡顿，同时网络被大量密集帧挤满，接收端来不及处理。

#### A3. 适配器的冗余 JSON 往返

上一点提到的 `currentScene()` 三段式往返（序列化→解析→深拷贝）在**每次出站广播**和**每次入站应用**各执行一次。对于大画板，这是单次操作中最大的 CPU 开销——远超加密本身。

根因是编辑器内核的数据模型和 `ExcalidrawScene`（协作用的中间表示）之间没有直接映射，必须经过 JSON 字符串中转。

#### A4. `ExcalidrawScene.copyWith` 逐元素深拷贝

`excalidraw_scene.dart` 的 `copyWith` 对每个元素做 `Map<String, Object?>.from(...)` 递归深拷贝。`SceneReconciler.reconcile` 每次合并都会触发这个拷贝。远程更新密集时，GC 压力极大。

#### A5. 20 秒全量同步定时器

`collaboration_repository.dart:705`：

```dart
_fullSceneSyncTimer = Timer.periodic(fullSceneSyncInterval, (_) {
  unawaited(broadcastScene(room: room, scene: _latestScene, syncAll: true));
});
```

每 20 秒无条件广播全量场景（`syncAll: true` 跳过增量计算）。这是丢帧兜底机制，但对于大画板，它会产生周期性的带宽尖峰，而且和增量机制部分冗余。

#### A6. 指针位置每次移动都加密发送

`whiteboard_page.dart:1465` 的 `_broadcastPointerPresence` 在每次指针移动时触发，走 `server-volatile-broadcast`（volatile 不错），但仍然每帧做一次 AES-GCM 加密。指针消息体很小（几十字节的 JSON），但加密的异步开销是固定的。密集移动时这是无效的 CPU 消耗。

---

### 问题 B：连接频繁断开

#### B1. 服务端无背压，慢客户端导致发送缓冲区膨胀

`hub.go:147-182` 的 `forward` 函数：

```go
operator := client.To(socket.Room(roomID))
if volatile {
    operator = operator.Volatile()
}
operator.Emit(EventClientBroadcast, frame.EncryptedBuffer, frame.IV)
```

`operator.Emit` 只是往接收方的 engine.io 写缓冲区里塞数据，**没有缓冲区深度检查，没有背压**。如果某个接收者网络慢（比如手机信号差），它的发送队列会无限增长，最终引擎可能因为内存压力或写超时断开连接。

结合 A1（无压缩，帧体积大 5-10 倍）和 A2（无节流，帧频率高），一个慢客户端的发送队列会在几秒内膨胀到几十 MB。

#### B2. 全局互斥锁在广播热路径上

`hub.go:158-160`，每次 `forward` 都要拿 `h.mu` 查 `socketRooms[socketID]`：

```go
h.mu.Lock()
currentRoomID := h.socketRooms[socketID]
h.mu.Unlock()
```

所有房间共用一把锁。高并发时（多个房间同时广播），join/leave 和广播互相竞争这把锁。临界区很短（一次 map 查找），影响有限，但在极端情况下会放大延迟。

#### B3. 重连后无 rejoin 完成确认

`socket_io_realtime_transport.dart:123-134`：

```dart
socket.onReconnect((_) {
  _emitStatus(RealtimeConnectionStatus.reconnecting);
  socket.emit(_eventJoinRoom, activeRoomId);
});
```

重连后只是 emit 了 `join-room`，但**没有等待 `room-user-change` 确认自己已重新加入房间**。status 直接从 `reconnecting` 跳到 `joined`（靠 socket 层的 connected 事件）。在 rejoin 尚未完成时发的广播会失败（服务端校验 `currentRoomID != roomID` 会返回 `room-error`），客户端收到 error 后可能进一步触发断连逻辑。

#### B4. Socket.IO 配置允许 polling 回退

`socket_io_realtime_transport.dart:96`：

```dart
.setTransports(['websocket', 'polling'])
```

当 WebSocket 建立不稳定时，会回退到 HTTP long-polling。polling 模式下每个帧是一次完整的 HTTP 请求，8 MiB 的帧还要 base64 编码（+33% 体积），极易超时断开。这在移动网络切换（WiFi↔蜂窝）时尤其常见——握手期间 polling 会反复失败。

#### B5. 服务端 join-room 每次读取整个加密场景

`hub.go:294-302`，`joinRoom` 调用 `roomExists`，底层是 `SceneStore.Load`——**从 Postgres 读取整个 `encrypted_buffer` BYTEA**，只为判断行是否存在。一个 5 MB 的场景，每次有人加入房间都读 5 MB。在频繁断连重连的场景下，这会造成 DB 压力和 join 延迟，进一步触发超时。

#### B6. 无限流、无连接数上限

服务端没有 `SetMaxConnection`，没有 per-socket 或 per-IP 限流，也没有发送频率限制。一个快速广播的客户端可以无限制地打满服务端。虽然不会直接导致「被断开」，但会导致服务端资源耗尽，间接影响所有连接的稳定性。

#### B7. ping/pong 间隔偏大但可接受

`main.go:85-86`：`SetPingInterval(25s)`、`SetPingTimeout(20s)`。死连接检测需要 25-45 秒。这个值本身不算问题，但在移动网络瞬断场景下（几秒的信号丢失），25 秒的 ping 间隔意味着可能等到下一次 ping 才发现连接断了，用户感知到的是「好一会儿没反应然后突然断开」。

---

## 三、优化方案

按「投入产出比」和「改动风险」分三个阶段。阶段一不改协议、不改服务端架构，纯客户端调优，风险最低、收益最直接。

### 阶段一：客户端即时优化（不改协议，1-2 天）

这是针对「同步慢」和「断连」最直接有效的改动。

#### 1.1 出站广播节流（coalesce + debounce）

**问题**：A2，拖拽时每帧都全量序列化+加密+发送。

**方案**：在 `CollaborationRepository` 中加一个 coalesce 定时器。`broadcastScene` 不立即发送，而是：

1. 标记「有待发送的场景」+ 记录最新场景引用。
2. 启动一个短定时器（建议 50ms，约 20fps）。
3. 定时器触发时，取最新场景做一次增量计算 + 加密 + 发送。

50ms 内的多次编辑合并为一次发送。拖拽体验仍然流畅（20fps 的远端同步足够），但 CPU 和网络负载降低 10-20 倍。

```
关键改动点：collaboration_repository.dart 的 broadcastScene 方法
新增字段：_pendingBroadcastTimer, _pendingBroadcastScene
注意：initial: true 和 syncAll: true 的调用应跳过节流，立即发送
```

#### 1.2 实时通道启用 zlib 压缩

**问题**：A1，JSON 无压缩上线。

**方案**：在 `_send` 路径中，`message.toBytes()` 之后加一层 zlib 压缩，再 AES-GCM 加密。接收端解密后先 zlib 解压再 `fromBytes`。

项目已有 `ExcalidrawBinaryCodec` 中的 zlib 能力，可以抽出一个轻量的 `compress`/`decompress` 工具函数复用，不需要引入新依赖。

需要在消息头中加一个 `compressed: true` 标志位（或用消息类型前缀区分），保证和旧客户端的兼容性（旧客户端收到压缩消息应忽略而非崩溃）。

**预期收益**：实时载荷体积降低 80%+，直接缓解 A1 和 B1（发送缓冲区膨胀）。

#### 1.3 指针位置节流到 30fps

**问题**：A6，每次指针移动都加密。

**方案**：在 `_broadcastPointerPresence` 中加一个简单的 33ms 节流（`Timer` 或时间戳判断）。最后一次移动后补发一帧（trailing call），保证松手后的最终位置被同步。

#### 1.4 重连后等待 rejoin 确认

**问题**：B3，重连后不等 rejoin 就发广播。

**方案**：在 `onReconnect` 中 emit `join-room` 后，复用现有的 `_waitForRoomJoin()` 逻辑等待 `room-user-change` 确认。确认后才将 status 切到 `joined`。等待期间 status 保持 `reconnecting`，`broadcastScene` 应缓冲请求（和 1.1 的 coalesce 机制自然结合）。

加一个 rejoin 超时（如 10s），超时则标记 `failed` 并提示用户。

---

### 阶段二：服务端加固 + 协议微调（3-5 天）

#### 2.1 服务端加背压：慢客户端断开

**问题**：B1，发送缓冲区无上限。

**方案**：在 `forward` 中，对每个接收方检查其 engine.io 发送缓冲区大小（`zishang520/socket.io` 暴露了 `socket.BufferSize()` 或类似 API，需确认）。如果超过阈值（如 2 MiB）：

- volatile 消息：直接丢弃（已经是 volatile 的语义）。
- 非 volatile 消息：丢弃并向发送方回一个 `room-error: "接收方缓冲区满"`，让发送方降速。

极端情况（缓冲区持续超过 10 MiB）主动断开慢客户端，让它重连——比让整个房间卡死好。

#### 2.2 join-room 改用轻量存在性检查

**问题**：B5，每次 join 读取整个加密场景。

**方案**：在 `SceneStore` 中加一个 `RoomExists(roomID)` 方法，用 `SELECT 1 FROM excalidraw_scenes WHERE room_id = $1` 代替 `Load`。`joinRoom` 改调这个。快照数据只在客户端主动 `GET /api/rooms/{id}/scene` 时才读。

#### 2.3 强制 WebSocket 传输

**问题**：B4，polling 回退导致大帧超时。

**方案**：客户端 `setTransports(['websocket'])`，去掉 polling 回退。WebSocket 建立失败就直接报错让用户重试，不要回退到 polling 模式。

前提是服务端也只开 websocket（`socketOptions.SetTransports(socket.TransportWebsocket)`），避免握手歧义。

#### 2.4 全量同步定时器改为自适应

**问题**：A5，20 秒固定全量同步。

**方案**：把 `fullSceneSyncInterval` 从固定 20 秒改为自适应：

- 最近有增量广播时，间隔延长到 60-120 秒（增量已经覆盖了，全量只是兜底）。
- 最近无广播（空闲）时，保持 20 秒。
- 收到 `new-user` 事件时立即触发一次（已有逻辑）。

或者更简单：直接把间隔改长到 60 秒，并依赖 new-user 时的 sceneInit 兜底新加入者。

#### 2.5 限流：per-socket 广播频率上限

**问题**：B6，无限流。

**方案**：在 `forward` 中维护一个 per-socket 的令牌桶或滑动窗口。非 volatile 消息限制为每秒 20 次（配合客户端 1.1 的 50ms 节流，正常不会触发），volatile 消息限制为每秒 30 次。超限时 volatile 直接丢，非 volatile 排队或回 error。

---

### 阶段三：架构级优化（长期，1-2 周）

这部分是更深层的改动，解决阶段一、二无法覆盖的根本问题。

#### 3.1 适配器直通：消除 JSON 字符串中转

**问题**：A3，`currentScene()` / `applyRemoteScene` 的序列化→解析→深拷贝往返。

**方案**：在 `MarkdrawController` 上新增两个直接产出 `ExcalidrawScene`（或等价 Map 结构）的方法，不经过 JSON 字符串：

```dart
// 直接从内核数据结构构建 Map，跳过 jsonEncode+jsonDecode
Map<String, dynamic> serializeExcalidrawSceneMap();
// 直接从 Map 应用到内核，跳过 jsonEncode+jsonDecode
void applyRemoteExcalidrawSceneMap(Map<String, dynamic> scene);
```

这是一次内部重构——`ExcalidrawJsonCodec.serialize` 的逻辑不变，只是把中间产物从 `String` 改成 `Map`，省掉 `jsonEncode` 和 `jsonDecode` 两次字符串解析。

**预期收益**：大画板下单次广播的 CPU 开销降低 50%+，这是比压缩更大的收益。

#### 3.2 乐观更新 + 区域化广播

**问题**：全场景广播在元素数量多时开销不可控。

**方案**：借鉴 tldraw sync 的思路——把画板按页面（FlowMuse 已有 paged 布局）分区。广播时只携带当前页面的元素，或者携带「变更元素所在页面」的标记。接收端只 reconcile 对应页面。

这不需要改服务端（服务端只是中继），只需要在 `CollaborationMessage` 中加一个 `pageId` 字段，客户端按 pageId 路由到对应页面的 reconcile 逻辑。

对于多页 PDF 笔记（你们的典型场景），这能把单次广播的元素数从几百降到几十。

#### 3.3 服务端水平扩展：Redis 适配器

**问题**：服务端是单进程，无法水平扩展。

**方案**：`zishang520/socket.io` 支持 Redis 适配器。在 `main.go` 中：

```go
import "github.com/zishang520/socket.io/v2/redis"

adapter := redis.NewRedisAdapter(&redis.RedisAdapterOptions{
    PubSub: redisClient,
})
io.SetAdapter(adapter)
```

同时把 `Hub` 中的 `roomUsers`/`socketRooms` 等 in-memory map 迁移到 Redis（或只迁移跨实例需要的部分）。

这是大工程，但如果不做，服务端永远是单点。当前用户量不大时可以不做，但要在架构文档中标记为已知限制。

#### 3.4 考虑 Yjs/CRDT 迁移（远期）

Excalidraw 社区自己也在讨论 CRDT 迁移（[Issue #3537](https://github.com/excalidraw/excalidraw/issues/3537)）。当前的全场景广播 + LWW 在并发编辑同一元素时会有 last-writer-wins 覆盖问题，虽然 `protectedElementIds` 缓解了文本编辑冲突，但不是根本解法。

tldraw 已经用 Yjs 做了生产级的 CRDT 同步（`tldraw sync`）。如果未来要支持离线编辑、更复杂的并发场景，迁移到 CRDT 是正确方向。但这等于重写协作层，成本极高，不建议在当前阶段做。

---

## 四、优先级矩阵

| 优化项 | 解决症状 | 改动量 | 风险 | 收益 | 优先级 |
|--------|----------|--------|------|------|--------|
| 1.1 出站节流 50ms | 同步慢、断连 | 小 | 低 | 极高 | **P0** |
| 1.2 实时 zlib 压缩 | 同步慢、断连 | 小 | 低 | 极高 | **P0** |
| 1.3 指针 30fps 节流 | CPU 占用 | 极小 | 极低 | 中 | **P0** |
| 1.4 重连等 rejoin | 断连 | 小 | 低 | 高 | **P0** |
| 2.1 服务端背压 | 断连 | 中 | 中 | 高 | **P1** |
| 2.2 轻量 join 检查 | 断连、延迟 | 小 | 低 | 中 | **P1** |
| 2.3 强制 websocket | 断连 | 极小 | 低 | 中 | **P1** |
| 2.4 自适应全量同步 | 同步慢 | 小 | 低 | 中 | **P1** |
| 2.5 per-socket 限流 | 断连、稳定性 | 中 | 中 | 中 | **P2** |
| 3.1 适配器直通 | 同步慢 | 大 | 中 | 高 | **P2** |
| 3.2 区域化广播 | 同步慢 | 大 | 中 | 高 | **P2** |
| 3.3 Redis 适配器 | 扩展性 | 大 | 高 | 远期 | **P3** |
| 3.4 Yjs/CRDT | 并发正确性 | 极大 | 极高 | 远期 | **P3** |

**建议执行顺序**：先做 P0 全部四项（1-2 天，纯客户端，立即见效），然后 P1 四项（3-5 天，需要改服务端但风险可控），P2 视实际效果决定是否需要，P3 纳入远期规划。

---

## 五、参考

- [Excalidraw P2P 协作技术博客](https://plus.excalidraw.com/blog/building-excalidraw-p2p-collaboration-feature) — FlowMuse 协作层的原型
- [Excalidraw live collaboration 讨论 #8487](https://github.com/excalidraw/excalidraw/discussions/8487) — 社区反馈的协作问题与经验
- [Excalidraw CRDT 迁移 RFC #3537](https://github.com/excalidraw/excalidraw/issues/3537) — 全场景广播的局限与 CRDT 替代方案讨论
- [tldraw sync 文档](https://tldraw.dev/docs/collaboration) — 基于 Yjs 的生产级 CRDT 同步，区域化广播和增量同步的参考
- [Excalidraw throttleRAF 性能优化](https://www.linkedin.com/pulse/excalidraw-enhancing-motion-performance-through-dany-valverde-caldas-kni3c) — 渲染节流机制，可借鉴到广播节流
