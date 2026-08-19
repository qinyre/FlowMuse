# P3：协作 Live Ink V2 执行计划

> 日期：2026-08-20  
> 状态：批准执行（三方终审无 findings）  
> 预计：8～11 人日  
> 启动：P0 completed；叶子任务另见依赖

## 1. 目标与零知识边界

把自由笔临时协作从“重复发送完整增长元素并进入正式 Scene”改成专用、AES-GCM 加密、volatile、增量且有界的 live-ink 通道。最终 `SCENE_UPDATE`、Presence、房间密码/AES-GCM 和 Excalidraw 格式保持不变。

服务端只看事件名、密文/IV 外层长度、房间成员/socket 和速率；不解密、不读取 `protocolVersion/strokeId/opId`、不对密文正文去重。Live 丢包允许，最终可靠性仍完全由现有 `SCENE_UPDATE` 语义承担。

## 2. 有效开关与依赖

```text
effectiveLiveInk = FLOWMUSE_LAYERED_WET_INK
                && FLOWMUSE_LIVE_INK_V2
                && serverLiveInkProtocolVersion >= 2
```

- `FLOWMUSE_LIVE_INK_V2` 默认 false，独立文件只读一次；layered=false 时不得收发/绘制 V2，并完整回退现有 V1 路径。
- `ready` 超时或服务器不支持只降级到旧路径，不阻塞 join；迟到 ready 在本次连接中忽略，重连后重新协商。
- 每笔在 PointerDown 冻结 `strokeLiveMode`；禁止 v1→v2 半笔切换。

## 3. Task P3-0A：服务端专用事件和 ready

**负责人/复核：** Enchograph / Hongyu Chen；**估时：** 0.75d；**前置：** P0-4。

**执行状态：** 已完成；`INK_CHUNK` 复用现有大写消息包络与 AES-GCM，严格验证 v2、UTF-8 ID、绝对索引/坐标、1～64 点、压力及固定样式，并支持按绝对索引去重乱序重叠点。

**执行状态：** 已完成；新增独立 ready/live 事件，服务端校验房间归属、外层类型、12-byte IV 与 64KiB ciphertext，并以服务端 socketId 构造 volatile 下行帧。

### 文件

- Modify: `FlowMuse-Server/internal/collab/events.go`
- Modify: `FlowMuse-Server/internal/collab/hub.go`
- Modify/Create: `FlowMuse-Server/internal/collab/hub_test.go`

### 独立事件

```text
server-live-ink  client → server，volatile
client-live-ink  server → room peers，volatile
live-ink-ready   server → joined socket，普通独立事件
```

客户端必须在发 `join-room` 前监听。join 成功后服务端只向当前 socket 发送 `{ "roomId": roomId, "liveInkProtocolVersion": 2 }`；它是独立事件，不改变现有 `room-user-change` 数组载荷，ready 失败/迟到不改变 join 结果。

服务端对入站外层做成员、room/socket 归属、字段类型、IV 恰好 12 bytes 和解码后 ciphertext ≤64KiB 校验，再使用 Socket.IO volatile operator 转发给同房间其他 socket；`senderSocketId` 必须由服务端根据连接写入下行外层，忽略客户端同名字段。Presence 常量/行为不变。

测试：非成员、跨房间、伪造 sender、超限、leave/disconnect 清理、下行确为 volatile、ready 独立于 join。

## 4. Task P3-0B：客户端开关、transport 分流和握手

**负责人/复核：** Enchograph / qinyre；**估时：** 1d；**前置：** P0-4。

