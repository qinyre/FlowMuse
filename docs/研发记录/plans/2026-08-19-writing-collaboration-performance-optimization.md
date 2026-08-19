# FlowMuse 书写与协作性能优化实施方案（修订版）

> 初稿日期：2026-08-19
>
> 修订日期：2026-08-20
>
> 状态：第六轮三路终审通过，无 findings，可按门禁实施
>
> 适用范围：`FlowMuse-App`、`FlowMuse-Server`
>
> 正式平台：HarmonyOS 优先，并保证 Android、iOS、macOS、Windows、Web 不退化

## 0. 修订说明

本次修订基于代码可行性、成熟技术方案和执行门禁三路独立审查，修复初稿中的主要阻断项：

1. 增加驱动真实 Widget、Painter、FrameTiming 的性能回放入口和唯一测量口径；
2. 增加“冻结前缀 + 有界活动尾段”，避免长笔迹在湿墨层继续重复计算完整轮廓；
3. 只分流自由笔迹预览，保留矩形、椭圆、箭头等现有 `previewElement`；
4. 增加独立、有界的 volatile 解密和消费通道，防止临时消息阻塞可靠 Scene 消息；
5. 将 `INK_CHUNK` 改为符合现有 `{type, payload}` 包络的自包含协议；
6. 明确绝对 Scene 坐标、点索引、时间、压力、样式、丢包和迟到包语义；
7. 服务端只校验其能看到的房间、密文大小和速率，语义校验放在客户端解密后；
8. 删除当前仓库无法执行的 10% 在线灰度，改用编译开关和内部 A/B 包；
9. Path 缓存、Scene 索引和 Pen Kit 改为数据触发，不再无条件实施；
10. 将 ACK、outbox、服务端重启不丢数据拆为独立可靠性项目 R1。
11. 二次审查后进一步拆出专用 live-ink Socket.IO 事件，避免破坏现有 Presence；
12. 增加 retained prefix 层、逐发送者公平队列、真实发送背压和确定安全上限。

## 1. 执行结论

当前卡顿来自三条已经由代码证实的热路径：

1. 自由笔迹每次被输入模型接受的 move 都触发 `MarkdrawController.notifyListeners()`，继而让 `MarkdrawEditor` 顶层 `setState()`；
2. 活动自由笔迹预览进入 `StaticCanvasPainter`，使已完成场景在书写过程中重复排序、裁剪、查找和重绘；
3. 协作层约每 50 ms 构造、加密并发送不断变大的完整笔迹，接收端又将临时元素放入正式 Scene reconcile。

本轮只实施三个高收益阶段：

- **P0：可复现测量基线**；
- **P1：本地自由笔迹湿墨分层和有界活动尾段**；
- **P3：独立临时消息通道和增量远端湿墨**。

P2 笔尖预测、已完成 Path 缓存、Scene 索引只在 P0/P1 数据证明需要时进入。可靠交付 R1 单独设计，不阻塞本轮性能优化。

本轮不迁移 CRDT，不重写原生整页画布，不改变最终 `FreedrawElement` 和 Excalidraw 格式，不降低 AES-GCM 端到端加密边界。

## 2. 已证实结论与待测假设

### 2.1 已被代码证实

| 结论 | 代码位置 |
| --- | --- |
| accepted freedraw move 会触发全局通知 | `editor_core/src/ui/markdraw_controller.dart` |
| 顶层监听后执行 `setState()` | `editor_core/src/ui/markdraw_editor.dart` |
| 自由笔迹 preview 被放入静态 Painter | `editor_core/src/ui/editor_canvas.dart`、`buildPreviewElement()` |
| 静态绘制会排序、裁剪并线性查找 | `rendering/static_canvas_painter.dart`、`core/scene/scene.dart` |
| completed freedraw 会重复计算 outline/Path | `rendering/rough/freedraw_renderer.dart` |
| live freedraw 约每 50 ms 构造完整元素 | `markdraw_controller.dart`、`editor/tools/freedraw_tool.dart` |
| 远端 live 元素进入正式 reconcile 和 Scene | `views/whiteboard_page.dart`、`collaboration_repository.dart` |
| non-volatile/volatile 密文最终进入同一客户端消息流和解密队列 | `realtime_transport.dart`、`socket_io_realtime_transport.dart`、`collaboration_repository.dart` |
| 服务端只看见密文和 IV，不持久化协作帧 | `FlowMuse-Server/internal/collab/events.go`、`hub.go` |
| 服务端存在逐帧广播日志 | `FlowMuse-Server/internal/collab/hub.go` |

### 2.2 必须由 P0 验证

- 各热路径分别占 UI、raster 和端到端延迟的比例；
- 60/120 Hz 目标设备的实际帧预算；
- 20～30 Hz 是否是最合适的远端湿墨频率；
- 活动尾段应保留多少点；
- Path 缓存和 Scene 索引是否仍有可见收益；
- `isComplete:false` 的实际视觉落后；
- AES-GCM/JSON 是否需要迁移 isolate；
- HarmonyOS Pen Kit 能否从 Flutter Surface 获得原生事件，以及是否至少改善 5 ms；
- 远端 150/250 ms 挑战目标能否在实际部署区域达成；
- Timer 和服务端日志是不是主要瓶颈。

## 3. 成功标准与唯一测量口径

### 3.1 测量环境

- 性能结论只来自 Profile/Release 真机，Debug 仅用于排错；
- HarmonyOS 至少覆盖一台 60 Hz 中端真机和一台高刷真机，Android 至少一台中端真机；
- 每个场景预热 5 秒、测量 60 秒、独立运行 5 次；
- 报告每轮 P50/P95/P99/最差值，以及 5 轮结果的中位数；
- 稳定性公式：`(max(runP95) - min(runP95)) / median(runP95) <= 10%`；
- 前 5 个 warm-up frame、首次 shader 编译和首次图片解码不计入稳定态，但单独记录冷启动最差帧；
- 原始结果输出 JSON/CSV，再由脚本生成 Markdown，禁止手工抄写指标。

### 3.2 指标定义

