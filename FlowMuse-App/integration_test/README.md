# FlowMuse 书写性能 runner

该入口只属于测试 target，不会进入正常导航。没有真机时可以完成编译和普通测试，但不得据此填写性能结论。

## Profile 运行

```powershell
Push-Location FlowMuse-App
flutter devices
$env:FLOWMUSE_PERF_OUTPUT_DIR = (Resolve-Path .).Path + '\build\writing-perf'
flutter drive --profile -d <deviceId> --driver=test_driver/whiteboard_writing_perf_driver.dart --target=integration_test/whiteboard_writing_perf_test.dart --dart-define=FLOWMUSE_PERF_TEST=true
Pop-Location
```

结果由 host driver 写到 `FLOWMUSE_PERF_OUTPUT_DIR`；未设置时写到 `FlowMuse-App/build/writing-perf/`，命令行会打印绝对路径。

## 平台说明

- HarmonyOS：使用已完成签名配置的真机 deviceId；HAP 构建成功不等于真机性能通过。
- Android：使用 `flutter devices` 返回的真机 deviceId，禁止用模拟器形成性能结论。
- iOS/macOS/Windows/Web：当前只要求代码可编译；它们不能替代路线图规定的 HarmonyOS/Android 真机矩阵。
- 只有结果中的 `measurementEligible=true` 才可能进入性能报告；Debug 结果仅用于排错。
