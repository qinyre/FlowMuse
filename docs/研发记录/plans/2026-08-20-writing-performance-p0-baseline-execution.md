# P0：书写性能真实基线执行计划

> 日期：2026-08-20  
> 状态：批准执行（三方终审无 findings）  
> 预计：4～6 人日  
> 唯一输出：测量设施、旧路径基线、冻结门槛；不做优化

## 1. 完成定义

P0 必须在固定提交 SHA、真机 Profile、固定 Dart fixture 和固定算法下复现：

1. input modeler 接受并追加的点到 `Local/Static Painter.paint` 首次消费该点的活动预览延迟；
2. 对应帧的 build/raster `FrameTiming`、jank、最长连续掉帧；
3. 100/1000/5000 元素的画布结果；
4. 2/5 个内存房间成员下 JSON → AES-GCM → transport → decrypt → reconcile 的 CPU/分配基线。

第 4 项是**非 UI 协作流水线基线**，不得用来宣称帧率或 stylus-to-photon 结论。P0 只给出 P1-3/G1/G2 的候选热点；是否触发必须在 P1-2 后用同一 runner/fixture 复测决定。

## 2. 冻结测量语义

- 活动预览主指标：raw Pointer 经过 input modeler、被接受并实际追加到活动点缓冲后，记录单调时钟与 `inputSeq/strokeEpoch`；Painter 实际消费该 accepted 点时记录单调时钟。两者差值是 event-to-paint proxy。raw/rejected 样本只另计数量，不进入延迟、missing 或 coverage 分母。
- `addTimingsCallback` 只按 `frameNumber` 挂接 build/raster 时长，绝不把回调到达时间当延迟。Profile 下回调可能批量到达。
- PointerUp 前已看到 terminal 的样本、跨 `strokeEpoch` 样本、未 paint 样本分开计数；不得把下一笔的 paint 误配给上一笔。
- 固定 nearest-rank P95：排序后取 `ceil(0.95*n)-1`；每场景预热 5 秒、测量 60 秒、独立运行 5 轮，报告各轮 P50/P95/P99/最差值和 5 轮中位数；`(max(runP95)-min(runP95))/median(runP95) <= 10%`。样本少于 100 标记 invalid。
- 所有 probe 是旁路观测：不得增加 `notifyListeners()`、不得改变 Scene、不得驱动真实逻辑。

## 3. Task P0-0：真机 Profile runner

**负责人/复核：** Tiax / qinyre；**估时：** 1d；**前置：** 无。

**执行状态：** runner、host driver、依赖和文档已实现；真机 Profile 运行与原始结果为 `deferred_device`。

### 文件

- Modify: `FlowMuse-App/pubspec.yaml`、`FlowMuse-App/pubspec.lock`（仅 `integration_test` SDK dev dependency）
- Create: `FlowMuse-App/integration_test/whiteboard_writing_perf_test.dart`
- Create: `FlowMuse-App/test_driver/whiteboard_writing_perf_driver.dart`
- Create: `FlowMuse-App/integration_test/README.md`

### 任务

- 仅 `--dart-define=FLOWMUSE_PERF_TEST=true` 启用入口；正式命令还必须用同一个唯一真机 ID 填写 `-d` 与 `FLOWMUSE_DEVICE_ID`，并声明设备类/物理设备；普通构建不注册性能页面。
- 必须用真实 `Widget`、真实 Pointer 注入、真实帧；算法 replay 只校验 fixture，不计帧性能。
- 必跑矩阵固定为 HarmonyOS 60Hz 中端、HarmonyOS 高刷、Android 中端 × 100/1000/5000 元素 × 快速书写 60 秒/长笔迹 30 秒 × 5 轮；中文、尖角、压力样本只作功能/几何验证，不做全笛卡尔积。
- recording 按单调时间差实时注入，不使用同步紧循环或每事件单独 pump；记录目标/实际注入时间，jitter P95 >4ms 或 max >16ms 的整轮 invalid。前 5 个 warm-up frame、首次 shader/图片解码不入稳定态但单列最差值。
- 原始 JSON 写入应用可访问目录，driver 输出绝对路径；记录 Git SHA、dirty 状态、设备/系统、刷新率、构建模式和 flags。
- README 给出 HarmonyOS/Android 的设备选择、运行与拉取命令；其余平台至少保证测试代码可编译。