| 指标 | 定义 | MVP 门槛 |
| --- | --- | --- |
| event-to-active-preview-paint proxy P95 | accepted point 追加到当前活动笔迹缓冲时读取应用级 Stopwatch，到活动预览 Painter 首次绘制该 inputSeq 时再读同一 Stopwatch；P0 为 StaticCanvasPainter，P1 后为 LocalWetInkPainter；不等于物理显示延迟 | 相对基线改善至少 30%；60 Hz 暂定不高于 33 ms |
| 物理 tip-to-pixel P95 | 至少 240 fps 高速录像，固定分位数算法，采样至少 100 次、推荐 200 次 | 相对改善 25% 为实验目标；绝对目标由 P0 确认 |
| UI build P95 | Flutter FrameTiming `buildDuration` | 不超过设备实测刷新周期 |
| raster P95 | Flutter FrameTiming `rasterDuration` | 不超过设备实测刷新周期 |
| deadline miss ratio | build 或 raster 任一超预算的帧占比 | 60 秒低于 1% |
| 干墨 paint 次数 | PointerDown 至 PointerUp 最终提交前，且无缩放、主题或资源变化 | 0 |
| 活动轮廓与 retained paint | 每帧参与临时轮廓生成的点数，以及冻结前缀是否被普通 PointerMove 重录 | 尾段固定有界；普通 move 不重录 retained prefix |
| 长笔迹上传增长 | N=`250/500/1000/2000` 点的累计点条目和密文字节 | `bytes(2N)/bytes(N)` 在 `[1.7,2.3]`；每点重复次数有固定上限；R² 只作辅助 |
| live 接收队列 | 一个解密处理中任务，加按 senderSocketId 保存的 latest pending 映射 | pending 最多 8 个发送者；同一发送者最多 1 个待处理包；round-robin |
| final Scene 消息等待 | SCENE_UPDATE 是否被临时消息排队阻塞 | 不排在 live backlog 后面 |
| 良好网络远端湿墨 P95 | RTT 20 ms、丢包 0%、抖动不超过 5 ms | 不高于 200 ms，挑战 150 ms |
| 受限网络远端湿墨 P95 | RTT 100 ms、丢包 0% | 不高于 300 ms，挑战 250 ms |

120 Hz 的 8.3 ms 门槛只有在 FrameTiming 证实实际帧间隔低于 10 ms 时启用，不能只按屏幕标称值判断。240 fps 录像存在约 4.17 ms 量化误差，报告必须披露；样本不足 100 时只报告中位数、最差值和原始分布，不宣称稳定 P95。

### 3.3 数据一致性门槛

- P1 对同一 raw recording 使用相同输入模型时，所有被模型接受的点不得因绘制合帧而额外丢失；
- P1 最终点、压力、元素 ID、版本、撤销、保存和导出结果与基线一致；
- P3 移除旧 live snapshot 后，只要求最终 version 合法、单调且不受临时发送频率影响，不要求等于旧路径由 live 广播次数产生的数值；ID、points、pressure、最终格式和冲突仲裁结果必须一致；
- P2 若调参，必须预先定义允许的几何误差和点数差异；
- predicted point 不进入最终元素、历史、AI、持久化和协作包；
- 丢失、重复、乱序 INK_CHUNK 不得破坏最终 SCENE_UPDATE；
- HarmonyOS 优化不得破坏其他五个平台。

## 4. 目标架构

```text
actual PointerEvent
  └─ 输入模型 ─→ accepted actual points
                  ├─→ LocalWetInkStore
                  │     └─ 冻结前缀 + 有界活动尾段 ─→ LocalWetInkPainter
                  ├─→ 20～30 Hz 有界 INK_CHUNK
                  └─→ PointerUp 生成现有 FreedrawElement

predicted point（条件启用）
  └─→ 临时笔尖；actual 到达后替换；永不进入正式数据

PointerUp 最终元素
  ├─→ Scene / History / Save / AI / Excalidraw
  └─→ 现有加密 SCENE_UPDATE

远端 volatile 密文
  └─ 独立有界解密队列 ─→ RemoteWetInkStore ─→ RemoteWetInkPainter

远端 non-volatile/final Scene 密文（不代表持久可靠交付）
  └─ 现有串行解密队列 ─→ 正式 Scene
                              └─ 记录 completedStrokeId 并清除远端湿墨
```

画布层：

```text
RepaintBoundary + DryScenePainter
  已完成元素，以及保持原路径的非自由笔图形 preview

RepaintBoundary + RemoteWetInkPainter
  远端临时自由笔迹；可降频；不进入正式 Scene

RepaintBoundary + LocalWetInkPainter
  本地自由笔迹；最高优先级；一帧最多重绘一次

InteractiveCanvasPainter
  选择框、变换手柄、激光笔等现有交互
```

## 5. 实施原则

1. 先有可复现数据，再允许合入优化；
2. 本地输入优先，临时远端数据可丢、可合并、可降帧；
3. non-volatile/final Scene 消息不进入 live-ink 队列；此命名不代表已经具备 R1 的持久可靠交付；
4. 只分流 `FreedrawElement` preview，其他工具保持原路径；
5. predicted 永不成为事实；
6. 服务端保持零知识，只校验外层可见信息；
7. 第一版不增加房间成员逐端能力协商、二进制协议、CRDT、空间索引和新渲染引擎；服务端仅发送独立 `live-ink-ready` 事件确认事件能力；
8. 使用两个编译值：`FLOWMUSE_LAYERED_WET_INK`、`FLOWMUSE_LIVE_INK_V2`；有效 v2 依赖 layered 和服务端协议版本；
9. 每阶段可通过重新构建关闭并回到原路径，不宣称远程即时回滚；
10. 协议与加密改动必须由非作者复核。

## 6. P0：建立真实、可复现基线（3～4.5 人日）

### P0-0：真实 Profile 回放入口

- 使用 `--dart-define=FLOWMUSE_PERF_TEST=true` 开启内部性能入口；
- 复用 `StrokeRecording`，但必须驱动真实 `MarkdrawController → EditorCanvas → Painter`；
- 现有 `StrokeReplayRunner` 只保留算法基准，不能冒充画布帧基准；
- `FlowMuse-App/pubspec.yaml` 增加 `integration_test: {sdk: flutter}` 并执行 `flutter pub get`；
- 新建 `FlowMuse-App/integration_test/whiteboard_writing_perf_test.dart`、`FlowMuse-App/test_driver/whiteboard_writing_perf_driver.dart` 和 `FlowMuse-App/integration_test/README.md`；
- runner 合成 PointerDown/Move/UpEvent，通过真实 EditorCanvas/Controller 输入入口注入；禁止只在 `TestWidgetsFlutterBinding` 中采集 FrameTiming；
- 固定命令：`flutter drive --profile -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true`；
- runner 必须按 recording 的单调时间差实时调度，禁止沿用 `StrokeReplayRunner` 的同步紧循环，也不对每个事件单独 `pump`；
- 记录每个事件的目标注入时间和实际注入时间；注入 jitter P95 超过 4 ms 或最大值超过 16 ms 时整轮作废并报告；
- README 写明各平台实际命令、结果文件绝对路径和设备拉取命令；
- 支持 100、1000、5000 元素 fixture；
- 记录设备实际刷新周期；
- 性能入口不进入正常用户导航和生产日志。

