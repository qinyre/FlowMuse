# FlowMuse 实时协作性能与稳定性优化调研

> 调研日期：2026-07-12  
> 结论依据：当前 Flutter/Go 源码静态审计、既有协作约束、Socket.IO / Yjs / Automerge / Excalidraw 公开资料。  
> 范围：实时元素同步、断线恢复、快照持久化、在线状态；不改变端到端加密和 Excalidraw 元素兼容性。

## 1. 结论

当前体验差的主因不是 Socket.IO 本身，而是应用层把 **每一次画布变更** 同时当成：

1. 本地持久化任务；
2. 实时网络任务；
3. 服务端全量快照任务。

一笔书写会持续触发 `onSceneChanged`。当前路径会立即全量序列化场景、写本地 SQLite、生成封面、加密、发 Socket 消息，并异步执行一次 HTTP 全量加密快照保存。随着笔迹增长，单次操作的数据量和 CPU/IO 成本线性增加；多次未串行的快照请求还会互相触发 409 冲突与 reload/reconcile/retry。这个设计足以解释“同步慢、越写越慢、网络稍有波动就像断开”。

推荐保留现有 Socket.IO、AES-GCM、元素 `version/versionNonce` 和 `SceneReconciler`，在其上改为：**有界频率的增量实时通道 + 本地 outbox + 低频且串行的全量快照 + 明确的重连状态机**。这比替换成 Yjs/Automerge 风险小一个数量级，并能直接解决当前主要问题。

## 2. 当前机制与证据

```text
MarkdrawController.applyResult()
  └─ onSceneChanged（每次 scene-changing ToolResult）
      └─ WhiteboardPage._saveMarkdrawScene()
          ├─ serializeScene(全场景)
          ├─ SQLite saveScene + 生成封面 + 更新资料库
          └─ CollaborationRepository.broadcastScene()
              ├─ 加密 changed elements 后 Socket.IO emit
              └─ unawaited(_saveSceneSnapshot(全场景 HTTP PUT))
```

| 观察到的实现 | 影响 | 证据位置 |
| --- | --- | --- |
| `onSceneChanged` 直接调用 `_saveMarkdrawScene()`，没有节流或合并 | 指针移动/元素拖动期间可重复启动全链路工作 | `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart:1373` |
| `_saveMarkdrawScene()` 每次都序列化整张场景、写本地库、生成缩略图，随后广播 | 本地 CPU、SQLite、图片编码与网络争用；大场景延迟明显放大 | 同文件 `:277` |
| `broadcastScene()` 虽只发送变更元素，但每次成功发送都 `unawaited` 保存全量远端快照 | 高频输入可堆积 HTTP PUT、AES-GCM、JSON/Base64；并发快照会发生 409 | `.../collaboration_repository.dart:236`、`:566` |
| 快照冲突处理是“拉全量快照 → reconcile → 再保存” | 高频并发下会形成额外全量读写风暴，而不是收敛 | 同文件 `_saveSceneResolvingConflict()` |
| 每 20 秒再发送一次全量实时场景 | 正常会话也周期性产生大包；对恢复没有确认语义 | 同文件 `fullSceneSyncInterval`、`_startFullSceneSync()` |
| 接收消息按单一 Future 队列逐条解密、解析、再切 UI 稳定帧应用 | 大量历史消息会排队，画面显示落后于网络接收 | 同文件 `_messageDecodeQueue`；`whiteboard_page.dart:_remoteSceneQueue` |
| Socket.IO 只启用默认重连；重连时只 `join-room`，之后由页面 HTTP 拉快照并重新全量发送 | 无未确认消息队列、无事件序号、无恢复完成确认；短断线中的增量可能丢失 | `socket_io_realtime_transport.dart:onReconnect`；`whiteboard_page.dart:_refreshCollaborationSnapshot` |
| 服务端对每次 join 调用 `sceneStore.Load()` 和 `roomStore.LoadRoom()` | 重连高峰时加入房间需同步访问数据库，增加恢复路径不确定性 | `FlowMuse-Server/internal/collab/hub.go:joinRoom` |
| 服务端转发不回 ACK、不保存实时事件 | Socket.IO 默认“至多一次”投递，断线中发送的事件没有应用层确认 | `hub.go:forward`；Socket.IO 官方投递保证 |