**执行状态：** 已完成；增加 effective flag、独立 live stream/send API 与 1 秒 ready 门禁；连接、重连、换房和断开均清零版本，Socket.IO 直接使用 `volatile.emit` 且不可写时不缓冲。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/config/live_ink_flags.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/config/live_ink_flags_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/services/realtime_transport.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/models/received_live_ink_frame.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/realtime_transport_live_ink_test.dart`
- Move/Modify: `FlowMuse-App/test/features/whiteboard/collaboration/collaboration_repository_sync_test.dart` → `FlowMuse-App/test/features/whiteboard/collaboration/repositories/collaboration_repository_sync_test.dart`

### 最小 transport 增量

- `Future<void> sendLiveInk(EncryptedPayload payload)`；transport 自己附加当前 roomId，实现必须直接调用 `socket.volatile.emit('server-live-ink', ...)`，不得转调普通 `socket.emit`/现有可靠 send，不新建重复 envelope 类型。
- `Stream<ReceivedLiveInkFrame> get liveInkFrames` 和 `int get serverLiveInkProtocolVersion`；transport 内部记录 connection generation+roomId，仅当前代 ready 可更新版本。不得把 live 帧塞入现有可靠 `messages` 解密/合并队列。
- disconnected/non-writable 时立即丢弃并计 `transport_not_writable`，Socket.IO send buffer 中不得出现该帧。
- connect/reconnect/disconnect/换房先把版本重置为 0；1 秒内只接受与当前连接、当前 roomId 匹配且版本 ≥2 的 ready。超时、缺字段、房间不匹配或迟到事件使本次连接保持 legacy；不阻塞 joined。
- Memory transport 只补同样的独立流，供确定性测试，不模拟 Socket.IO 缓冲。

测试 flag 四种组合、监听先于 join、room mismatch、ready 迟到/重复/断线、ready mid-stroke 不切模式、真正 volatile API、断线不缓冲、Presence/可靠 messages 行为不变。

## 5. Task P3-1：加密 INK_CHUNK 模型

**负责人/复核：** Enchograph / Hongyu Chen；**估时：** 0.75d；**前置：** P0-4。

### 文件

- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/models/collaboration_message.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/models/live_ink_chunk.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/models/live_ink_chunk_test.dart`

### 密文内 payload v2

```json
{
  "type": "INK_CHUNK",
  "payload": {
    "protocolVersion": 2,
    "strokeId": "same-as-final-element-id",
    "startIndex": 84,
    "points": [{"x": 1.2, "y": 2.4, "pressure": 0.6}],
    "style": {"brushType":"fountainPen","strokeColor":"#000000","strokeWidth":2.0,"opacity":100}
  }
}
```

- `strokeId` 在 PointerDown 预留并等于最终 `FreedrawElement.id`；每笔新建唯一 ID，因此 wire 不需要额外 epoch。
- `x/y` 是绝对 Scene 坐标且 `abs <=1e7`；pressure 是 null 或 `[0,1]`；`startIndex` 是 points[0] 在完整 accepted 序列中的索引。
- 每包 1～64 点并携带最小固定 style；收到任意包即可渲染。重复点按 `startIndex + offset` 去重；有缺口时开启新子路径，禁止跨缺口画长线，后到点可填补。
- 每包覆盖最近三个实际发送周期，三个周期 >64 点时只保留最新 64 点并显式形成缺口；每个 accepted index 最多出现在 3 个实际发出的包。
- 第一版不增加 sequence、strokeEpoch、时间字段、style 字典、量化/delta 或二进制编码；绝对索引已承担去重、乱序和缺口判断。
- 先按现有大写消息包络序列化，再复用 `CollaborationCrypto` AES-GCM；外层保持现有 `EncryptedPayload`，服务端不读取正文。

单测覆盖 round-trip、NaN/Infinity/坐标溢出、任意首包缺样式、非法 style、重复/乱序/缺口、绝对索引恢复、64 点/64KiB 边界和密文篡改。

## 6. Task P3-2：发送端 delta、冻结模式和背压

**负责人/复核：** qinyre / Enchograph；**估时：** 1.25d；**前置：** P1-1、P3-0B、P3-1。

**执行状态：** 已完成；PointerDown 按笔冻结 V1/V2，20Hz 聚合发送最近三次实际周期的最多 64 点窗口，并以单笔 1 in-flight + 1 覆盖式 pending 控制背压；PointerUp 在清点前交出最后 accepted 点且不等待可靠 final，Cancel/切工具/dispose/离房均清理 sender。真机时延仍按既定条件门禁延期。