每个 accepted actual point 分配递增 `inputSeq`，在追加到当前活动笔迹缓冲时用应用级 `Stopwatch` 记录起点。P0 只增加旁路 `ActivePreviewMetricsProbe`，不创建 wet store 或新画层：当前 `StaticCanvasPainter` 绘制 Freedraw preview 时读取 probe 的 high-water mark。P1 分层后由 `LocalWetInkPainter` 读取同一个 probe。两条路径都在 paint 时读取同一 Stopwatch，并把 `(lastPaintedSeq, currentMaxSeq]` 的全部未绘制 seq 配到当前帧；不能只记录最大 seq。probe 按递增 `strokeEpoch` 隔离笔画：PointerUp、Cancel 或工具切换清空活动缓冲前，将当前 epoch 尚未绘制的 seq 标记为 `terminalBeforePreview` 并推进该 epoch watermark；这些 seq 不得与后续笔画配对。`event-to-active-preview-paint proxy` 只使用两次 Stopwatch 读数，确保旧路径基线和新路径同口径。Painter 同时记录 `PlatformDispatcher.frameData.frameNumber`，`SchedulerBinding.addTimingsCallback` 仅按 frameNumber 关联该帧 build/raster 数据；callback 批量上报等待不得进入延迟代理。MVP 不报告 event-to-raster-finish 估算值，也不得直接相减 `PointerEvent.timeStamp` 和 FrameTiming 时间戳。

### P0-1：标准样本

- HarmonyOS 和 Android 真机各录制慢速中文、快速曲线、尖角、压力交替、30 秒长笔迹；
- 双人/五人样本通过测试 transport 驱动，不依赖公网；
- recording 只包含相对坐标、时间、压力和输入类型，不含白板正文或身份；
- 固定随机种子，失败可复现。

P0 必跑门禁矩阵固定为：HarmonyOS 中端、HarmonyOS 高刷、Android 中端 × 100/1000/5000 元素 × 快速书写 60 秒/长笔迹 30 秒 × 5 轮。中文、尖角和压力样本只用于功能与几何验证，不与全部场景规模做笛卡尔积。新增组合必须单独计入工期。

### P0-2：分段埋点

- input normalize/modeler；
- active preview 更新/build 到 paint；P1 分层后再细分 wet notifier 到 paint；
- UI build 和 raster；
- dry paint、wet paint；
- `getStroke`、Path 构造及参与点数；
- live delta 构造、JSON、AES-GCM、发送；
- final Scene/live 队列长度和等待时间；
- remote wet merge 与正式 Scene reconcile。

埋点只记录时长、数量、大小和脱敏 ID 前缀，不记录坐标、密钥、明文或可还原密文。

### P0-3：基线报告

- 固定命令输出 JSON/CSV 和汇总 Markdown；
- 报告设备、系统、实际刷新周期、场景规模、运行轮次和全部指标；
- 软件代理延迟与高速录像分栏；
- 远端自动指标使用同一进程 FakeTransport 单调时钟；跨设备用高速录像或校准采集器。

### 主要文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/stroke_recorder.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- `FlowMuse-App/pubspec.yaml`
- `FlowMuse-App/integration_test/whiteboard_writing_perf_test.dart`
- `FlowMuse-App/integration_test/README.md`
- `FlowMuse-App/test_driver/whiteboard_writing_perf_driver.dart`
- `FlowMuse-App/test/features/whiteboard/`

### 完成定义

- 同一命令驱动真实 Widget/Painter 并生成原始数据和报告；
- 固定 recording 各轮的 accepted seq 总数和最终几何必须一致；当分母大于 0 时，配对覆盖率 `paired / (accepted - terminalBeforePreview)` 至少 99.5%；`terminalBeforePreview` 数量和比例单独报告，新路径不得比同 recording 基线恶化超过 0.5 个百分点；未配对、terminal 和帧分布全部原样报告，不要求不同真机运行的绘制帧数量完全相同；覆盖率不足的整轮作废，任何类别均不得静默删除；
- 5 次运行满足稳定性公式；
- 可分辨 build、raster、活动几何、干墨绘制、加密和远端合并耗时；
- 冷启动最差帧与稳定态分开；
- 未完成 P0 时不得宣称优化效果。

## 7. P1：本地自由笔迹分层与有界活动几何（4～5.5 人日，P1-3 触发时）

### P1-1：独立湿墨通知

- 在 `MarkdrawController` 增加轻量 `Listenable`/`ValueNotifier<int>` 湿墨 revision；
- accepted freedraw move 只更新活动点缓冲并触发湿墨 notifier；
- Freedraw PointerDown、accepted move 和 cancel 只触发 wet notifier；PointerUp 提交最终 Scene 时触发正式通知；工具切换和其他正式状态仍走原通道；
- 不得为了“统一流程”给 Freedraw PointerDown/Cancel 新增顶层通知；
- 一帧内 accepted 点全部追加，但最多安排一次湿墨 repaint；
- 不新增状态管理框架。

### P1-2：只分流自由笔迹 preview

- `buildPreviewElement()` 中矩形、椭圆、菱形、直线、箭头等继续走现有 preview；
- 仅将 `FreedrawElement` 活动预览移出 `StaticCanvasPainter`；
- 增加 `RepaintBoundary + CustomPaint(repaint: wetInkListenable)`；
- 本地湿墨与 dry scene 共用 viewport transform；
- 100 次湿墨通知不得增加 dry `paint()` 次数；
- viewport、主题、资源加载和非自由笔 preview 仍能触发正确重绘。

### P1-3：条件启用 retained prefix 和有界尾段

P1-2 完成后比较 30 秒长笔迹最初 10 秒和最后 10 秒。最后 10 秒 wet raster P95/P99 高出 20% 以上、deadline miss ratio 增长超过 0.5 个百分点、每帧 `getStroke/Path build` 输入点数持续增长，或 retained layer/count 持续增长，任一条件成立才实施 P1-3。