```powershell
Push-Location FlowMuse-App
flutter pub get
flutter drive --profile -d <唯一真机ID> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_DEVICE_ID=<唯一真机ID> --dart-define=FLOWMUSE_DEVICE_CLASS=<冻结设备类> --dart-define=FLOWMUSE_PHYSICAL_DEVICE=true --dart-define=FLOWMUSE_SCENE_ELEMENTS=100 --dart-define=FLOWMUSE_WRITING_FIXTURE=quick_zigzag --dart-define=FLOWMUSE_RUN_INDEX=1
Pop-Location
```

## 4. Task P0-1：ActivePreviewMetricsProbe

**负责人/复核：** qinyre / Tiax；**估时：** 1d；**前置：** P0-0。

**执行状态：** 已实现并通过单元/Widget 测试；真机 Profile 数据仍按总约束记为 `deferred_device`。

### 文件

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/input/active_preview_metrics_probe_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`

### 最小接口与配对规则

- `recordAcceptedPoint(strokeEpoch, inputSeq, Stopwatch.elapsedMicroseconds)`；
- `recordPaintedThrough(strokeEpoch, currentMaxInputSeq, frameNumber, Stopwatch.elapsedMicroseconds)`：把 `(lastPaintedSeq,currentMaxInputSeq]` 的全部 accepted seq 配到本帧，不能只记录最大 seq；
- `recordRejectedRawSample(strokeEpoch, reason)`（仅计数）；
- `finishStroke(strokeEpoch, reason)`；
- 同一 `strokeEpoch` 单调匹配；同一 sample 只记录首次 paint；PointerCancel/工具切换/PointerUp 后迟到 paint 标记 `terminalBeforePreview`，不进入主分母。
- probe 可禁用、无全局单例、无 Timer；禁用时热路径只做一次布尔判断。

### 测试

- 正常、重复 paint、丢帧、跨笔、cancel、terminal-before-preview、frameNumber 附着；
- probe 开关前后 Scene JSON、history 和通知次数完全一致。

## 5. Task P0-2：FrameTiming、Timeline 与报告 schema

**负责人/复核：** qinyre / Tiax；**估时：** 0.75d；**前置：** P0-0。

**执行状态：** 已实现并通过报告 schema、活动预览和协作仓库回归测试；真机 FrameTiming 结果为 `deferred_device`。

### 文件

- Modify: `FlowMuse-App/integration_test/whiteboard_writing_perf_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/writing_performance_report.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/input/writing_performance_report_test.dart`

### 任务

- `FrameTiming` 保存 frameNumber、build、raster、totalSpan；与 probe 的 frameNumber 关联，但不替代 event-to-paint。
- debug/profile-only Timeline 分段：input/model、active element build、static paint、JSON、AES-GCM、transport send、decrypt/reconcile。
- 只记录时长、数量、密文字节数和脱敏 ID 前缀；不记录密码、nonce、明文或完整协作正文。
- schema 包含 version、invalidReasons、missingPaint、terminalBeforePreview、coverage；报告器拒绝未知版本。

## 6. Task P0-3：可打包的固定 fixture

**负责人/复核：** Tiax / qinyre；**估时：** 0.75d；**前置：** P0-0。

**执行状态：** 已实现 5 类书写 recording 与 100/1000/5000 元素场景；确定性、modeler accepted 数、JSON round-trip 和真实编辑器 codec 加载测试通过。

### 文件

- Create: `FlowMuse-App/integration_test/fixtures/writing_recordings.dart`
- Create: `FlowMuse-App/integration_test/fixtures/scene_fixtures.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/input/writing_fixture_test.dart`

fixture 使用编译进测试 bundle 的 Dart 常量/固定 seed 生成器，不依赖未声明的 JSON asset。

- writing：短横、长曲线、快速折返、压力/无压力、PointerCancel；每条有 schemaVersion、seed、raw/accepted 预期样本数。
- scene：100/1000/5000 元素，覆盖 Freedraw/shape/text/image 占位/z-order；5000 是压力门禁，设备失败必须原样报告，不得静默降级；只引用仓库已有测试资源。
- 单测验证确定性、坐标范围、样本数和序列化稳定性。

## 7. Task P0-3B：2/5 人协作 CPU 基线

**负责人/复核：** Enchograph / qinyre；**估时：** 1d；**前置：** P0-0/P0-2/P0-3。

**执行状态：** 真实 2/5 人 repository 内存流水线、分段 probe、100/1000 次正式场景和非 UI 报告已实现；缩短迭代的单元回归通过，完整 Profile 基线为 `deferred_device`。

### 文件

- Create: `FlowMuse-App/integration_test/collaboration_pipeline_perf_test.dart`
- Create: `FlowMuse-App/integration_test/fixtures/collaboration_scenarios.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_performance_probe.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/repositories/collaboration_repository.dart`
- Create: `FlowMuse-App/test/features/whiteboard/collaboration/services/collaboration_perf_harness_test.dart`

### 真实仓库路径

- 复用 `MemoryRealtimeRoomHub`/对应 memory transport；建立 2 个和 5 个真实 `CollaborationRepository` 实例。
- 使用固定房间密钥和固定场景操作，执行 repository 的 JSON、AES-GCM、send、receive、decrypt、reconcile；不创建第二套模拟加密/合并实现。
- 每场景预热 100 次，测量 1000 次；记录每段 CPU 时间、密文字节数、分配近似值、错误数和最终 Scene hash。
- 该 runner 不测 Socket.IO 网络 RTT，也不把结果合并到 UI frame P95；报告必须分栏标注 `collaboration_cpu_non_ui`。

## 8. Task P0-4：基线、门槛与不可变证据

**负责人/复核：** Tiax / 任逸青；**估时：** 0.5d；**前置：** P0-0/1/2/3/3B。

**执行状态：** 版本化 manifest 已冻结正式 fixture/hash/时长/场景 hash/刷新率目标；runner 使用设备实测刷新率，driver 完整扫描设备列表并要求唯一匹配真机。raw 携带 canonical final Scene，汇总器按 `--phase p0|p1` 独立 round-trip Scene、重算 canonical/semantic hash、Freedraw 数量、唯一 `(strokeEpoch,inputSeq)`、覆盖率和帧覆盖。非真机测试已通过；所有真机数值保持 `not_measured/deferred_device`。

### 文件

- Create: `FlowMuse-App/tool/writing_perf/summarize_results.dart`
- Create: `FlowMuse-App/test/tool/writing_perf/summarize_results_test.dart`
- Modify: `FlowMuse-App/integration_test/whiteboard_writing_perf_test.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/active_preview_metrics_probe.dart`
- Modify: `FlowMuse-App/test_driver/whiteboard_writing_perf_driver.dart`
- Modify: `FlowMuse-App/integration_test/README.md`
- Create: `docs/研发记录/research/writing-performance-p0-baseline.md`

### 开跑前冻结的目标

| 设备类 | event-to-paint P95 | 物理 stylus-to-photon P95 |
| --- | ---: | ---: |
| 实测约 60Hz | ≤33ms | ≤50ms |
| 实测帧间隔 <10ms | ≤实测刷新周期（120Hz 约 8.3ms） | ≤35ms |
| 其他刷新率 | 第一次基线前由负责人/复核人填写并冻结 | 第一次基线前由负责人/复核人填写并冻结 |

无可用高速摄像/光电测量时，物理列记为 `not_measured`，不得由 event proxy 推算。目标、设备分类、P95 算法、fixture hash、Git SHA、样本数由负责人和复核人在第一次基线运行前签名冻结；后续只能新建版本，不能覆盖旧基线。

报告器生成 CSV/Markdown，并列出 raw path、有效率、invalid 原因和 95% bootstrap 区间。P0 可标注 P1-3/G1/G2 `candidate_hotspot`，不得标注 triggered。

```powershell
Push-Location FlowMuse-App
dart run tool/writing_perf/summarize_results.dart --phase p0 --input <raw-directory> --output ../docs/研发记录/research/writing-performance-p0-baseline.md
flutter analyze
flutter test test/features/whiteboard/editor_core
flutter test test/features/whiteboard/collaboration
flutter test test/tool/writing_perf
flutter test
Pop-Location
```

## 9. 回滚与 DoD

- 删除性能入口/probe 并移除 dev dependency 即可回滚；fixture/report 无生产数据迁移。
- P0 completed 需要：真机 raw 可复现；`paired/(accepted-terminalBeforePreview) >=99.5%`，terminal 比例单列且新路径不得比同 recording 基线恶化 >0.5 个百分点；5 轮满足稳定性公式；所有 invalid 可解释；2/5 人协作 hash 收敛；目标已在运行前签名冻结；普通构建行为和产物不含性能入口。
- 任何以 Debug、纯算法 replay、timings callback 到达时钟或后改阈值形成的“基线”均判失败。