### 文件

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/live_ink_sender.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/live_ink_sender_test.dart`

`FreedrawTool/ActiveFreedrawView` 继续只拥有 points、唯一 strokeId 和 strokeLiveMode，并提供只读 point slice。`LiveInkSender` 独占 `lastSentIndex`、inFlight、pending 和三周期窗口边界，禁止把网络游标放回 Tool/Controller。

### 确定性发送规则

- PointerDown 冻结 `strokeLiveMode`；true 时创建 sender state，false 时整笔旧路径。
- 默认 20～30Hz，一帧内 accepted 点聚合；每次**实际 emit** 都携带最近三个实际发送周期覆盖的自包含滑窗，并截取最新最多 64 个绝对 Scene 点。`startIndex` 指明首点 accepted index，每包带最小 style；不为 raw pointer 创建包。
- 同一 accepted index 最多出现在 3 次实际 emit；发送器记录最近三次已 emit 周期边界。累计 bytes 必须随点数线性增长且放大系数有上界，不能随整笔长度二次增长。
- 同一 stroke 最多 1 个 in-flight 加 1 个 pending；新候选覆盖 pending，窗口按“最近三次实际 emit + 最新 accepted 点”重建，保证最新点仍可发送；未实际 emit 的 pending 不算一个周期，不排无界队列。
- send 调用不阻塞输入/paint，不等待 volatile Future；异常只计数。
- PointerUp：在 Tool 清活动点之前生成包含最后 accepted 点的 pending snapshot；发起/覆盖 pending 后，同一同步事件继续提交 final `SCENE_UPDATE`，随后清 sender。final 不等待 live。
- Cancel/工具切换/dispose 清 sender，不发 final；ready mid-stroke 只影响下一笔。

测试含 1/7/8/64/65 点、三周期覆盖与最多 3 次重复、pending 覆盖、慢/抛异常 transport、PointerUp 最后点、Cancel、每笔唯一 strokeId、ready mid-stroke、final hash 与 P1 一致。

## 7. Task P3-3A：独立接收调度和公平队列

**负责人/复核：** Enchograph / qinyre；**估时：** 1d；**前置：** P3-0B、P3-1。

**执行状态：** 已完成；live 帧进入独立异步解密/校验 scheduler，同时仅解密 1 帧、每 sender 覆盖保留最新密文、最多 8 个 pending sender，并按 sender 轮转且每 2ms 主动 yield；坏密文和 sender 上限只聚合计数，不进入可靠 Scene 队列。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/live_ink_receive_scheduler_test.dart`

- live stream 使用独立异步 StreamController、独立 decrypt/validate queue；不得串入可靠 Scene message 的队列或锁。
- 同时最多 1 个 live decrypt；pending 映射最多 8 个 sender、每 sender 只留最新 ciphertext。完成一个后按 sender round-robin 取下一个，单次调度耗时到 2ms 立即 yield；单个高频 sender 不得覆盖其他 sender 的 latest。
- 本地 Pointer/paint 不等待 receive scheduler；可靠 Scene 流也不等待 live queue。
- P3-3A 只输出已解密、已校验的 chunk 给下游 consumer；不引用或创建 P3-3B 的 store/finalized registry。
- 测 1/5/9 sender 洪泛、坏密文、慢 decrypt、可靠 Scene 同时到达、独立队列和公平性。

## 8. Task P3-3B：RemoteWetInkStore 与有界 Painter

**负责人/复核：** qinyre / Tiax；**估时：** 1.5d；**前置：** P1-2、P3-1、P3-3A。

