# P2：笔尖延迟条件优化执行计划

> 日期：2026-08-20  
> 状态：计划已批准；条件未触发，默认不启动  
> 预计：2～4 人日；Pen Kit spike 最多 2 人日  
> 前置：P0/P1 completed，P0 已冻结物理目标

## 1. 唯一启动门禁

P1 使用 P0 同一设备/fixture 达到 event-to-paint 目标，但高速摄像或光电测量的 stylus-to-photon P95 仍超过 P0 冻结目标，并且差异超过测量误差区间时启动。没有物理测量则标记 `not_triggered`，不得用 event proxy 推断。

## 2. Task P2-0：冻结配对实验

**负责人/复核：** qinyre / Tiax；**估时：** 0.25d。

- 引用 P0 报告中的设备、刷新率、物理目标、相机帧率/光电装置、误差和 P95 算法；禁止事后修改。
- A/B 共用同一构建 SHA、场景、笔、动作脚本和环境；轮换 AB/BA，5 轮，每轮每 variant 有效样本 ≥100。
- 所有候选先保持最终点列/Scene hash 相同；任何预测点只用于活动视觉层。

## 3. Task P2-1：最小即时尾段/笔尖帽

**负责人/复核：** qinyre / Tiax；**估时：** 0.75～1d；**前置：** P2-0。

### 文件

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/local_wet_ink_painter.dart`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/rendering/immediate_freedraw_tip_test.dart`

- 只画最近 raw pointer 到最后 accepted/modelled point 的短尾段；最多 2 点、长度上限 24 logical px。
- PointerUp/Cancel/工具切换立即清；不进入 element JSON/history/AI/协作，也不改变 final geometry。
- 超过 24px、方向反转 >90°、时间间隔 >32ms 或非 Freedraw 时不画，避免飞线。
- 若物理 P95 无稳定收益或视觉错误率上升，直接删除，不叠加预测框架。

## 4. Task P2-2：小范围参数矩阵

**负责人/复核：** qinyre / Tiax；**估时：** 0.75～1.5d；**前置：** P2-1 仍未达目标。

只测试现有 input modeler 中 3 个可解释参数，每个 baseline/low/high；先单因素淘汰，完整 fixture 最多 3 个组合，禁止笛卡尔积。候选必须同时满足：final hash 不变、视觉错误不增加、CPU P95 不回退 >5%。结果写入 `docs/研发记录/research/writing-tip-latency-p2.md`。

## 5. Task P2-3：HarmonyOS Pen Kit 两阶段 spike

**负责人/复核：** Tiax / qinyre；**总 timebox：** ≤2d；**前置：** P2-1/2 后 app-side 达标但物理延迟仍失败。

### 必读本地资料

- `../harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-point-prediction.md`
- `../harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-stylus-interaction.md`
- `../harmonyos-guides/系统/硬件/Pen Kit（手写笔服务）/手写功能开发/pen-suite.md`

不引用不存在于该目录的 `pen-point-prediction-c.md`。

### Spike A：0.5d 可用性/契约（不接生产输入链）

输出：支持的 API/系统版本/设备，线程和坐标语义，生命周期、权限、失败码、预测点有效期，以及固定 MethodChannel 契约：

```text
channel: flow_muse/pen_point_prediction
method: start / update / stop
update input: pointerId, sceneTransformVersion, x, y, pressure, eventMicros
output: status, transformVersion, predicted[{x,y,pressure,horizonMicros}]
```

若 API 不可用、必须重写 Flutter surface 或无法保留 Scene 坐标/终止语义，立即 Stop，记录原因，不进入 Spike B。

### Spike B：≤1.5d 最小 A/B，仅 Spike A Go 后

具体文件：

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/pen_point_predictor.dart`（最小 Dart 接口/禁用实现）
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/input/ohos_pen_point_predictor.dart`（MethodChannel 调用）
- Create: `FlowMuse-App/ohos/entry/src/main/ets/channels/PenPointPredictionChannel.ets`
- Modify: `FlowMuse-App/ohos/entry/src/main/ets/entryability/EntryAbility.ets`（与现有 `PenColorPickerChannel` 同样注册）
- Modify only if official API requires permission: `FlowMuse-App/ohos/entry/src/main/module.json5`
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/input/pen_point_predictor_test.dart`

预测点仅进 LocalWetInkPainter 的临时 tail，永不进入 final/Scene/协作。非 OHOS、API unavailable、版本不符和任何 channel 错误同步降级为 disabled。

## 6. Pen Kit Go/No-Go 统计规则

5ms 是最小可感知效果量，不是单次样本门槛。对 5 个 AB/BA 配对轮次：

1. 每轮分别算 paired P95 差，5 轮方向必须一致；
2. 5 轮差值中位数 ≥5ms；
3. 以固定 seed 10,000 次 cluster bootstrap（按轮次重采样），95% 单侧下界 >0ms；
4. crash/错误率不增加，Flutter CPU/raster P95 不回退 >5%，final hash 100% 一致；
5. 快速折返的预测 overshoot P95 ≤12 logical px，取消/抬笔后 1 帧内无残影。

任一失败即 No-Go，删除 Spike B 生产接线，仅保留研究报告；不得以调参延长 timebox。

## 7. 文档、命令和验收

Go 时同步：

- `docs/技术设计/前端架构.md` 的 HarmonyOS 输入/MethodChannel 小节；
- `docs/研发记录/research/writing-tip-latency-p2.md` 的设备、raw path、五轮结果、区间、Go/No-Go 和回滚。

```powershell
Push-Location FlowMuse-App
flutter analyze
flutter test test/features/whiteboard/editor_core
flutter test
flutter drive --profile --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_LAYERED_WET_INK=true
Pop-Location
```

P2 completed 仅表示被触发后的候选通过上述门禁；未触发必须写 `not_triggered`。所有候选均有独立 flag 或可删除提交，关闭后回到 P1，无数据迁移。
