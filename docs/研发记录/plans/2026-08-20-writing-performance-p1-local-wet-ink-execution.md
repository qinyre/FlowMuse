# P1：本地 Freedraw 湿墨分层执行计划

> 日期：2026-08-20  
> 状态：批准执行（三方终审无 findings）  
> 必要依赖：P0 completed  
> 预计：3.5～6 人日（不含未触发条件项）

## 1. 目标和不可变条件

只把**本地活动 Freedraw 预览**从整 Scene 重绘中分离。最终 `FreedrawElement`、Scene JSON、history、undo/redo、AI、保存与协作最终消息完全不变；shape/text/image 等工具仍走旧路径。

`FreedrawTool/ActiveFreedrawView` 只拥有点列、唯一 `strokeId`、P0 probe 的本地 `strokeEpoch` 和活动生命周期。P1 不引入网络状态；P3 的 `LiveInkSender` 才拥有发送窗口和背压。

## 2. P1 验收门槛

使用 P0 冻结的设备、SHA 基线、runner、fixture、样本数和算法，分别以 `FLOWMUSE_LAYERED_WET_INK=false/true` 运行：

- event-to-local-paint proxy P95 必须达到 P0 绝对目标（60Hz 默认 ≤33.4ms）且相对旧路径改善 ≥30%；
- build P95、raster P95 均不超过真机实测帧周期；固定 60 秒窗口内 deadline miss <1%，且相对旧路径不回退；
- 100/1000/5000 元素和 2/5 人协作下最终 Scene hash 一致；
- PointerUp/Cancel/工具切换、undo/redo 与压力笔回归通过；
- flag=false 与 P0 旧路径语义一致。

只达到相对改善、未达到绝对目标不能通过。

## 3. Task P1-0：单一分层开关

**负责人/复核：** qinyre / Tiax；**估时：** 0.25d；**前置：** P0-4。

**执行状态：** 已实现单次环境读取、默认关闭且可注入的只读 effective value，并通过单元测试。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/config/writing_feature_flags.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/config/writing_feature_flags_test.dart`

`FLOWMUSE_LAYERED_WET_INK` 默认 `false`。只从 `bool.fromEnvironment` 读取一次，向下传只读 effective value；禁止散落读取和运行时双状态源。

## 4. Task P1-1：活动状态与专用 notifier

**负责人/复核：** qinyre / Tiax；**估时：** 1d；**前置：** P1-0。

**执行状态：** 已完成；活动笔迹使用稳定 `strokeId` 与专用 notifier，PointerUp 同步交接 final，Cancel/切换/dispose 与 flag=false 回退均已由测试覆盖。

### 文件

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools/freedraw_tool.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/local_wet_ink_state.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/editor/tools/freedraw_tool_test.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/local_wet_ink_state_test.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/ui/markdraw_controller_test.dart`

### 状态语义

- PointerDown 创建新的 `strokeEpoch` 和最终元素会复用的稳定 `strokeId`；PointerMove 只追加 tool 已接受的点。
- flag=true 且 Freedraw 活动时只通知 `localWetInkNotifier`，不因每个 move 调用整编辑器 `notifyListeners()`。
- PointerUp 的同一同步事件中：Tool 先用当前点列构造 final `AddElementResult` 并清活动状态，Controller 随即 apply final，然后事件返回；两步之间不得安排 frame，所以不存在空白中间帧。
- P3 若启用，PointerUp 的 pending live 快照必须在 Tool 清点列之前取得；该约束由 P3-2 实现和测试。
- PointerCancel、工具切换、页面 dispose 清活动状态但不提交 final；flag=false 完整走旧逻辑。

### 先失败测试

- 100 个 move 只增加 wet notifier 次数，Controller 整体通知不随 move 线性增长；
- final ID/points/bounds/hash 与旧路径相同；
- Down/Move/Up、Cancel、工具切换、dispose、flag=false；
- P0 probe 的 `strokeEpoch` 在跨笔/terminal 情况不误配。

## 5. Task P1-2：本地湿墨画层接入

