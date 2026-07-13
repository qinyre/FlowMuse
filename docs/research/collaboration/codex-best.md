# FlowMuse 协作性能与稳定性优化方案（综合评审版）

> 日期：2026-07-12  
> 整合：`claude-best.md`、`zcode-best.md`、原 `codex-best.md` 及当前 Flutter / Go 源码。  
> 评审目标：在不破坏端到端加密、Excalidraw 兼容和跨端行为的前提下，解决实时同步慢、短断线易失步和恢复状态不可信的问题。

## 1. 决策摘要

**采用元素级 LWW，不迁移 CRDT；先拆热路径，再建立可靠投递，最后用指标选择深度性能优化。**

当前协作问题的主因是每次 `onSceneChanged` 同时执行本地全量保存、封面生成、实时网络发送和远端全量快照保存。高频书写使这四项竞争 CPU、SQLite、网络和加密资源；快照并发还会触发 409 后的全量加载、合并和重试。另一方面，Socket.IO 的默认投递是“至多一次”，现有实现没有 ACK、持久 outbox 或 resume，因此短断线不能可靠确认编辑是否已送达。

本方案按以下顺序落地：

1. **Phase 0：热路径止血**——50 ms 批处理、分离本地/实时/快照任务、串行快照、接收合并、presence 限频；
2. **Phase 1：可靠恢复**——加密 outbox、`opId`、ACK、幂等去重、resume 与清晰的 `synced` 状态；
3. **Phase 2：服务端和运行环境加固**——轻量 join、网络/生命周期恢复、限流与可观测性；
4. **Phase 3：基于 profile 的深度优化**——Dirty Set、直接 Map 编解码、压缩、分区与大笔迹策略；
5. **远期**——只有并发语义或离线编辑确实超出 LWW 能力时，才单独 ADR 评估 Yjs/Automerge。

## 2. 现状与问题证据

```text
MarkdrawController.applyResult()
  └─ onSceneChanged
      └─ WhiteboardPage._saveMarkdrawScene()
          ├─ serializeScene（全场景）
          ├─ SQLite saveScene + 生成封面 + touchNote
          └─ CollaborationRepository.broadcastScene()
              ├─ 变更元素加密并 Socket.IO emit
              └─ unawaited(_saveSceneSnapshot(全场景 HTTP PUT))
```

| 优先级 | 已证实的问题 | 代码证据 | 后果 |
| --- | --- | --- | --- |
| P0 | 高频变更直接触发 `_saveMarkdrawScene()`，无合并 | `whiteboard_page.dart:1373` | 一笔书写或一次拖动重复启动整条重任务链路 |
| P0 | 每次本地变更都全场景序列化、写库、生成封面 | `_saveMarkdrawScene()` | UI 与持久化、缩略图争用；大场景越写越慢 |
| P0 | 每次广播都异步保存全量远端快照 | `collaboration_repository.dart:broadcastScene()` | 快照请求堆积、AES/JSON/HTTP 竞争 |
| P0 | 409 后执行全量加载、reconcile、重试 | `_saveSceneResolvingConflict()` | 高频编辑时形成放大的全量读写风暴 |
| P1 | 每 20 秒强制全量场景广播 | `_startFullSceneSync()` | 周期性大包，且不等于可靠投递 |
| P1 | 入站解密和远端 UI 应用各自单队列 | `_messageDecodeQueue`、`_remoteSceneQueue` | 高峰时消费历史消息，画面落后 |
| P1 | 重连只 rejoin，不含已确认游标或待发队列 | `SocketIoRealtimeTransport.onReconnect` | 断线期间的变更无法可靠确认或补齐 |
| P2 | `joinRoom()` 为判断房间存在而加载场景 | `hub.go:roomExists()` | 重连路径不必要地读取加密大对象 |
| P2 | 服务端没有 ACK、幂等去重、业务级限流 | `hub.go:forward()` | 无法判断可靠消息已接受；异常流量难隔离 |

### 2.1 已有能力，必须复用

