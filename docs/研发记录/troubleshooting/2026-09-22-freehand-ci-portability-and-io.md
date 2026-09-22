# 自由绘画合并后的 CI：回放精度与异步收尾

2026-09-22，合并提交 `f85a2b3` 的 [Quality 运行](https://github.com/qinyre/FlowMuse/actions/runs/35680212533) 中，Flutter 分析与 Go 检查通过，Flutter 测试出现三个失败用例。

## 原因

1. `continuous_curve_30s` 使用未量化的三角函数结果。冻结的 Windows hash 为 `0ceeac0e...`，Linux 实际为 `97c1e051...`；此前 Android 也已记录过差异。已有 v2 解决了跨平台精度问题，但单元测试仍将 v1 的 Windows hash 当成所有平台的精确基准。
2. PDF 页面测试仅等待约 200ms。CI 中标题已载入，但恢复 PDF 页边界的异步步骤还未完成，`contentBounds` 因而仍为空。测试失败后过早销毁页面又产生了后续异常。
3. 识别工作流的内容断言已通过，但退出补存中的 SQLite 笔记更新还在执行，测试便结束，遗留 sqflite 的 10 秒锁等待诊断定时器。

## 修复范围

- v2 等可移植 fixture 继续精确匹配冻结 hash。v1 按 v2 对照检查逐点坐标、压力、时间和阶段，浮点容差为百万分之一，并继续检查样本数。旧数据与旧 hash 保留；设备性能入口和报告汇总器仍要求精确 hash，不放宽性能验收门槛。
- 页面测试等待 PDF 边界与图片解码就绪后再断言。测试用 SQLite repository 继承真实实现，仅记录未完成的笔记更新；公共等待辅助方法持续推动 Flutter 微任务和真实 I/O，直到这些更新完成，并保留超时失败。
- 未修改生产书写、渲染、保存实现或 CI 工作流，未新增跳过项，未安装到设备。

## 本地验证

- `flutter analyze`：无问题。
- 两个相关测试文件：15 项通过，1 项既有协作撤销问题跳过。
- `flutter test --reporter expanded`：1679 项通过，5 项既有跳过。
- 日志：应用目录下 `build/freehand-ci-targeted.log`、`build/freehand-ci-analyze.log`、`build/freehand-ci-full-tests.log`。
