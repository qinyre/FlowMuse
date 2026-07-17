# GitLab 质量门禁设计

## 目标

每次 GitLab push、Merge Request 或手动触发时，验证 Flutter 与 Go 质量。

## Runner 约定

| 标签 | Job | 预装工具 |
| --- | --- | --- |
| `linux` | Go 质量 | Go |
| `ohos` | Flutter 质量 | `flutter_ohos`、Node.js |

SDK 由 Runner 预装，流水线不重复下载。

## 流水线

`quality` 阶段并行运行 `flutter analyze --no-fatal-warnings --no-fatal-infos`、`flutter test`、`go test ./...` 与 `go vet ./...`。Flutter Job 使用 Runner 提供的鸿蒙 Flutter 与 Node.js 路径，保证源码中的鸿蒙平台扩展可被解析。

## 安全边界

CI 不输出或归档 `.env`、token、协作密钥、证书与描述文件。流水线不部署服务、不发布应用、不保存构建缓存。

## 验证

在 GitLab Pipeline Editor 中运行 CI Lint；推送分支后确认两个质量 job 均被匹配标签的 Runner 接管并通过。

## 后续项

- Android 构建：配置 Android SDK Runner，并解决标准 Flutter 与鸿蒙平台扩展的编译边界。
- Web、Windows、鸿蒙构建：配置对应 SDK 并逐端验证构建兼容性。
- iOS、macOS 构建：配置 macOS Runner、Xcode 与 CocoaPods。