实施时禁止 `LocalWetInkPainter` 每帧处理或重画完整活动笔迹：

- 活动笔迹分为不可变 retained prefix segments 和最近一段可变尾部；
- 每帧只重算固定上限尾部点，并保留固定重叠；
- 初始候选：尾部 64 个 accepted 点、重叠 8 点，仅供实测调节；
- 冻结前缀按固定段落生成不可变 segment/display-list，并放入不随尾段 revision 重绘的独立 RepaintBoundary；普通 PointerMove 不得重新记录或 draw 全部冻结前缀；
- retained prefix 采用一个 consolidated prefix 层、最多 8 个增量 segment 层和一个活动尾段层；活跃笔迹 retained layer 总数硬上限为 10，估算缓存预算上限为 16 MiB；
- 第 8 个增量 segment 冻结时，在受控冻结边界将最旧 4 个 segment 合并进 consolidated prefix，使层数回落；合并只在冻结边界发生，不得由普通 PointerMove 触发；
- 合并实现必须让 layer 数和缓存预算保持有界；若 `ui.Picture` 合并仍导致旧命令在每帧重放，则改用按当前 viewport scale 生成的临时栅格快照。viewport 变化可重建；该快照只用于活动预览，最终矢量元素不受影响；
- 超过 16 MiB 预算时停止新增 retained cache，湿墨前缀降级为低成本折线快照；不得继续无界分配 layer/cache；
- viewport、主题或资源变化时允许统一重建 retained segments，冻结新 segment 的边界帧 P99 必须单独报告；
- 若分段 perfect-freehand 无法无缝连接，湿墨改用轻量圆帽折线，PointerUp 再生成精确轮廓；
- 远端湿墨复用同一有界原则；
- 最终元素仍使用全部 accepted points。

验收同时覆盖：每帧轮廓参与点数、retained layer/display-list 数、`layerCacheCount/layerCacheBytes`、paint 时间、raster P95/P99/最差值、冻结/合并边界帧 P99。任何时刻层数不得超过 10、估算缓存不得超过 16 MiB；把无限增长 Path 留在逐帧 Painter 中不视为完成。

### P1-4：独立清理次要热路径

- 指针移动只更新 `lastActiveAt`，不在每个原始事件中 cancel/new 两个长 Timer；
- 服务端逐帧 `log.Printf` 改为错误日志或聚合计数；
- 两项分别保留行为测试，不与渲染重构混成一个提交。

### P1-G1：按指标决定最终 Path 缓存

只有 P1-2/P1-3 后，completed-freedraw 的 `getStroke + Path build` P95 超过 2 ms，或占 UI paint/frame 时间超过 25%，才实施。raster 超标但 UI Path 构造不高时不得自动启用 Path 对象缓存：

- 使用标准库 `LinkedHashMap<FreedrawPathKey, Path>`，不依赖当前未启用的 Rough cache；
- key 包含 ID、version、versionNonce 和所有轮廓参数；
- 同时限制条目数、源点总数/估算字节和单项成本；
- 超长单笔迹超过预算时不缓存；
- 测试命中、样式/版本失效、淘汰、GC 和峰值内存。

### P1-G2：按指标决定 Scene 派生缓存

只有排序或线性查找 P95 超过 1 ms，或超过 dry paint 时间的 15% 才实施：

- 利用 Scene 不可变性，在每个实例使用 `late final` 缓存 ordered list、byId 和 boundText map；
- 不新增 Scene version 服务或集中刷新器；
- 保证 z-order、删除过滤和绑定文本行为；
- 暂不增加四叉树/R-tree。

### 主要文件

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/rough/freedraw_renderer.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/scene/scene.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-Server/internal/collab/hub.go`

### 自动化测试与完成定义

- 100 个 accepted move 不产生 100 次正式 Scene 通知；
- 100 次湿墨通知期间 dry `paint()` 不增加；
- 非自由笔工具预览不变；
- PointerUp 只提交一个最终元素和一个历史操作；
- 最终 accepted 点、压力和几何与基线一致；
- 触发 P1-3 时，30 秒长笔迹活动尾段点数不超过上限加重叠，普通 move 不重录 retained prefix；
- 缩放、平移后湿墨与最终笔迹不偏移；
- 满足第 3 节本地门槛；
- P1-3、P1-G1/G2 未达触发阈值时明确“不实施”，不算缺项。

## 8. P2：笔尖体验优化（条件阶段，2～4 人日）

P1 后 UI/raster 已达标但物理 tip-to-pixel 仍未达到 P0 目标时才进入。

### P2-1：即时尾段/笔尖帽

- accepted stable points 继续走现有输入模型；
- 湿墨末端额外绘制最后稳定点到最后 actual raw point 的临时尾段；
- 新 actual 替换上一帧尾段；
- 抬笔只使用 accepted actual points；
- 鼠标、触摸、手写笔分别沿用现有策略。

### P2-2：小范围真机调参

- 只测试 One Euro `minCutoff/beta`、最小点距、压力滤波、尾段长度等少量候选；
- 同时评价尖角偏移、慢速抖动、快速延迟、点数和 CPU；
- 调参前确定几何误差门槛；
- 主观盲测只作补充，需记录人数、随机顺序和原始票数。

### P2-3：HarmonyOS Pen Kit 最多 2 人日 spike

- 先确认 Flutter OHOS Surface 是否暴露原生 TouchEvent 和历史点；
- 不能低成本取得则停止，不重写原生画布；
- predicted 只进入本地临时笔尖，actual 到达立即替换；
- 禁止保存、同步、识别和撤销 predicted；
- P95 改善不足 5 ms 或破坏跨平台维护时不合入。

## 9. P3：分离 final Scene 与临时密文通道（7.5～11 人日）

### P3-0：分离可靠和临时密文通道

现有 `server-volatile-broadcast → client-broadcast` 同时承载鼠标、idle 和 visible bounds，必须保持不变以兼容 Presence 和旧客户端。湿墨单独增加：

- 专用外层事件 `server-live-ink → client-live-ink`，两端均使用 volatile 语义；
- 服务端通过当前 socket 上下文给 `client-live-ink` 外层附加经过认证的 `senderSocketId`，正文仍只有 AES-GCM 密文和 IV；
- `RealtimeTransport` 增加 `sendLiveInk()` 和 `Stream<ReceivedLiveInkFrame> liveInkFrames`；现有 `send(..., volatile:true)` 和 `messages` 行为不变；
- `ReceivedLiveInkFrame` 只包含 `senderSocketId + EncryptedPayload`，socketId 只用于临时 store、配额和公平调度，不写逐包日志；
- repository 保留现有 non-volatile/final Scene 串行解密队列；live ink 使用独立 best-effort 调度器；
- 调度器同时最多 1 个解密任务；pending 使用 `senderSocketId → latest ciphertext` 有界映射，同一发送者只留最新包，不同发送者 round-robin；
- pending 最多保留 8 个活跃发送者；超限时按最久未服务发送者/房间策略拒绝新增，不能让单个高频发送者覆盖其他人的最新状态；
- final Scene 消息不得等待 live 队列；
- live 解密/语义校验失败只 drop + 聚合计数，每分钟最多一条脱敏汇总，不进入逐包 repository error 或用户提示。

当前协议没有 join response，禁止修改 `room-user-change` 的现有数组载荷。服务端新增独立 `live-ink-ready` 事件：

- 客户端必须在发送 `join-room` 前注册监听；
- join 成功后，服务端只向当前 socket 发送 `{"roomId": roomId, "liveInkProtocolVersion": 2}`；
- 每次 connect、reconnect、disconnect 或换房先把服务端 live 版本重置为 0；
- 仅在 1 秒内收到与当前连接、当前 roomId 匹配且版本 `>= 2` 的事件时启用 v2；
- 超时、缺字段、房间不匹配或迟到事件都使本次连接继续使用 v1；超时不得阻塞 joined 状态；
- 新服务端仍保留现有 `first-in-room`、`new-user`、`room-user-change` 行为。

有效开关定义为：

```text
effectiveLiveInkV2 =
  FLOWMUSE_LAYERED_WET_INK &&
  FLOWMUSE_LIVE_INK_V2 &&
  serverLiveInkProtocolVersion >= 2