- `SceneReconciler`：基于 Excalidraw `version/versionNonce` 的元素级 LWW；
- `EncryptedSceneStore`：带乐观锁元数据的加密快照；
- `RealtimeTransport`：可扩展可靠发送、ACK 和恢复，而不污染编辑器；
- `ExcalidrawBinaryCodec`：可复用压缩能力，但先验证是否值得用于实时帧；
- `volatile` 消息：已区分 cursor/idle/visible bounds 与文档元素；
- SQLite 与 secure storage：可承载 outbox、恢复游标和本地元数据。

### 2.2 已排除与待测项

- **已排除“WebSocket 下 Uint8List 必然转 JSON 数字数组、膨胀 6 倍”**：项目锁定的 `socket_io_client 3.1.6` 在 WebSocket transport 中对二进制数据直接调用 `sendBytes(...)`。因此不实施“改成原生二进制传输”的独立优化。仍应在首轮真机指标中记录实际协商 transport；polling 回退下的编码与失败率另行观察。
- **仍待测“明文压缩收益”**：压缩必须发生在 AES-GCM 前，方向正确；但它改变消息编解码协议，并可能对已批处理的小帧得不偿失。因此不并入首个无协议变更的 PR；Phase 0 先采集原始字节数和批次大小，再做压缩 A/B。
- **仍待测“并行解密收益”**：Dart 单 isolate 下不能假定并行就更快。优先做接收端合并窗口，只有 profile 证明解密而非 UI 应用是瓶颈时再评估 isolate。

## 3. 方案边界与非目标

### 必须保持

- 场景、操作、roomKey 不以明文传给服务端；AES-GCM 端到端加密不变。
- `id/version/versionNonce/index/isDeleted` 的 Excalidraw 语义不变。
- 远端应用不再次触发本地协作广播；删除墓碑不被错误合并或丢弃。
- 文档元素不走 volatile；presence 不进入快照与 outbox。
- 平台网络差异收敛在 transport/适配层，不在共享业务代码散布 `Platform.is*`。

### 本轮不做

- 不迁移 Yjs、Automerge、OT；现有根因是热路径和可靠投递，而非 LWW 算法本身。
- 不在未 profile 前重写编辑器编解码或引入 MessagePack。
- 不强制 websocket-only；先记录 polling 回退率和失败率后再做选择。
- 不假定 Go Socket.IO 库存在缓冲区长度 API；背压实现先以实际库 API 为准。

## 4. 目标架构

```text
本地编辑
  ├─ 立即更新画布（不等待网络）
  ├─ ChangeAccumulator：按 elementId 合并最高版本
  ├─ LocalDraftScheduler：500 ms debounce 保存本地场景
  ├─ RealtimeScheduler：50 ms 批量发送变更元素
  ├─ Encrypted Outbox：P1 起，ACK 前持久化
  └─ SnapshotScheduler：空闲 2 s / 最长 30 s，单飞快照

服务端
  ├─ 校验房间和帧大小，转发密文
  ├─ P1：按外层 opId 去重、写短期密文操作日志并 ACK
  └─ P2：RoomExists 轻量检查、限流和指标

接收端
  ├─ 解密、解析
  ├─ 16–33 ms 合并窗口，按 elementId 取最新
  ├─ SceneReconciler 合并
  └─ 每帧最多一次 applyRemoteScene

恢复
  reconnect → rejoin 确认 → resume(lastSeenServerSequence, snapshotVersion)
    → 补短期密文操作日志，或单次拉快照/reconcile → 重放 outbox → synced
```

### 4.1 应用层可靠帧与恢复备用协议

`opId` 不能只放在密文内：服务端若看不到它，就无法去重、确认或关联恢复。若 Socket.IO CSR POC 不可用或不能满足本项目语义，采用“**外层不透明路由元数据 + 内层加密场景数据**”的备用路线。

```json
{
  "protocolVersion": 2,
  "roomId": "...",
  "opId": "clientInstanceId:sequence",
  "kind": "scene-update",
  "ciphertext": "...",
  "iv": "..."
}
```

