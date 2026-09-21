# FlowMuse 书写性能 runner

该入口只属于测试 target，不会进入正常导航。没有真机时可以完成编译和普通测试，但不得据此填写性能结论。

## Profile 运行

```powershell
Push-Location FlowMuse-App
flutter devices
$env:FLOWMUSE_PERF_OUTPUT_DIR = (Resolve-Path .).Path + '\build\writing-perf'
flutter drive --profile --keep-app-running -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true --dart-define=FLOWMUSE_PHYSICAL_DEVICE=true --dart-define=FLOWMUSE_DEVICE_ID=<deviceId> --dart-define=FLOWMUSE_DEVICE_CLASS=harmony-60hz-mid --dart-define=FLOWMUSE_SCENE_ELEMENTS=100 --dart-define=FLOWMUSE_WRITING_FIXTURE=quick_zigzag --dart-define=FLOWMUSE_RUN_INDEX=1 --dart-define=FLOWMUSE_LAYERED_WET_INK=false
Pop-Location
```

结果由 host driver 写到 `FLOWMUSE_PERF_OUTPUT_DIR`；未设置时写到 `FlowMuse-App/build/writing-perf/`，命令行会打印绝对路径。

**数据保护：** 本项目当前的测试 target 与正式应用共用包名。`flutter drive` 默认的结束清理会卸载 Android 应用并清除本地数据，必须使用 `--keep-app-running`，且实机测试前先备份已有笔记。已有个人数据的设备优先采用下面的保留安装与直接连接流程，安装失败时停止，不使用卸载重试。

```powershell
# 先按上方相同的 target / dart-define 参数运行 flutter build apk --profile。
adb -s <deviceId> install -r -t build/app/outputs/flutter-apk/app-profile.apk
# 在启动前持续落盘，避免测试输出刷掉 VM service 启动地址。
$capture = Start-Process adb -ArgumentList '-s','<deviceId>','logcat','-T','1','-v','brief','-s','flutter:I' -WindowStyle Hidden -RedirectStandardOutput "$PWD/build/writing-device.log" -RedirectStandardError "$PWD/build/writing-device-error.log" -PassThru
adb -s <deviceId> shell am start -n com.example.flowmuse/com.example.flowmuse.MainActivity --ez enable-dart-profiling true
# 核对日志 PID 与本次进程一致，读取 VM service URL，保留端口和路径。
adb -s <deviceId> shell pidof com.example.flowmuse
Select-String -Path build/writing-device.log -Pattern 'Dart VM service'
adb -s <deviceId> forward tcp:<hostPort> tcp:<devicePort>
$env:VM_SERVICE_URL = 'http://127.0.0.1:<hostPort>/<vmPath>/'
dart run test_driver/whiteboard_writing_perf_driver.dart
Stop-Process -Id $capture.Id # 只结束本次主机日志采集器
```

直接运行 driver 只连接已启动的应用，结束时不卸载应用。完整矩阵允许两小时；收到测试失败响应时也保存已完成场景的报告，进程退出或 VM 断连则无法保证回收。每个场景另输出不含笔迹正文的计数摘要。不要对保存了个人内容的设备执行 `adb uninstall`、`pm clear` 或测试工具的默认卸载清理。

从 integration target 切回正常 release 时使用 `flutter build apk --release --target=lib/main.dart`，允许重新生成发布模式插件注册文件；若沿用测试阶段的 `--no-pub`，可能残留 `IntegrationTestPlugin` 引用而构建失败。

## 平台说明

- HarmonyOS：使用已完成签名配置的真机 deviceId；HAP 构建成功不等于真机性能通过。
- Android：使用 `flutter devices` 返回的真机 deviceId，禁止用模拟器形成性能结论。
- iOS/macOS/Windows/Web：当前只要求代码可编译；它们不能替代路线图规定的 HarmonyOS/Android 真机矩阵。
- 只有结果中的 `measurementEligible=true` 才可能进入性能报告；Debug 结果仅用于排错。
- 使用 `fullyLive` 绘帧、无测试指针十字的合成设备事件，并与正常启动一样初始化 `PencilShader`。这仍不是物理触控笔延迟测量。报告记录绘帧策略、输入来源和 shader 状态，汇总时不混用这些条件不同的场景。