**负责人/复核：** qinyre / Tiax；**估时：** 1.5d；**前置：** P1-1。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/local_wet_ink_painter_test.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/ui/editor_canvas_test.dart`

### 画层

```text
background/grid → committed StaticCanvasPainter → local wet ink → remote wet ink(P3) → selection/UI
```

- flag=true 的活动 Freedraw 不再作为 live element 传给 `StaticCanvasPainter`；避免一笔被画两次。
- Painter 复用现有 Freedraw 样式/压力曲线与 canvas transform；首包带完整样式，后续只读活动状态。
- repaint 仅监听 `localWetInkNotifier`；不得重建页面或写 Scene。
- Painter.paint 调用 P0 probe 的 `onSamplePainted`；无额外 Timer。
- Golden/recording 校验 zoom/pan、DPR、压力/无压力、单点/长笔、final 接管无闪烁。

## 6. P1-2 后的唯一条件判定

P1-3/G1/G2 必须在 P1-2 合并后、使用同一 P0 fixture 和门槛重新采样。P0 的 hotspot 只作候选，不能直接开工。每项将 raw evidence 和 `triggered/not_triggered/rejected` 写入 P1 报告。

### Task P1-3：有界 retained prefix（条件）

**触发：** P1-2 后比较同一 30 秒长笔迹最初/最后 10 秒；最后 10 秒 wet raster P95/P99 高出 >20%、deadline miss 增长 >0.5 个百分点、每帧 getStroke/Path 输入点持续增长、或 retained layer/count 持续增长，任一成立才触发。  
**负责人/复核：** qinyre / Tiax；**估时：** 1～2d；**前置：** P1-2 复测。

文件：

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/retained_freedraw_prefix.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/retained_freedraw_prefix_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart`

硬边界：tail 初始 64 点并固定重叠 8 点；最多 1 个 consolidated prefix、8 个 immutable incremental segment 和 1 个活动 tail 层，总层数 ≤10、估算缓存 ≤16MiB。第 8 个 segment 冻结时只在冻结边界把最旧 4 个合入 consolidated prefix；普通 move 不得触发合并或重录全部前缀。若 picture 仍逐帧重放旧命令则使用按当前 viewport scale 的临时栅格快照；超预算降级为低成本折线快照，不得无界分配。冻结/合并边界帧 P99 单列；验收包含 16k/64k 点和内存峰值。

### Task P1-G1：Path 派生缓存（条件）

**触发：** 仅在 P1-2/P1-3 后 completed-Freedraw 的 `getStroke + Path build` P95 >2ms，或占 UI paint/frame >25%。  
缓存用标准库 `LinkedHashMap`；key 包含 ID/version/versionNonce 和全部轮廓参数，同时限制条目数、源点数/估算字节和单项成本，超长单笔超过预算不缓存。未达到触发条件标 `not_triggered`。

### Task P1-G2：Scene 派生缓存（条件）

**触发：** 仅在排序或线性查找 P95 >1ms，或 >dry paint 时间的 15%。  
利用 Scene 不可变性在实例中使用 `late final` 缓存 ordered list、byId 和 boundText map；不增加 Scene version 服务、集中刷新器或空间索引，保证 z-order/删除过滤/绑定文本行为。

## 7. Task P1-4：独立清理 Timer 与逐帧日志

**负责人/复核：** Enchograph / qinyre；**估时：** 0.5d；**前置：** P0-4；可与 P1 并行但不得进入 P0 固定 SHA。

- 客户端销毁/断开时取消协作 Timer/订阅；服务端高频帧日志降为计数器或 debug sampling。
- 只修改已有生命周期点；不新建 scheduler/日志框架。
- Go 测试写入 `FlowMuse-Server/internal/collab/hub_test.go`；验证 disconnect 后无 tick/泄漏、高频 live 不逐帧输出正文。

## 8. 固定验证命令

```powershell
Push-Location FlowMuse-App
flutter analyze
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard
flutter test
flutter drive --profile --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=false
flutter drive --profile --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=true
Pop-Location

Push-Location FlowMuse-Server
go test ./...
go vet ./...
Pop-Location
```

## 9. 回滚与 DoD

- 首选回滚：构建 `FLOWMUSE_LAYERED_WET_INK=false`；retained/cache 全是内存态，无迁移。
- P1 completed：P1-0/1/2/4 通过；绝对/相对门槛通过；final hash 与旧路径一致；P1-3/G1/G2 各有同一 fixture 的触发证据并完成，或明确 `not_triggered/rejected`；六平台 analyze/test 无新增失败。