- `clientInstanceId` 是首次安装时生成并持久化的随机 UUID，不使用易变的 `socketId`，不承载用户身份；`sequence` 与 outbox 写入在同一事务中递增，避免重启复用。
- 外层 `opId` 只泄露伪随机实例标识和单调计数，不泄露画布内容；`elements`、base version 和任何可读场景信息仍只在密文内。
- 服务端对每个已接受 frame 分配单调 `serverSequence`，短期保存**完整密文 envelope**，并回 ACK `{opId, serverSequence}`。默认保留 2 分钟、每房间最多 4096 帧或 32 MiB，以先达到的上限为准；日志只在内存中保存，服务端重启后视为不可用。
- resume 的日志包含房间内**所有成员**在断线期间的可靠帧。客户端按 `serverSequence` 逐帧解密，经 `SceneReconciler` 合并后应用，绝不直接覆盖本地场景。
- 操作日志过期、达到上限、服务端重启或 resume 有空洞时，客户端回退为“拉一次快照 → reconcile → 重放 outbox”。因此短期操作日志只优化恢复，不成为新的持久化真相来源。
- outbox 保存**已加密的完整 envelope**，重放时保持同一个 `opId`、密文和 nonce；当前 roomKey 在房间生命周期内不轮换。若未来引入 roomKey 轮换，必须增加 outbox 重加密迁移，不能静默丢弃。

## 5. 分阶段方案

### Phase 0：热路径止血（首个 PR）

**目标**：无需改变协议即可显著降低同步负载和快照冲突。

1. 新增 `ChangeAccumulator`：50 ms 内按 `elementId` 覆盖合并，只发送最新版本。`initial`、用户显式保存和恢复强制同步可 bypass。
2. 将 `_saveMarkdrawScene()` 拆成三个调度器：
   - 本地草稿：500 ms debounce，离开、进入后台、显式保存时 flush；
   - 实时协作：50 ms batch；
   - 封面：仅显式保存或用户空闲后生成。
3. 新增 `SnapshotScheduler`：最后一次变更 2 秒后、最长 30 秒一次；同一房间 single-flight。若保存期间继续变化，完成后只补一次最新快照。409 仅做一次 load/reconcile/retry。
4. 接收端增加 16–33 ms 合并窗口；同一元素只保留最高 `version/versionNonce` 的更新，再调用一次远端场景应用。
5. 对 pointer/idle/visible bounds 限频至 20–30 fps，保留 trailing 更新；保持 volatile。
6. 20 秒全量同步改为可开关的临时兜底并加指标；Phase 1 后以可靠恢复替代，禁止在已有快照请求飞行时额外触发。
7. 加入最小指标：batch 元素数、密文字节数、发送间隔、远端应用延迟、快照耗时和 409 数。
8. 先修复协作正确性前提：为 `onSceneChanged` 增加变更来源（普通编辑 / undo / redo / 远端应用 / 恢复），`undo()` / `redo()` 恢复历史快照后，所有与当前场景不同的元素必须以新 `version` 与 `versionNonce` 表达变更，并强制 flush，不能等待 accumulator；否则旧版本会被 `_changedElements()` 门控而永远不发送。
9. 修复远端 reconcile 后的版本表：`reconcileRemoteScene()` 必须以实际 `reconciled` / `nextScene.elements` 更新 `_rememberBroadcasted()`，不能只记录 `remoteElements`；并取消快照恢复后的 `syncAll: true` 回声广播，改为仅发送 accumulator / outbox 判定仍待发送的增量。

**Accumulator 约束**：对同一 ID 按现有 `SceneReconciler._shouldKeepLocal()` 的 `version + versionNonce` 顺序选择最新元素，不能只比较时间或版本；flush 时从最新场景取值，不保留过期对象引用。删除墓碑正常参与该比较，且在 `deletedElementTimeout` 内不得丢弃。`protectedElementIds` 仅是入站合并保护，不能让选中元素绕过全部批处理；正在提交的文本/Frame 编辑必须以提交后的最新元素进入 accumulator。

**验收**：两端连续书写 60 秒，快照 PUT 不超过 1 次/秒、实时批次不超过 20 次/秒；场景增大不出现持续性延迟抬升；无元素丢失、回声广播或删除复活。

### Phase 1：可靠投递和断线恢复（第二个 PR）

**目标**：网络切换、后台恢复和短断线后，用户不需手动重新加入且不丢本地变更。

1. 新建 SQLite 加密 outbox。可靠变更先写入已加密 envelope，收到服务端 ACK 后删除；重启后以原 `opId` 重放。
2. 每个可靠 payload 的加密内层包含：

```json
{
  "baseSnapshotVersion": 42,
  "elements": ["本批变更元素"]
}
```

