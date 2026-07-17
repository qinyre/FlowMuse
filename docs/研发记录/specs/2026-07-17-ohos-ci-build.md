# 鸿蒙 HAP CI 构建设计

## 目标

在 `feature/ci-build` 中仅恢复鸿蒙 Debug HAP 构建，不恢复其他平台构建。

## 根因

Windows GitLab Runner 作为 `SYSTEM` 服务运行，不能继承开发用户 `LTY` 的 PATH。此前 `analyze_flutter` 通过 Runner 环境变量 `FLUTTER_OHOS_HOME`、`NODE_HOME` 和 Job 内 PATH 注入成功找到鸿蒙 Flutter 与 npm；原有构建 Job 未执行这一步，因此报 `flutter` 未找到。

## 方案

- 新增 `build_ohos`，标签为 `ohos`。
- 在 Job 内复用分析 Job 的 PATH 注入，再执行 `flutter pub get` 与 `flutter build hap --debug`。
- 归档 `FlowMuse-App/build/ohos/hap/entry-default-signed.hap` 七天。
- Android、Web、Windows、iOS、macOS 构建继续不启用。

## 验证

- 新流水线保留 `analyze_flutter`、`test_server` 与 `build_ohos`。
- `build_ohos` 成功生成并归档 HAP；失败时以 Job 日志定位 DevEco SDK、ohpm 或签名环境，不能掩盖失败。