```

新客户端连接旧服务端时因收不到 `live-ink-ready` 自动回退 v1；这只是服务端事件能力确认，不是房间成员逐端 capability 协商。

验收：5 个发送者各 30 包/秒持续 60 秒，队列不超限，每个发送者都有可见更新；从某 sender 出现 pending 到其下一包完成处理的最大连续饥饿时间不超过 200 ms。final Scene 测试消息等待不随 live backlog 增长；Presence 在新旧客户端组合下保持不变。

### P3-1：自包含 `INK_CHUNK` v2

沿用现有包络和大写 wire name：

```json
{
  "type": "INK_CHUNK",
  "payload": {
    "protocolVersion": 2,
    "strokeId": "same-as-final-element-id",
    "startIndex": 84,
    "points": [
      {"x": 1.2, "y": 2.4, "pressure": 0.6}
    ],
    "style": {
      "brushType": "fountainPen",
      "strokeColor": "#000000",
      "strokeWidth": 2.0,
      "opacity": 100
    }
  }
}
```

协议语义：

- `strokeId` 在 PointerDown 预留，必须等于最终 `FreedrawElement.id`；
- `x/y` 是绝对 Scene 坐标，不受最终 minX/minY 转换影响；
- `pressure` 为 0～1；无真实压力时为 `null`；
- `startIndex` 是 `points[0]` 在完整 accepted 序列中的索引；
- 每包携带最小固定 style，避免首包丢失后无法渲染；
- 每包必须携带覆盖最近三个发送周期的滑动窗口，窗口最多 64 点；具体窗口点数由 P0 accepted-rate P99 确定；
- 若三个周期超过 64 点，只保留最新 64 点并显式形成缺口，不突发补发历史临时包；重复点按 `startIndex + points 内下标` 去重；
- 索引有缺口时不跨缺口画长直线，从新子路径开始；
- 每个 accepted point index 最多出现在 3 个实际发出的 INK_CHUNK 中，总传输仍为 O(n)；
- 第一版不增加 `sequence`、时间字段、style 字典、二进制编码和成员能力协商；绝对点索引已经承担去重、乱序和缺口判断。

兼容策略：收到本次连接 `live-ink-ready` 的新客户端发送 INK_CHUNK；旧客户端忽略专用事件且仍接收最终 SCENE_UPDATE。只有产品明确要求旧版本显示实时湿墨时才增加房间成员逐端 capability。

### P3-2：只读取未发送区间

- `FreedrawTool` 提供只读 `[lastSentPointIndex, currentLength)` live delta；
- 不再构造完整 live `FreedrawElement`；
- 默认 20～30 Hz，一帧内新点聚合；
- live sender 全局最多 1 个 in-flight Future 和 1 个可覆盖 pending delta；发送期间的新点只合并到 pending，不创建更多 Future；
- pending 超过 64 点时只保留最新 64 点，并用 startIndex 显式形成临时缺口；不得拆成历史包突发发送；
- PointerUp 顺序为“生成包含最后 accepted 点的 pending 快照 → 发起或覆盖 volatile pending → 提交最终元素 → 清空活动状态”，不等待 volatile Future 完成；
- 最后一批 live delta 可以丢，最终 SCENE_UPDATE 覆盖；
- 第一版省略 `INK_CANCEL`，用超时清理。

### P3-3：RemoteWetInkStore

- 以服务端认证的 `senderSocketId + strokeId` 保存点和样式；
- INK_CHUNK 不进入 Scene reconcile、历史、保存和 AI；
- 按绝对索引去重并立即合并，不增加等待 Timer 或独立重排队列；当前连续段之外的点立即作为新子路径，后到点可填补索引，但不得跨仍存在的缺口连线；
- 远端复用冻结前缀 + 有界尾段；
- 每帧最多 repaint 一次，本地繁忙时远端可降至 15 Hz；
- 收到最终 SCENE_UPDATE 时先记录 completedStrokeId，再清除湿墨；
- completed ID 有界保留 10 秒，覆盖最终消息收到但 finalized set 尚未更新的窗口；
- `RemoteWetInkStore` 维护房间生命周期的 `Set<ElementId> finalizedStrokeIds`：初始 Scene 加载时批量加入已完成 Freedraw ID，收到或应用最终 FreedrawElement 时 O(1) 追加，离开房间时清空；
- 处理 INK_CHUNK 前只做 `finalizedStrokeIds` 和 completed cache 的摊销 O(1) 检查，禁止逐包调用当前线性的 `Scene.getElementById()`；
- 3～5 秒无新增且无最终元素时淡出；退出房间时清空；
- 限制发送者、临时笔迹、单笔点数和房间总点数。

### P3-4：信任边界与校验

服务端只能校验：房间成员、密文/IV 大小、每 socket/房间速率，并统计 non-volatile/live 外层事件；不得解密或记录可还原密文。客户端解密后执行语义校验。第一版固定上限：

| 边界 | 固定值 |
| --- | ---: |
| 单个 live 密文 | 64 KiB |
| IV | 恰好 12 bytes |
| strokeId | UTF-8 后 1～128 bytes |
| 每 socket 速率 | 60 包/秒，burst 120 |
| 每房间速率 | 300 包/秒，burst 600 |
| 每 chunk 点数 | 64 |
| 每 stroke 点数 | 16384 |
| 每房间临时 stroke | 64 |
| 每房间临时点总数 | 65536 |
| `abs(x)` / `abs(y)` | `<= 1e7` |
| pressure | `null` 或 `[0,1]` |
| strokeWidth | `(0,100]` |
| opacity | `[0,100]` |

客户端还必须校验 protocolVersion、strokeId、startIndex、数组结构、有限数和 style 白名单。64 KiB 指解码后的 ciphertext；live endpoint 必须在复制、建表和解密前检查 IV、ciphertext 与可见字段长度，对 `[]any` 兼容形式先检查长度再分配，无法做到时直接拒绝该形式。超限/非法包只丢弃并增加聚合计数，不逐包写日志、抛用户错误或污染 Scene。连接离开时清理服务端限速状态。P0 数据只能有证据地调整这些常量，任何调整必须同步测试。

### P3-5：确定性故障注入

- 增加测试专用 `FaultInjectingRealtimeTransport`；
- 固定 seed，支持 delay/drop/duplicate/reorder/disconnect；
- 失败输出 seed；
- 覆盖首包丢失、连续丢两包、积压、乱序、重复、最终先到、chunk 迟到；
- 公网和真机网络切换只作补充。

### 主要文件

- `FlowMuse-App/lib/features/whiteboard/collaboration/models/collaboration_message.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/realtime_transport.dart`
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/`
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- `FlowMuse-Server/internal/collab/events.go`
- `FlowMuse-Server/internal/collab/hub.go`