3. ACK 直接使用 Socket.IO 原生机制：Dart `emitWithAck` / `emitWithAckAsync` 与 Go `Ack` / `EmitWithAck`，不自建 ack 事件。另完成 Go v2.5.0 最小 POC，验证该服务端与 Dart 客户端的 CSR 互操作、二进制帧、重连后的房间恢复和非 volatile 漏包重放。Dart 3.1.6 本地源码已确认会保存/发送 `pid` 与 `offset`；Go 侧行为仍以 POC 为准。
4. POC 通过且恢复窗口满足目标时，使用库原生 CSR 处理服务端到客户端补包；outbox 仍负责客户端到服务端可靠投递。POC 失败或语义不满足时，启用 §4.1 的应用层 `opId + serverSequence + 短期密文日志` 备用方案。两套恢复机制不可同时作为权威来源。
5. 在 transport 适配层补齐重连触发器：网络恢复、应用 `resumed` 时主动检查连接并触发 rejoin/resume；`paused` 不得清空 outbox。Android 与鸿蒙各自走适配层，公共状态机保持共享。
6. 重连必须等待 `room-user-change` 或等价确认后才能发送。状态细分为 `reconnecting`、`rejoining`、`catchingUp`、`replayingOutbox`、`synced`、`failed`；socket connected 不等于 synced。
7. 操作日志不可用或 resume 失败时：加载一次远端快照、执行 `SceneReconciler`、重放 outbox；禁止以全量本地场景直接覆盖远端。
8. outbox 绝不静默淘汰未 ACK 数据：正常状态按 elementId 压缩未确认更新、保留删除墓碑；达到硬上限时停止继续入队并向用户提示“协作缓存已满”，直到恢复同步或用户显式导出本地副本。后续可增加加密全场景 checkpoint 压缩，但不能以丢操作换空间。
9. presence 单独以 TTL 表示在线状态；短断线显示“恢复中”，不立即当作永久离开。

**验收**：断网 10 秒、Wi‑Fi/蜂窝切换、前后台切换后，双方元素内容和版本一致；outbox 清空；无重复元素；用户无需手工重进房间。

### Phase 2：服务端与运行环境加固（第三个 PR）

1. 增加 `SceneStore.RoomExists(roomId)`，以 `SELECT 1` / 元数据查询替代 `SceneStore.Load()` 的大对象读取；活动房间缓存 `exists/ended`，结束后失效。
2. 先查实际 Go Socket.IO 库能力后实现慢客户端保护：volatile 超限可丢弃；可靠消息触发降速/错误信号；必要时断开持续无法消费的客户端。
3. 加 per-socket 令牌桶：可靠变更以 Phase 0 的 20 fps 作为正常上限，presence 30 fps；超限处理不能丢可靠 outbox 数据。
4. 建立脱敏指标：connect/rejoin/resume 耗时、ACK RTT、outbox 长度、去重命中、发送字节、快照 409、丢弃的 volatile 数。按 Android、鸿蒙、Web 分维度观察。
5. 评估是否支持 Socket.IO Connection State Recovery；若不支持，应用层 `opId + 短期密文日志 + resume` 仍是完整方案。

**验收**：异常会话可定位到连接、rejoin、补操作、快照、ACK 或 UI 应用层；加入房间不再读取完整场景；异常客户端不能拖慢整个房间。

### Phase 3：基于数据的深度优化