**执行状态：** 已完成；RemoteWetInkStore 固定执行 8 sender、64 stroke、16384 点/笔、65536 点/房间、5s TTL 和 10s completed cache，并以房间生命周期 finalized set 阻止 final 后复活；远端画层使用 1 个 consolidated picture、最多 8 个增量 picture 和 64 点 tail，final 到达先清湿墨再进入 Scene。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/remote_wet_ink_store.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/remote_wet_ink_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/remote_wet_ink_store_test.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/remote_wet_ink_painter_test.dart`

### 客户端 admission/overflow 语义

| 边界 | 固定值 | 达到边界后的行为/稳定原因码 |
| --- | ---: | --- |
| active sender/room | 8 | 已登记 sender 保留槽；第 9 个 sender 全帧丢弃 `sender_limit`，不得驱逐；leave/5s 无活动才释放 |
| live stroke/room | 64 | 现有 stroke 可更新；新 stroke 整包拒绝 `stroke_limit`，不得 LRU 驱逐 |
| point/stroke | 16384 | 会越界的整包拒绝 `stroke_point_limit`，不部分接收 |
| point/room | 65536 | 会越界的整包拒绝 `room_point_limit`；重复包不增加计数 |
| inactivity TTL | 3～5s（常量固定后测试） | 到期淡出/清 stroke；final Scene 立即清并进入 10s completed cache + room-lifetime finalized set |

sender churn 不能驱逐活跃 sender；每次清理必须同时更新 room 计数。测试精确覆盖 8→9、64→65、16384→16385、65536→65537、leave/TTL 后重新准入和重复包计数。

P3-3B 创建并独占房间生命周期的 `finalizedStrokeIds`：初始 Scene 中 Freedraw ID 批量加入，final apply 时 O(1) 加入并先写 10 秒 completed cache、再清 wet stroke；离房清空。处理 live 前只查 set/cache，禁止逐包线性 `Scene.getElementById()`；final 先到及 100ms/11s 迟到包都不得复活。对应 terminal-before-preview 测试归 `remote_wet_ink_store_test.dart`。

### 渲染成本硬边界

- 每个 remote stroke 最多 1 个 consolidated prefix、8 个 immutable incremental segment 和 1 个 64 点 tail 层，总层数 ≤10；room 总估算渲染缓存 ≤16MiB。第 8 个 segment 冻结时按 P1-3 的冻结边界规则合并最旧 4 个，普通包不得重录全部前缀。
- 若 P1-3 已 completed，可复用其 `RetainedFreedrawPrefix`；若 P1-3 为 not_triggered/rejected，P3-3B 在 `remote_wet_ink_painter.dart` 内实现上述最小 remote-only bounded prefix，不反向强制启动 P1-3，也不抽象通用框架。
- 合并追不上或缓存到顶时，拒绝该 stroke 的新增 wet 包并计 `render_cache_limit`；final Scene 仍正常到达和接管。禁止以遍历全部历史点或无界 layer/tail 兜底。
- style 缺失/非法、startIndex 溢出或非有限坐标整包丢弃；重复索引去重，缺口拆子路径。Painter 只读 store，不写 Scene/history/save/AI。

验收含 64 个 16k 点 stroke 的合成压力输入；逐帧几何遍历量、layer 数和内存始终不越界，final 接管无残影。

## 9. Task P3-4：服务端外层安全边界

**负责人/复核：** Enchograph / Hongyu Chen；**估时：** 1d；**前置：** P3-0A、P3-1。

**执行状态：** 已完成；live 事件先校验当前房间成员，再以标准库令牌桶执行每 socket 60/s、burst 120 和每 room 300/s、burst 600；IV、ciphertext 与不安全 `[]any` 在复制和广播前拒绝，leave/disconnect/end-room 同步清理 bucket，可靠消息与 Presence 不受限流影响。

- 只用 Go 标准库实现有界 token bucket；每 socket 60 包/s、burst 120，每 room 300 包/s、burst 600，IV 恰好 12 bytes，解码后 ciphertext ≤64KiB，常量集中在 `hub.go`。
- 拒绝原因只记录枚举、socket 脱敏前缀和字节数；不记录 ciphertext/nonce/正文。
- 成员校验在限流和广播前；disconnect/leave 删除 bucket；限流只影响 live 事件。
- 客户端解密后校验 protocolVersion、strokeId UTF-8 1～128 bytes、startIndex、数组先验长度、每 chunk ≤64 点、每 stroke ≤16384、每 room ≤64 stroke/65536 点、`abs(x/y)<=1e7`、pressure null 或 `[0,1]`、strokeWidth `(0,100]`、opacity `[0,100]` 和 style 白名单；超限只 drop+聚合原因码。
- 服务端在复制/建表/广播前检查可见长度；无法安全预检的 `[]any` 形式直接拒绝。测试每个边界值/越界值、并发、时钟推进、socket/room bucket 清理、Presence/可靠 broadcast 不受影响；不新增依赖。

## 10. Task P3-5：故障、兼容和负载门禁

**负责人/复核：** Tiax / Enchograph；**估时：** 1.5d；**前置：** P3-0A/0B/1/2/3A/3B/4 全部完成。

**执行状态：** 可在当前环境完成的部分已完成；新增固定 seed 的 drop/duplicate/reorder/delay 与断线故障注入，自动覆盖 flag/legacy、final 先到与迟到防复活、N 矩阵线性约束、5000 finalized ID 和真实 repository→store→painter Profile 入口。当前无真机，且 Windows 缺少 Visual Studio 工具链、Web 不支持 integration test，因此三组 Profile 命令及 5 分钟真机阈值保持为发布前延期门禁，不生成伪造性能结论。

### 文件

- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/fault_injecting_realtime_transport.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/live_ink_fault_test.dart`
- Create: `FlowMuse-App/integration_test/collaboration_live_ink_perf_test.dart`
- Create: `FlowMuse-App/test_driver/collaboration_live_ink_perf_driver.dart`
- Modify/Create: `FlowMuse-Server/internal/collab/hub_test.go`（或同包专用 socket 集成测试；不用 `http_api_test.go`）