### 自动化测试与完成定义

- 对 N=`250/500/1000/2000` 分别测量；每个 accepted point index 最多出现在 3 个实际发出的 chunk 中，累计发送点条目不超过 `3N`，`bytes(2N)/bytes(N)` 在 `[1.7,2.3]`，R² 只作辅助；
- 首包丢失后后续包仍有样式可渲染；
- 重复窗口按索引去重，缺口不生成长直线；
- PointerUp 不遗漏最后一个 accepted 点；
- live sender 始终最多 1 个 in-flight + 1 个 pending，不随加密/发送变慢累积 Future；
- 10% 丢包和乱序不影响最终元素；
- 最终先到、100 ms 和 11 秒后迟到 chunk 都不会重建湿墨；
- 5000 元素、150 live 包/秒时 finalized ID 检查保持摊销 O(1)，不得随 Scene 元素数线性增长；
- 五人 30 包/秒持续 60 秒，队列/内存有界，每个发送者有可见更新，最大连续饥饿时间不超过 200 ms；
- final Scene 消息不等待 live backlog；
- 现有鼠标、idle、visible bounds Presence 在新旧客户端组合中保持工作；
- 旧客户端仍看到最终元素；
- 新客户端连接旧服务端时 v2 自动关闭并回退 v1；
- 无效密文、NaN/Infinity、超限数组和非法 style 被拒绝；
- P3-4 每一个固定安全上限都有边界值和越界值断言；live 解密失败不进入用户错误流，日志每分钟最多一条汇总；
- 满足第 3 节协作门槛；
- AES-GCM 边界保持不变。

## 10. 后续独立项目 R1：最终操作可靠交付

R1 不属于本轮性能 MVP，不进入本方案工期和验收门槛。

开始 R1 前必须单独编写 ADR/设计规格，明确：

1. ACK 表示网关内存接收、密文持久化成功，还是对端应用成功；
2. `deliveryId/opId` 位于加密正文还是外层元数据，以及元数据泄露边界；
3. 零知识服务端只能按不透明 envelope ID 去重，业务 opId 由客户端解密后校验；
4. 如承诺服务端重启不丢，必须持久化密文事件或证明加密快照已包含操作；
5. outbox 保存同一份 ciphertext + IV，禁止明文落新表；
6. 数据库迁移幂等，并覆盖全新安装和旧版本升级；
7. ACK 丢失、重复发送、房间结束、密钥失效、存储上限和清理；
8. Socket.IO connection state recovery 只能作为优化。

语义未确定前，不承诺“服务端重启零丢失”。本轮只验证临时优化不降低现有最终 Scene 行为。

## 11. 任务、依赖与工期

