# FlowMuse 书写性能 runner

该入口只属于测试 target，不会进入正常导航。没有真机时可以完成编译和普通测试，但不得据此填写性能结论。

## Profile 运行

```powershell
Push-Location FlowMuse-App
flutter devices
$env:FLOWMUSE_PERF_OUTPUT_DIR = (Resolve-Path .).Path + '\build\writing-perf'
flutter drive --profile --keep-app-running -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_PHYSICAL_DEVICE=true --dart-define=FLOWMUSE_DEVICE_ID=<deviceId> --dart-define=FLOWMUSE_DEVICE_CLASS=harmony-60hz-mid --dart-define=FLOWMUSE_REFRESH_HZ=60 --dart-define=FLOWMUSE_SCENE_ELEMENTS=100 --dart-define=FLOWMUSE_WRITING_FIXTURE=quick_zigzag --dart-define=FLOWMUSE_RUN_INDEX=1 --dart-define=FLOWMUSE_LAYERED_WET_INK=false
Pop-Location
```

结果由 host driver 写到 `FLOWMUSE_PERF_OUTPUT_DIR`；未设置时写到 `FlowMuse-App/build/writing-perf/`，命令行会打印绝对路径。

**数据保护：** 本项目当前的测试 target 与正式应用共用包名。`flutter drive` 默认的结束清理会卸载 Android 应用并清除本地数据，必须使用 `--keep-app-running`，且实机测试前先备份已有笔记。已有个人数据的设备优先采用下面的保留安装与直接连接流程，安装失败时停止，不使用卸载重试。

```powershell
# 先按上方相同的 target / dart-define 参数运行 flutter build apk --profile。
adb -s <deviceId> install -r -t build/app/outputs/flutter-apk/app-profile.apk
adb -s <deviceId> shell am start -n com.example.flowmuse/com.example.flowmuse.MainActivity --ez enable-dart-profiling true
# 立即读取本次进程日志中的 VM service URL，保留其中的端口和路径。
adb -s <deviceId> logcat -d -s flutter:I
adb -s <deviceId> forward tcp:<hostPort> tcp:<devicePort>
$env:VM_SERVICE_URL = 'http://127.0.0.1:<hostPort>/<vmPath>/'
dart run test_driver/whiteboard_writing_perf_driver.dart
```

直接运行 driver 只连接已启动的应用，结束时不卸载应用。完整矩阵允许两小时；收到测试失败响应时也保存已完成场景的报告，进程退出或 VM 断连则无法保证回收。每个场景另输出不含笔迹正文的计数摘要。不要对保存了个人内容的设备执行 `adb uninstall`、`pm clear` 或测试工具的默认卸载清理。

从 integration target 切回正常 release 时使用 `flutter build apk --release --target=lib/main.dart`，允许重新生成发布模式插件注册文件；若沿用测试阶段的 `--no-pub`，可能残留 `IntegrationTestPlugin` 引用而构建失败。

## 平台说明

- HarmonyOS：使用已完成签名配置的真机 deviceId；HAP 构建成功不等于真机性能通过。
- Android：使用 `flutter devices` 返回的真机 deviceId，禁止用模拟器形成性能结论。
- iOS/macOS/Windows/Web：当前只要求代码可编译；它们不能替代路线图规定的 HarmonyOS/Android 真机矩阵。
- 只有结果中的 `measurementEligible=true` 才可能进入性能报告；Debug 结果仅用于排错。

## 固定矩阵与汇总

- `FLOWMUSE_SCENE_ELEMENTS` 只允许 `100/1000/5000`；`5000` 失败必须保留原始失败，不得降级。
- 功能 fixture 包含短线、压力坡道和取消；正式性能 fixture 为 `quick_zigzag`（60 秒）、`long_curve_pressure`（重复约 1 秒笔画，30 秒）和 `continuous_curve_30s`（单笔持续 30 秒，120Hz，3601 个真实样本）。前两项的冻结内容和 hash 保持不变。
- runner 按 fixture 时长计算固定笔画数；慢机允许超时完成，不减少工作量。`measuredMicros` 记录实际耗时。预热用快速短笔，正式回放前必须断言命中画布并生成笔迹，防止属性面板遮挡造成零输入假通过。
- `FLOWMUSE_BRUSH=all` 遍历五笔，也可指定枚举名；`FLOWMUSE_FULL_EDITOR=true` 保留工具栏/属性面板/缩放控件，但仍是 Editor 宿主，不代表含保存和协作的 WhiteboardPage。
- `FLOWMUSE_COMPARE_LAYERED=true` 在同一个构建内对照 false/true；`FLOWMUSE_PERF_REPEATS=5` 按轮次交替先后顺序。多场景报告为 schema 2 容器，汇总器按笔刷、渲染版本和界面模式分别统计，旧单场景报告仍可读取。
- 每个设备类/场景独立运行 5 轮并填写 `FLOWMUSE_RUN_INDEX=1..5`。raw 会包含目标/实际注入时间、jitter、Git SHA、dirty 状态和 fixture hash。
- `FLOWMUSE_PHYSICAL_DEVICE=true` 与 `FLOWMUSE_DEVICE_ID` 必须由操作者按 `flutter devices` 的真机结果填写；模拟器或缺失身份的结果会被汇总器拒绝。每个场景分别运行 `FLOWMUSE_LAYERED_WET_INK=false/true`，不得混合汇总。
- 60Hz 和 ≥100Hz 目标由 runner 按冻结表生成；其他刷新率必须在运行前用 `FLOWMUSE_EVENT_TO_PAINT_TARGET_MICROS` 显式给出已批准目标。

```powershell
dart run tool/writing_perf/summarize_results.dart --input build/writing-perf --output ../docs/研发记录/research/writing-performance-p0-baseline.md
```

协作 CPU 使用独立 target，输出不得解释为 UI 帧率：

```powershell
flutter drive --profile --keep-app-running -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/collaboration_pipeline_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true
```