| 候选项 | 启动门槛 | 实施原则 |
| --- | --- | --- |
| Dirty Set | profile 显示多次 O(n) 扫描进入热点 | 由编辑器产出变更元素；删除/远端合并必须同步更新 dirty 状态 |
| 直接 Map 编解码 | JSON encode/decode 占显著 CPU | `MarkdrawController` 与 `ExcalidrawScene` 直传 Map，保持现有 codec 往返兼容 |
| 广播版本表清理 | 长会话、创建/删除大量元素后 map 持续增长 | 仅在删除墓碑过期并从 syncable scene 清除后，清理对应 `_broadcastedElementVersions`；不使用会导致错误重发的通用 LRU |
| 实时压缩 | 指标证明明文 JSON 字节数是主要瓶颈 | **压缩发生在 AES-GCM 前**；以 feature version 保持兼容；比较 CPU 与字节收益 |
| WebSocket permessage-deflate | Go v2.5.0 POC 证实配置与 Dart 互操作 | 零应用协议变更的低成本候选；压的是密文 frame，预期压缩比低于明文 zlib，仍以 CPU/字节实测决定 |
| 二进制 payload | 当前 WebSocket transport 已确认 `sendBytes`；仅 polling 异常时复核 | 不做“二进制改造”；记录实际协商 transport 与失败率 |
| Socket.IO ACK / CSR / 传输压缩 | ACK 的 Dart API 已确认；CSR 与 permessage-deflate 以 Go/Dart POC 证实互操作 | 若 CSR 可用，优先替换自建服务端补包；传输压缩仍需用真实 CPU/字节数据评估 |
| 分页/区域化广播 | 多页笔记的无关元素 dominate payload | 只标记变更元素所属 page；不得按页裁掉跨页元素或全局删除墓碑 |
| 实时笔迹预览 | 产品明确要求远端看到书写过程 | 当前 freedraw 仅抬笔提交；新增独立 volatile overlay 点流，不能混入 scene 同步优化 |
| 多实例/Redis | 单实例容量达到指标上限 | 同时设计跨实例 room 状态、可靠事件和 presence 语义 |

## 6. 技术选择说明