## 先校准，再跑矩阵

同一 target 增加 `--dart-define=FLOWMUSE_REPLAY_CALIBRATION=true` 可分别运行 30 秒纯计时和空白 Listener 输入分发。两组均保留所有目标/实际注入时间、逐次分发耗时和原始 hash；`mode=replay_calibration_non_ui` 不进入正式画布统计。校准超门槛时保留原因，不放宽 P95 4ms / max 16ms，也不继续堆积同类无效矩阵。

实际刷新率以运行中引擎报告为准，不能用设备型号或系统设置名代替。例如本次 OPD2404 曾切到 50Hz，不能套用 120Hz 目标。Git dirty 的诊断构建保留原始数据但不计入正式五轮。

## 固定矩阵与汇总

- `FLOWMUSE_SCENE_ELEMENTS` 只允许 `100/1000/5000`；`5000` 失败必须保留原始失败，不得降级。
- 功能 fixture 包含短线、压力坡道和取消；正式性能 fixture 为 `quick_zigzag`（60 秒）、`long_curve_pressure`（重复约 1 秒笔画，30 秒）和 `continuous_curve_30s`（单笔持续 30 秒，120Hz，3601 个真实样本）。前两项的冻结内容和 hash 保持不变。
- 新的跨架构长笔使用 `continuous_curve_30s_v2`：只在 fixture 生成阶段将坐标与压力固定到六位小数，避免 ARM/x64 三角函数末位差异。v1 内容和 hash 不改写。设备端先核对冻结 hash，失败即停止；不能拿不匹配的数据继续验收。
- runner 按 fixture 时长计算固定笔画数；慢机允许超时完成，不减少工作量。`measuredMicros` 记录实际耗时。预热用快速短笔，正式回放前必须断言命中画布并生成笔迹，防止属性面板遮挡造成零输入假通过。
- `FLOWMUSE_BRUSH=all` 遍历五笔，也可指定枚举名；`FLOWMUSE_FULL_EDITOR=true` 保留工具栏/属性面板/缩放控件，但仍是 Editor 宿主，不代表含保存和协作的 WhiteboardPage。
- `FLOWMUSE_COMPARE_LAYERED=true` 在同一个构建内对照 false/true；`FLOWMUSE_PERF_REPEATS=5` 按轮次交替先后顺序。多场景报告为 schema 2 容器，汇总器按笔刷、渲染版本和界面模式分别统计，旧单场景报告仍可读取。
- 每个设备类/场景独立运行 5 轮并填写 `FLOWMUSE_RUN_INDEX=1..5`。raw 会包含目标/实际注入时间、jitter、Git SHA、dirty 状态和 fixture hash。
- `FLOWMUSE_PHYSICAL_DEVICE=true` 与 `FLOWMUSE_DEVICE_ID` 必须由操作者按 `flutter devices` 的真机结果填写；模拟器或缺失身份的结果会被汇总器拒绝。每个场景分别运行 `FLOWMUSE_LAYERED_WET_INK=false/true`，不得混合汇总。
- 55–65Hz 和 100–165Hz 目标由 runner 按冻结表生成；其他刷新率不进入当前正式报告，新增目标须另行冻结，不能靠修改设备标签绕过。

```powershell
dart run tool/writing_perf/summarize_results.dart --phase p0 --input build/writing-perf --output ../docs/研发记录/research/writing-performance-p0-baseline.md
```

完整页面功能回归（真实 SQLite；PDF 栅格、识别服务和协作传输的模拟边界见测试注释）：

```powershell
flutter test test/features/whiteboard/views/whiteboard_writing_workflow_test.dart
flutter test test/features/whiteboard/views/whiteboard_writing_workflow_test.dart --dart-define=FLOWMUSE_LAYERED_WET_INK=true
```

该文件有一个显式跳过的既有协作撤销缺陷，不能把其他场景通过解释成这个问题已解决。可用 `--run-skipped --plain-name known_remote_undo_preserves_new_elements` 单独复现；第二轮验证记录说明其影响和后续验收条件。

协作 CPU 使用独立 target，输出不得解释为 UI 帧率：

```powershell
flutter drive --profile --keep-app-running -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/collaboration_pipeline_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true
```