| ID | 任务 | 依赖 | 预计 | 负责人角色 | 复核角色 | 必须验收 |
| --- | --- | --- | ---: | --- | --- | --- |
| P0-0 | 真实 Profile 回放入口 | 无 | 1～1.5d | Flutter 性能 | 非作者 Flutter | 驱动 Widget/Painter、seq/frame 配对 |
| P0-1 | 标准样本与 fixture | P0-0 | 0.5～1d | Flutter 测试 | 性能负责人 | 可重复、脱敏 |
| P0-2 | FrameTiming/Timeline 埋点 | P0-0 | 1d | Flutter 性能 | 非作者 Flutter | 指标与时钟完整 |
| P0-3 | 基线报告脚本 | P0-1/2 | 0.5～1d | 测试/数据 | 性能负责人 | 5 次稳定性 |
| P1-1 | 独立湿墨 notifier | P0 | 1d | Flutter 渲染 | 非作者 Flutter | move 不触发正式通知 |
| P1-2 | 仅 Freedraw 分层 | P1-1 | 1～1.5d | Flutter 渲染 | 性能负责人 | 其他 preview 不回归 |
| P1-3 | retained prefix/尾段 | P1-2 且阈值触发 | 1.5～2.5d | Flutter 渲染 | 性能负责人 | paint/raster 均不递增退化 |
| P1-4 | Timer/日志清理 | 无 | 0.5d | Flutter/Go | 对应非作者 | 行为不变 |
| P1-G1 | 最终 Path 缓存 | 阈值触发 | 1d | Flutter 渲染 | 性能负责人 | 内存和失效 |
| P1-G2 | Scene `late final` 派生缓存 | 阈值触发 | 1d | Flutter 核心 | 非作者 Flutter | z-order/绑定不变 |
| P2 | 笔尖/Pen Kit | P1 未达目标 | 2～4d | 输入/OHOS | 跨平台负责人 | 物理延迟收益 |
| P3-0 | final/live 专用通道 | P0 | 1.5～2d | Dart 协作 + Go | 安全非作者 | Presence 与 backlog 隔离 |
| P3-1 | INK_CHUNK 模型/校验 | P3-0 | 1～1.5d | Dart 协作 | 协议非作者 | 自包含与固定上限 |
| P3-2 | 增量发送/背压 | P3-1 | 1～1.5d | Dart 协作 | 性能负责人 | 字节线性、Future 有界 |
| P3-3 | RemoteWetInkStore/画层 | P1/P3-1 | 2～3d | Dart 协作/渲染 | 非作者 Flutter | 公平且不进入 Scene |
| P3-4 | 信任边界和限流 | P3-1 | 1～1.5d | Go + 安全 | 安全非作者 | 服务端不解密 |
| P3-5 | 故障/兼容测试 | P3-2/3/4 | 1～1.5d | 测试/协作 | 协议非作者 | 故障可复现 |

性能主线 P0+P1+P3 约 15～21 人日：单人约 4～5 周；一名 Flutter 渲染工程师与一名协作/Go 工程师并行约 2.5～3.5 周。P1-3、P1-G1、P1-G2、P2 未触发时不实施。开工前必须把负责人/复核角色映射到具体成员；未分配不得进入 in-progress。协议、加密和安全上限必须由非作者复核。

## 12. 建议执行顺序

1. P0-0～P0-3：真实回放、统一口径、基线；
2. P1-1～P1-2：本地湿墨分层；
3. 同样本复测，仅在阈值触发时做 P1-3/P1-G1/P1-G2；
4. P1-4：Timer 和日志独立清理；
5. P3-0：先隔离临时解密队列；
6. P3-1～P3-4：协议、发送、远端 store 和信任边界；
7. P3-5：五人负载、旧端和确定性故障；
8. 只有物理延迟仍不达标时进入 P2；
9. R1 单独立项。

任一阶段同样本 P95 恶化超过 10%，先回滚并分析 Timeline，不继续叠加。

## 13. 测试矩阵

### 13.1 功能与性能

- 输入：鼠标、触摸、手写笔；
- 工具：自由笔、荧光笔、橡皮、矩形、椭圆、菱形、线、箭头、选择；
- 操作：抬笔、取消、切工具、撤销、重做、保存、重进、导出；
- 视图：缩放、平移、高 DPI；
- 协作：单人、2 人、5 人同时绘制；
- 场景：100/1000/5000 元素，单条 30 秒长笔迹，连续书写 60 秒；
- 数据：ID、version、versionNonce、points、pressure、z-order、绑定文本。

### 13.2 确定性网络故障

- RTT 20/100/300 ms；
- 丢包 0%/5%/10%；
- 首包丢失、连续丢两包；
- 重复、乱序、延迟、断开；
- 最终元素先到、临时包迟到；
- 旧客户端忽略 v2；
- 固定 seed 并输出失败 seed。

最终正确性以正式 Scene 的元素 ID、版本、点数组和顺序为准。临时动画可短暂缺口，但不得留下永久错误。

### 13.3 平台

- HarmonyOS：完整功能、性能和手写笔主验收；
- Android：中端与高刷设备功能/性能回归；
- iOS：功能和基础性能回归；
- macOS、Windows、Web：编译、鼠标输入和协作回归。

### 13.4 PR 必跑验证

- 所有 Flutter PR：`flutter analyze`、`flutter test`；
- P3 服务端改动：在 `FlowMuse-Server` 执行 `go test ./...`、`go vet ./...`；
- P3 运行 v1/v2、Presence、新 client + 旧 server、新 server + 旧 client 组合测试；
- 涉及 HarmonyOS 原生输入时执行 `flutter build hap`；
- Android、Web、Windows 与 iOS、macOS 的构建证据可来自不同平台 runner，但必须附在对应阶段验收记录；
- 真机性能 runner 的命令、设备、原始结果路径和报告必须进入 PR 证据。

## 14. 发布、开关与回滚

仓库当前没有远程配置、在线分流和崩溃率采集，本轮不宣称 10% 在线灰度。

### 发布

- 两个开关使用 `bool.fromEnvironment`；
- `effectiveLiveInkV2` 必须同时满足 layered 开关、v2 开关和服务端 `liveInkProtocolVersion >= 2`；关闭 layered 自动关闭 v2 发送/接收并回退 v1；
- 生成旧路径 A 包和新路径 B 包；
- 固定设备矩阵各完成 5 次回放和 30 分钟人工书写；
- 固定回放 100 轮出现任何归因于新路径的崩溃即停止；
- 数据一致且性能达标后发布默认开启构建；
- 发布顺序固定为“先部署兼容 `server-live-ink/client-live-ink` 的服务端，再发布启用 v2 的客户端”；回滚顺序相反，先发布/配置关闭 v2 的客户端构建，再回滚服务端；
- 将来有远程配置和生产遥测后再设计百分比灰度。

### 回滚条件

- accepted 点因绘制合帧额外丢失；
- 撤销、保存、导出或最终 Scene 改变；
- P95 build/raster/event proxy 恶化超过 10%；
- dry paint 未隔离；
- live 队列或 RemoteWetInkStore 超限；
- 旧客户端看不到最终元素；
- 加密边界或日志脱敏被破坏。

### 回滚保证

- 分层只改变临时渲染；
- INK_CHUNK 只改变临时动画；
- 最终 SCENE_UPDATE 格式不变；
- 服务端不保存 INK_CHUNK，无数据迁移；
- 关闭编译开关回到旧路径；
- 编译开关不具备远程即时关闭能力，发布后回滚需要重新分发关闭开关的构建；
- 新路径完成一次正式版本稳定验证前不删除旧路径。

## 15. 风险控制