| 选择 | 结论 | 理由 |
| --- | --- | --- |
| 元素级 LWW | 保持 | 现有 `SceneReconciler` 已适配 Excalidraw；本轮问题不是并发语义不足 |
| 50 ms 批处理 | 先采用并实测 | 能立即消除重复工作，参数后续依指标调整 |
| SnapshotScheduler | 必须采用 | 快照应承担恢复/持久化，而非每帧实时同步 |
| ACK + outbox | 必须采用 | Socket.IO 默认不提供断线可靠投递。[
官方 delivery guarantees](https://socket.io/docs/v4/delivery-guarantees/) |
| 应用层 resume | 必须采用 | 即使启用 Socket.IO recovery，也仍需同步兜底。[
官方 connection recovery](https://socket.io/docs/v4/connection-state-recovery/) |
| presence 与文档分离 | 保持并完善 | 与成熟 awareness 模型一致。[
Yjs awareness](https://docs.yjs.dev/api/about-awareness) |
| zlib / 二进制 | 条件采用 | 有潜在收益，但当前传输实际编码和 CPU 比例必须先测 |
| websocket-only | 条件采用 | polling 有成本也有兼容性价值，基于失败率决定 |
| Yjs/Automerge | 远期评估 | Flutter/Go、E2E、Excalidraw 迁移成本高；仅在需求超出 LWW 时启动 |

## 7. 测试与验收矩阵

| 层级 | 场景 | 必须证明 |
| --- | --- | --- |
| 单元 | accumulator 覆盖、版本倒退、删除墓碑 | 仅最新有效元素被发送，删除不复活 |
| 单元 | outbox 写入、ACK、重启、重放、重复 ACK | 可靠消息幂等，ACK 后删除，未 ACK 可恢复 |
| 集成 | 两人同改不同元素/同一元素 | `SceneReconciler` 结果一致 |
| 集成 | 重复帧、乱序帧、恢复后重放 | 无重复元素，不覆盖较新版本 |
| 服务端 | `opId` 去重、ACK、短期密文日志 resume、RoomExists | 不重复转发，日志失效时安全回退快照 |
| 网络 | 10% 丢包、300 ms RTT、10 秒断网、网络切换 | 自动恢复，outbox 最终清空，场景一致 |
| 性能 | 2/5/10 人、1k/5k 元素、连续书写/拖动 | 采集 P50/P95 发送、ACK、UI 应用、快照、内存 |
| 跨端 | Android、鸿蒙、Web | 加入、书写、图片、删除、恢复行为一致 |

首轮 SLO：

- 本地改动到对端可见 P95 < 250 ms（良好网络、非图片）；
- 短断线恢复到 `synced` P95 < 5 s；
- 已 ACK 的场景操作不得丢失；
- 正常编辑中快照保存不阻塞实时渲染；
- 所有性能结论必须带场景规模、设备、网络条件和 P50/P95 数据。

## 8. 评审问题

以下问题已在本轮评审后作出设计决议：

| 问题 | 决议 |
| --- | --- |
| `opId` 在哪里 | 放入外层 envelope；场景内容继续在密文内。备用协议中服务端按 `opId` ACK/去重，按 `serverSequence` 补短期日志。 |
| ACK 表示什么 | 仅表示“服务端已接受并写入短期操作日志”，不表示对端已渲染；服务端零知识模型下后者不可验证。 |
| outbox 保存什么 | 保存已加密完整 envelope，确保重放一致；当前 roomKey 不轮换。 |
| outbox 满了怎么办 | 绝不静默丢未 ACK 操作；先按元素合并，硬上限时停止继续入队并提示用户，后续再设计 checkpoint 压缩。 |
| 短期日志如何保存 | 服务端内存保存 2 分钟，单房间上限 4096 帧或 32 MiB；达到任一上限、重启或有空洞时一律回退快照 reconcile。 |
| 谁触发重连 | Phase 1 的 transport 适配层负责网络恢复和 `resumed` 触发，不能延后到 Phase 2。 |
| 二进制编码问题 | WebSocket transport 已从锁定依赖源码确认 `sendBytes`；不作为单独优化项，真机仅确认协商 transport。 |
| zlib 排序 | 保持在 metrics gate 后；P0 首个 PR 不改变协议，先以真实批次字节数决定。 |
| undo/redo 与版本 | Phase 0 必须为历史快照差异生成新 `version/versionNonce`，否则远端永远收不到撤销/重做。 |
| 远端版本表与回声 | Phase 0 必须以 reconciled 结果更新广播版本表，且快照恢复不再 `syncAll` 全量回声。 |
| freedraw 与合并窗口 | 当前 freedraw 仅在 pointer-up 提交元素，进行中笔迹是本地 overlay、不广播；16–33 ms scene 合并窗口对它无影响。实时笔迹流属于新增 volatile 功能。 |
| checkpoint 压缩 | 可作为超大 outbox 的后续方案：以 `getSyncableElements` 保留 1 天内墓碑、reconcile 而非盲覆盖、只引用已上传图片。 |
| ACK / CSR 能力 | ACK 直接用原生 API；CSR 的 Dart 侧 PID/offset 已确认存在，Go/Dart 互操作仍以 v2.5.0 POC 决定。原生 CSR 通过则替代自建服务端补包，自建方案只作回退。 |

请评审者继续重点验证以下未决问题，而非仅检查文档措辞：

1. Phase 0 的 accumulator 是否能正确处理删除墓碑、撤销/重做和远端合并后的版本边界？
2. Connection State Recovery POC 是否能在当前 Dart/Go 组合中恢复房间成员关系、身份和漏掉的非 volatile 帧；若不能，备用日志方案的 TTL/上限应如何实现？
3. 当前 scene 合并窗口仅处理 `sceneInit/sceneUpdate`，presence 已直接分流；freedraw 只在 pointer-up 提交。是否另行建设实时笔迹预览 volatile 通道是产品新增功能，不属于本轮优化。
4. 加密全场景 checkpoint 是否能安全替代超大 outbox：已确定必须保留 1 天内墓碑、reconcile 而非盲覆盖，且只引用已上传的图片文件；仍需设计 checkpoint 的 ACK 与原子切换测试。
5. 当前 Go Socket.IO 库在 CSR、背压、`permessage-deflate` 上的实际 Go/Dart POC 结果是什么；ACK 直接使用已确认的原生 API。
6. 鸿蒙生命周期可否直接复用 `WidgetsBindingObserver`；网络状态是否以 `NetConnection` Platform Channel 注入 transport，并避免污染业务层？

## 9. 参考与来源取舍

- 三份调研共同确认：热路径耦合、无批处理、20 秒全量同步、无可靠投递、LWW 可继续使用。
- 采用 zcode 的：`RoomExists` 轻量检查、直接 Map 编解码、分页区域化广播和大笔迹优化，但均按 profile 后置。
- 采用 claude 的：Dirty Set、网络/生命周期恢复、系统化压测视角，但不采纳未经测量的固定收益数字和强制 WebSocket 结论。
- 采用原 codex 的：ACK/outbox/resume、快照单飞、证据分级、SLO 与完整恢复验收；作为整体实施主线。
