# FlowMuse P0 书写与协作性能基线

> 建档日期：2026-08-20  
> 当前状态：`deferred_device`  
> 适用 schema：writing performance v1 / fixture v1

## 1. 当前结论

当前没有可用真机，因此尚无可进入门禁的 Profile 原始数据。本文只冻结测量口径、目标和证据位置，不填写合成 P95，不用 Windows、Debug、算法回放或内存 transport 结果代替真机 UI 结论。

- event-to-paint proxy：`not_measured`
- 物理 stylus-to-photon：`not_measured`
- 2/5 人协作 CPU 完整 100/1000 次 Profile：`deferred_device`
- P1-3/G1/G2：`not_evaluated`
- P2：`not_evaluated`

## 2. 冻结目标 v1

| 设备类 | event-to-paint P95 | 物理 stylus-to-photon P95 |
| --- | ---: | ---: |
| 实测约 60Hz | ≤33ms | ≤50ms |
| 实测帧间隔 <10ms | ≤实测刷新周期 | ≤35ms |
| 其他刷新率 | 首次运行前登记并签名 | 首次运行前登记并签名 |

统计固定为 nearest-rank P95；每个场景预热 5 秒、测量 60 秒、独立 5 轮；单轮 accepted 少于 100 无效；`paired/(accepted-terminalBeforePreview) >= 99.5%`；五轮 `P95` 的 `(max-min)/median <= 10%`。物理列只能来自高速录像或光电测量。

## 3. 固定证据

- 书写 recording：`integration_test/fixtures/writing_recordings.dart`，schema v1，固定 seed 101/202/303/404/505。
- 场景：`integration_test/fixtures/scene_fixtures.dart`，schema v1，固定 seed 1701，规模 100/1000/5000。
- 协作：2/5 个真实 `CollaborationRepository`，100 次预热、1000 次测量；结果栏固定标记 `collaboration_cpu_non_ui`。
- raw 默认目录：`FlowMuse-App/build/writing-perf/`；每次运行必须保留绝对 raw path、Git SHA、dirty 状态、设备/系统、刷新率、构建模式、flags 和 fixture hash。
- 汇总命令：

```powershell
Push-Location FlowMuse-App
dart run tool/writing_perf/summarize_results.dart --input build/writing-perf --output ../docs/研发记录/research/writing-performance-p0-baseline.md
Pop-Location
```

首次真机运行前，由负责人和复核人在追加的新版本中登记 Git SHA、设备分类、fixture hash 与签名；不得覆盖本版本或回填阈值。

## 4. 已完成的非真机验证

- 活动预览 probe 的 high-water、跨笔、重复 paint、terminal-before-preview 与真实 painter 接线测试通过。
- 报告 schema round-trip、未知版本拒绝、FrameTiming frameNumber 字段测试通过。
- 5 类 writing recording 和 100/1000/5000 元素场景的确定性、样本数、序列化与编辑器 codec 加载测试通过。
- 2/5 人缩短迭代回归经过真实 JSON、AES-GCM、memory transport、decrypt、reconcile，最终 Scene hash 收敛。
- 汇总器会拒绝非 Profile、未知 schema、accepted <100、coverage <99.5% 或无 painted 样本的轮次。

这些结果证明测量设施可执行，不构成真机性能通过。