### 2.1 已有可复用基础

- `SceneReconciler` 已能基于 Excalidraw 的 `version/versionNonce` 合并增量；不应为了“上 CRDT”而推倒重来。
- `EncryptedSceneStore` 已有乐观锁快照元数据，适合作为灾难恢复与最终持久化，而非热路径。
- `RealtimeTransport` 已抽象传输层，能在不污染编辑器的前提下加入 ACK、重连和指标。
- 鼠标、空闲状态与可视范围已使用 volatile 通道，说明代码已有“可丢失 presence”和“不可丢失文档”两类消息的基础区分。

## 3. 与成熟方案的差距及可借鉴点

| 成熟实践 | 可确认的机制 | 对 FlowMuse 的具体含义 |
| --- | --- | --- |
| Socket.IO | 默认仅保证顺序，不保证断线期间的到达；客户端可通过 ACK + retry 实现至少一次投递，服务端到客户端需事件 ID / offset 或连接状态恢复。 | 文档变更必须有 `opId`、ACK 和本地待发队列；不能把 `emit()` 返回当成已送达。[
官方文档](https://socket.io/docs/v4/delivery-guarantees/) |
| Socket.IO | Connection State Recovery 可以恢复短断线的会话与漏包，但仍必须准备同步兜底。 | 先确认 Go Socket.IO 库是否支持；若不支持，按 `lastAckedOpId` 自建恢复协议即可，不必等待替换库。[
官方文档](https://socket.io/docs/v4/connection-state-recovery/) |
| Yjs | 文档增量和 awareness 分离；awareness 不写入文档，采用心跳与超时判定在线。 | 光标/在线状态保持 volatile、限频、可丢；元素操作走可靠通道。在线状态不应因为一次 Socket `disconnect` 就永久判定离开。[
Yjs awareness](https://docs.yjs.dev/api/about-awareness) |
| Yjs / Automerge | 本地先持久化，再只同步尚未同步的增量；网络与存储是可组合适配器。 | FlowMuse 已有 SQLite，可最小化实现加密 outbox，而无需引入 JS CRDT 运行时。[
Yjs offline](https://docs.yjs.dev/getting-started/allowing-offline-editing)；[
Automerge sync](https://automerge.org/docs/tutorial/network-sync/) |
| Excalidraw | `onChange` 可在微小变更时频繁触发，官方讨论明确建议 debounce 并用 scene version 避免无意义保存。 | 将持久化与协作发送从 UI 回调中解耦，合并变更是符合目标生态的做法。[
Excalidraw 讨论](https://github.com/excalidraw/excalidraw/discussions/3778) |

## 4. 推荐目标架构

```text
编辑器变更
  ├─ 立即更新本地画布（不等网络）
  ├─ ChangeAccumulator：按 elementId 覆盖合并最新版本
  ├─ Local outbox（加密 op，持久化，未 ACK 不删除）
  ├─ 40–80 ms 批量 flush：只发 changed elements + opId + base/clock
  │    └─ 服务器校验房间后转发并 ACK sender
  ├─ 接收端：按短窗口合并 elementId，单帧最多应用一次
  └─ SnapshotScheduler：闲置 2 s 或每 30 s 串行保存一次全场景
       └─ 离开、后台、明确保存时强制 flush；409 时单次 reconcile 后重试

Socket 断开
  ├─ 保留 outbox 和当前场景，界面为“正在恢复”，继续离线编辑
  ├─ 指数退避 + 抖动重连
  ├─ join/resume(roomId, lastAckedOpId, snapshotVersion)
  ├─ 服务端补齐可得 op；否则客户端拉一次快照、reconcile
  └─ 重放 outbox，收到 ACK 后逐项删除，状态才变为“已同步”
```

### 协议最小扩展

不改变密文边界：`opId`、`sequence`、`kind`、`elements` 等内容仍与协作消息一起 AES-GCM 加密；服务端只读取 `roomId` 和转发必需的外层帧标识。服务端以 `socketId + opId` 做短期去重，ACK 只确认密文帧已被服务器接受，不代表每个远端已渲染。

```json
{
  "frameId": "uuid",
  "kind": "scene-update",
  "ciphertext": "...",
  "iv": "..."
}
```

明文载荷建议为：

```json
{
  "opId": "clientId:monotonicSequence",
  "baseSnapshotVersion": 42,
  "elements": ["仅本批最新版本的元素"]
}
```

`opId` 不是 CRDT 的替代品，而是可靠发送、幂等重放和指标关联的最小单位。元素冲突仍由现有 `SceneReconciler` 裁决。

## 5. 分阶段实施方案

### P0：先止血（1 个迭代）

目标：显著降低实时路径的数据量和并发，无协议破坏。

1. 新增 `CollaborationChangeScheduler`，集中接收本地 scene 变化；每 50 ms 合并一次，按 `elementId` 仅保留最新元素版本。
2. 将 `_saveMarkdrawScene()` 拆成：本地草稿保存（500 ms debounce，离开时 flush）、协作增量发送（50 ms batch）、封面生成（仅显式保存/闲置时）。
3. `broadcastScene()` 不再对每个 batch 保存远端快照。改为：最后一次本地变更后 2 秒保存，最长每 30 秒一次；同一房间只允许一个快照请求在飞行。
4. 接收端改为 16–33 ms 合并窗口后再 `applyRemoteScene`；同一元素只应用最新版本，避免 UI 队列积压。
5. 保留现有 20 秒全量同步仅作为过渡期开关；P0 验证后删除或改成“仅重连失败后的兜底”。

验收：两台设备连续书写 60 秒，实时帧率不因场景增长持续下降；每秒场景 HTTP PUT 不超过 1 次，正常书写时 Socket 批次数不超过 20 次/秒。

### P1：可靠重连（1 个迭代）

目标：网络切换或后台短断后，协作不需要用户重新加入，不丢本地编辑。

1. 加入 SQLite 加密 outbox：入队必须先于发送；ACK 后删除。设置空间上限和合并规则：同一 elementId 的未 ACK 更新可覆盖，仅删除墓碑不能提前丢弃。
2. 扩展 `RealtimeTransport` 为 `sendReliable()` / `acknowledgements` / `resume()`；为普通 scene batch 生成 `opId`。
3. 服务端对 reliable frame 回 ACK、以短 TTL 的 `socketId + opId` 去重；断线后客户端先 resume，再重放未确认 outbox。
4. 重连策略显式配置：指数退避、抖动、无限或较高次数尝试；从 `joined` 仅在“快照/漏包补齐 + outbox 清空”后进入 `synced`，不要仅凭 socket 已连接显示正常。
5. 断开时保留远端 cursor 的最后状态短暂淡出；presence 用 30 秒 TTL 心跳，不将短暂 TCP 断开直接等同于成员离开。

验收：编辑中切换 Wi-Fi/蜂窝或断网 10 秒后恢复；双方最终元素集合、元素 version 和内容一致；断网期间本端新增元素恢复后均到达对端；无重复元素。

### P2：服务端恢复与观测（1 个迭代）

目标：把“偶发断开”变为可定位事件，并缩短重连恢复时间。

1. 评估 `zishang520/socket.io` 是否支持 Socket.IO connection state recovery；若不支持，保留 P1 的 `lastAckedOpId` 恢复日志，不为了该特性迁移整套 Socket.IO 服务端。
2. 缓存活动房间的 `exists/ended` 元数据，避免每次 reconnect 的 `joinRoom()` 都加载加密场景；结束房间时失效缓存。
3. 所有日志改为脱敏结构化指标：连接耗时、重连次数、outbox 长度、batch 元素数/密文字节、ACK RTT、快照耗时/409 数、接收合并丢弃数。不得记录 roomKey、token 或明文场景。
4. 增加 `/metrics` 或最小日志聚合，按 Android / HarmonyOS / Web 区分。先量化再调 ping：当前服务端 25 s ping + 20 s timeout 是合理起点，不能仅凭感觉缩短心跳。

验收：一次异常会话能从指标定位到 DNS/连接、重连、ACK、快照或 UI 应用中的哪一层；95% 重连在目标网络条件下恢复到 `synced` 的时间可量化。

### P3：大场景与长期演进（按数据决定）

1. 大型 freedraw 元素在抬笔前只同步低频预览/分段点，抬笔时发送最终元素；不要将每个 pointer 点都变成完整元素 JSON。
2. 图片继续走对象存储，不进入实时场景帧；实时帧只同步 `fileId/status`。
3. 快照服务端可做压缩、分块或对象存储转移，但压缩发生在 AES-GCM 前、密文不做有损转换。
4. 仅当 P0–P2 数据证明 LWW 元素合并无法满足多人同时编辑同一元素/富文本的需求时，再做独立 ADR 评估 Yjs/Automerge。Flutter/Go 与 JS CRDT 的跨语言、E2E 加密、Excalidraw 兼容和迁移成本很高，不应作为本轮性能修复的前置条件。

## 6. 关键实现约束

- 保持 AES-GCM 端到端加密；服务端不解析 scene 内容，不落明文。
- 保持 Excalidraw 元素 `id/version/versionNonce/index/isDeleted` 语义；远端应用必须标记为非本地编辑，避免回声广播。
- outbox、快照元数据和连接状态使用现有 SQLite / secure storage 约束，不引入 `shared_preferences`。
- `volatile` 仅用于 cursor、idle、visible bounds；文档元素绝不走 volatile 通道。
- 不以“全部元素每 20 秒广播”作为可靠性方案。可靠性应由 ACK、幂等 `opId`、outbox 和恢复协议提供。
- 平台差异不进入业务层；Android / 鸿蒙的网络生命周期监听放在 transport 适配层，公共协议与调度器共享。

## 7. 测试与验收矩阵

| 层级 | 场景 | 必须证明 |
| --- | --- | --- |
| 单元测试 | ChangeAccumulator 同元素多次更新、删除墓碑、版本倒退 | 仅最新有效元素被发送，删除不复活 |
| 单元测试 | outbox ACK / 重放 / 去重 | 重发幂等、ACK 后删除、重启后可恢复 |
| 集成测试 | 两客户端同时编辑不同元素、同一元素 | 合并结果符合 `SceneReconciler` |
| 集成测试 | 发送中断、重复帧、乱序帧 | 最终场景一致，无重复、无崩溃 |
| 服务端测试 | `opId` 去重、ACK、resume、房间缓存失效 | 不重复转发，房间结束后不能恢复 |
| 网络测试 | 10% 丢包、300 ms RTT、10 秒断网、网络切换 | 自动恢复，outbox 清空，场景一致 |
| 性能测试 | 2/5/10 人，1k/5k 元素，连续书写和拖动 | P50/P95 消息大小、RTT、应用耗时、内存和快照频率在预算内 |
| 跨端验收 | Android、鸿蒙、Web 至少各一端配对 | 加入、断线恢复、笔迹/图片/删除一致 |

建议首轮 SLO：本地改动到对端可见 P95 < 250 ms（良好网络，非图片）；短断线恢复到 `synced` P95 < 5 s；正常编辑期间不丢确认过的场景操作；远端快照保存 P95 < 2 s 且不阻塞实时渲染。

## 8. 优先级与取舍

| 方案 | 收益 | 风险/成本 | 决策 |
| --- | --- | --- | --- |
| P0 调度、批处理、串行快照 | 直接降低当前主路径负载 | 小，保持协议兼容 | 立即做 |
| P1 outbox + ACK + resume | 解决短断线丢更改和“假连接” | 中，需要前后端协议测试 | 紧随 P0 |
| P2 指标与活动房间缓存 | 可诊断、缩短恢复路径 | 小到中 | 与 P1 并行设计、随后落地 |
| 直接切 Yjs/Automerge | 长期 CRDT 能力 | 高，跨语言/E2E/格式迁移复杂 | 暂不做 |
| 仅缩短 ping / 增加重连次数 | 可能掩盖部分网络问题 | 不能解决高频全量保存或丢包 | 不单独做 |

## 9. 建议的首个实施任务

先实现 P0，并在同一变更中增加最小性能日志与测试。原因是它不触及密钥、服务器持久化格式或 Excalidraw 数据模型，却能验证主要瓶颈是否来自当前热路径。P0 指标改善后，再以真实的断网测试数据确定 P1 的 ACK/outbox 参数，而不是猜测重连次数或心跳值。