| 风险 | 控制 |
| --- | --- |
| 湿墨与干墨坐标错位 | 共用 viewport transform；缩放/平移测试 |
| 分段轮廓接缝 | 固定重叠；必要时湿墨降级圆帽折线 |
| 长笔迹仍全量计算或重画 | 尾段点数硬上限；retained prefix 独立边界；普通 move 不重录前缀 |
| live 首包丢失 | 每包携带样式和强制三周期滑动窗口 |
| 缺包形成长直线 | 索引缺口后开启新子路径 |
| 最终后迟到包形成幽灵笔迹 | completed cache + 正式 Scene 永久检查 |
| 临时解密阻塞 final Scene 消息 | 专用事件、独立队列、逐 sender latest + round-robin |
| 改道 volatile 破坏 Presence | 保留现有通道；湿墨使用 server/client-live-ink 专用事件 |
| 远端湿墨内存增长 | 发送者/笔迹/点数/总量/TTL 上限 |
| 服务端越过 E2E 边界 | 只校验成员、密文大小和速率 |
| 旧端/旧服务端不兼容 | 服务端版本确认、服务端先发布、最终格式和现有 Presence 不变 |
| Path 缓存内存不可控 | 仅指标触发，按点数/估算字节限制 |
| Pen Kit 污染共享代码 | 最多 2 人日 spike，平台层收口 |

## 16. 明确不做

- 不迁移 Yjs、Automerge 或其他 CRDT；
- 不重写原生 Skia/ArkUI 整页画布；
- 不新增全局状态管理框架；
- 不在第一版引入二进制协议；
- 不提前加入四叉树/R-tree；
- 不把每个 PointerEvent 投递 isolate；
- 不改变 Excalidraw 最终元素；
- 不同步 predicted points；
- 不给第一版增加房间成员逐端 capability 协商；只保留服务端 `live-ink-ready` 事件确认；
- 不把 presence/INK_CHUNK 放进 outbox；
- 不在性能方案中承诺服务端重启零丢失。

## 17. 文档同步要求

- 渲染分层同步 `docs/技术设计/前端架构.md`；
- INK_CHUNK/transport 同步 `docs/技术设计/接口设计.md`；
- HarmonyOS Platform Channel 同步平台适配说明；
- 重大偏离必须在 PR 给出真机数据和替代指标。

本方案承接但不删除：

- `docs/研发记录/plans/2026-07-09-stroke-smoothing.md`
- `docs/研发记录/specs/2026-07-09-stroke-smoothing-design.md`
- `docs/研发记录/plans/2026-07-12-collab-phase0-heat-path-fix.md`

## 18. 成熟方案参考

- Flutter 真机 Profile、UI/raster：
  https://docs.flutter.dev/perf/best-practices
  https://docs.flutter.dev/perf/ui-performance
- Apple actual/coalesced 与 temporary predicted touches：
  https://developer.apple.com/documentation/uikit/getting-high-fidelity-input-with-coalesced-touches
  https://developer.apple.com/documentation/uikit/minimizing-latency-with-predicted-touches
- Android Jetpack Ink in-progress/final stroke：
  https://developer.android.com/develop/ui/compose/touch-input/stylus-input/ink-api-modules
  https://developer.android.com/develop/ui/views/touch-and-input/stylus-input/advanced-stylus-features
- Figma 本地交互优先、增量协作和可靠 journal：
  https://www.figma.com/blog/keeping-figma-fast/
  https://www.figma.com/blog/how-figmas-multiplayer-technology-works/
  https://www.figma.com/blog/making-multiplayer-more-reliable/
- Socket.IO volatile、交付语义和恢复边界：
  https://socket.io/docs/v4/emitting-events/#volatile-events
  https://socket.io/docs/v4/delivery-guarantees/
  https://socket.io/docs/v4/connection-state-recovery
- perfect-freehand 完整输入生成轮廓：
  https://github.com/steveruizok/perfect-freehand
- HarmonyOS Pen Kit：
  `harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/`

## 19. 最终验收清单

### P0

- [ ] 真实 Widget/Painter Profile 回放可重复；
- [ ] inputSeq、frameNumber 和单调时钟配对可复现，未配对点单独报告；
- [ ] 软件代理与物理延迟分开报告；
- [ ] 原始数据和报告自动生成；
- [ ] 指标稳定性满足公式。

### P1

- [ ] accepted move 不逐点触发顶层正式更新；
- [ ] 自由笔活动期间 dry paint 为 0；
- [ ] 非自由笔 preview 无回归；
- [ ] 触发 P1-3 时，活动尾段有界且普通 move 不重录 retained prefix；
- [ ] 触发 P1-3 时 retained layer 不超过 10、估算缓存不超过 16 MiB，冻结/合并边界帧单独报告；
- [ ] 最终数据、撤销、保存和导出一致；
- [ ] P1-G1/G2 有触发证据或明确不实施。

### P3

- [ ] 现有 Presence 通道保持不变，湿墨使用专用 server/client-live-ink；
- [ ] final/live stream 和解密队列分离；
- [ ] live 队列最多一个处理中、每 sender 一个 pending、总 sender 不超过 8，并采用 round-robin；
- [ ] live sender 最多一个 in-flight 和一个 pending Future；
- [ ] 每个 INK_CHUNK 自包含样式和坐标语义；
- [ ] 累计字节随 accepted 点线性增长；
- [ ] 远端湿墨不进入 Scene；
- [ ] 首包丢失、连续丢包、乱序、重复和迟到测试通过；
- [ ] 五人负载下本地输入优先、每个发送者最大连续饥饿时间不超过 200 ms 且内存有界；
- [ ] 旧客户端显示最终元素；
- [ ] 新客户端连接旧服务端自动回退 v1，Presence 不受影响；
- [ ] 每个固定安全上限都有边界测试；
- [ ] finalizedStrokeIds 检查摊销 O(1)，没有逐包线性 Scene 查询；
- [ ] 服务端未读取或记录加密正文。

### 发布

- [ ] layered 可独立关闭；v2 仅在 layered、v2 编译值和服务端协议版本同时满足时生效；
- [ ] 六平台编译和基础行为通过；
- [ ] A/B 固定设备回放达到门槛；
- [ ] 固定回放 100 轮无新路径崩溃；
- [ ] 架构和接口设计文档已同步；
- [ ] R1 未混入性能主线。

只有功能正确、量化指标达标、故障测试通过三者同时满足，阶段任务才可标记完成。