Profile target 复用 P0 fixture/report schema，在同一应用进程通过扩展后的 `MemoryRealtimeRoomHub` 建立 1 个真实接收 `EditorCanvas` 和 2/5 个真实 `CollaborationRepository`/sender；显式注入与当前 connection generation、roomId 匹配的 ready 和固定网络模型，使远端 painter 真正产帧。每轮报告 effective flag、ready generation/room、accepted/emit/receive/decrypt/paint/drop 数、队列长度和 raw path。true/true 轮 effective=false 或 emit/paint 任一为 0 则整轮 invalid；false 组合必须断言 effective=false 且 V2 emit=0。

固定 seed 注入 drop 10%/20%、duplicate 10%、reorder window 5、delay 0～120ms、disconnect/reconnect；另设良好网络（RTT=20ms、drop=0、jitter≤5ms）和固定 RTT=100ms/drop=0 场景。覆盖首包丢失、连续丢两包、final 先到、100ms/11s 后迟到、2 人/5 人、5 分钟、长笔、sender churn、ready mid-stroke，以及 N=250/500/1000/2000 accepted 点。通过条件：

- live 可缺段但最终 Scene hash 100% 收敛；
- 无远端湿墨永久残留、无跨笔复活、无未界定队列/内存增长；
- 本地 event-to-paint 达 P0 绝对目标且 P95 相对 P1 不回退 >5%；
- 5 人下可靠 Scene 消息处理 P95 不因 live 洪泛回退 >10%；
- 良好网络远端 accepted-to-remote-paint P95 ≤200ms，RTT=100ms 时 P95 ≤300ms；该指标在同进程确定性 2/5 repository harness 中用同一 Stopwatch 测量，不跨未同步设备时钟。5 个 sender 各 30 包/s 持续 60 秒时每 sender 最大连续饥饿 ≤200ms；
- N 矩阵累计 point entries ≤3N、每 accepted index 实际发送次数 ≤3、`bytes(2N)/bytes(N)` 在 `[1.7,2.3]`；报告斜率、R²、最大重复次数和原始计数；
- final Scene 从可靠流进入到 apply 的等待时间不随 live backlog 增长，P95 相对“live 关闭”不回退 >10%；必须直接记录 reliable queue wait，不用总 RTT 替代；
- 5000 元素、150 live 包/s 时 finalized ID 检查保持摊销 O(1)，不得随 Scene 大小线性增长；
- legacy/flag false 可正常协作。

## 11. 固定开关矩阵和命令

必须验证 `false/false`、`true/false`、`true/true`；`false/true` 的 effective 也必须为 false。

```powershell
Push-Location FlowMuse-App
flutter analyze
flutter test test/features/whiteboard/collaboration
flutter test test/features/whiteboard/editor_core
flutter test
flutter drive --profile --driver=test_driver/collaboration_live_ink_perf_driver.dart --target=integration_test/collaboration_live_ink_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=false --dart-define=FLOWMUSE_LIVE_INK_V2=false
flutter drive --profile --driver=test_driver/collaboration_live_ink_perf_driver.dart --target=integration_test/collaboration_live_ink_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=false
flutter drive --profile --driver=test_driver/collaboration_live_ink_perf_driver.dart --target=integration_test/collaboration_live_ink_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
Pop-Location

Push-Location FlowMuse-Server
go test ./...
go vet ./...
Pop-Location
```

## 12. 发布、回滚与 DoD

当前只有编译期开关且没有生产远程配置/完整遥测，因此发布门禁是：先部署兼容服务端 → 生成 false/false A 包和 true/true B 包 → 固定设备矩阵每包 5 次回放和 30 分钟人工书写 → 固定回放 100 轮（任何归因于新路径的崩溃即停止）。证据来自 runner raw JSON、测试日志和服务端聚合计数；达标后发布默认开启构建，本轮不做百分比在线灰度。异常时重新构建并分发关闭 `FLOWMUSE_LIVE_INK_V2` 的客户端，再按需回滚服务端；无需数据迁移。

P3 completed 需要全部叶子任务/flag 矩阵/故障负载通过；volatile API、独立队列、资源原因码和 final 收敛均有自动证据；AES-GCM/Presence/final Scene 无格式变化，并有非作者安全复核。
