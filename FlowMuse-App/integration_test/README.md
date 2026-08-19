# FlowMuse 书写性能 runner

该入口只属于测试 target，不会进入正常导航。没有真机时可以完成编译和普通测试，但不得据此填写性能结论。

## Profile 运行

```powershell
Push-Location FlowMuse-App
flutter devices
$env:FLOWMUSE_PERF_OUTPUT_DIR = (Resolve-Path .).Path + '\build\writing-perf'
flutter drive --profile -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_DEVICE_CLASS=harmony-60hz-mid --dart-define=FLOWMUSE_REFRESH_HZ=60 --dart-define=FLOWMUSE_SCENE_ELEMENTS=100 --dart-define=FLOWMUSE_WRITING_FIXTURE=quick_zigzag --dart-define=FLOWMUSE_RUN_INDEX=1
Pop-Location
```

结果由 host driver 写到 `FLOWMUSE_PERF_OUTPUT_DIR`；未设置时写到 `FlowMuse-App/build/writing-perf/`，命令行会打印绝对路径。

## 平台说明

- HarmonyOS：使用已完成签名配置的真机 deviceId；HAP 构建成功不等于真机性能通过。
- Android：使用 `flutter devices` 返回的真机 deviceId，禁止用模拟器形成性能结论。
- iOS/macOS/Windows/Web：当前只要求代码可编译；它们不能替代路线图规定的 HarmonyOS/Android 真机矩阵。
- 只有结果中的 `measurementEligible=true` 才可能进入性能报告；Debug 结果仅用于排错。

## 固定矩阵与汇总

- `FLOWMUSE_SCENE_ELEMENTS` 只允许 `100/1000/5000`；`5000` 失败必须保留原始失败，不得降级。
- `FLOWMUSE_WRITING_FIXTURE` 使用 `short_horizontal_no_pressure`、`long_curve_pressure`、`quick_zigzag`、`pressure_ramp` 或 `pointer_cancel`。
- 快速书写默认测量 60 秒，`long_curve_pressure` 默认 30 秒；仅排错时可用 `FLOWMUSE_MEASURE_SECONDS` 缩短，缩短结果不能进入基线。
- 每个设备类/场景独立运行 5 轮并填写 `FLOWMUSE_RUN_INDEX=1..5`。raw 会包含目标/实际注入时间、jitter、Git SHA、dirty 状态和 fixture hash。

```powershell
dart run tool/writing_perf/summarize_results.dart --input build/writing-perf --output ../docs/研发记录/research/writing-performance-p0-baseline.md
```

协作 CPU 使用独立 target，输出不得解释为 UI 帧率：

```powershell
flutter drive --profile -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/collaboration_pipeline_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true
```
