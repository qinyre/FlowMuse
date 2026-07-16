# GitLab 六端持续集成设计

## 目标

每次 GitLab push、Merge Request 或手动触发时，验证 Flutter 与 Go 质量，并构建 Android、iOS、Windows、macOS、Web、鸿蒙六端。

## Runner 约定

| 标签 | Job | 预装工具 |
| --- | --- | --- |
| `linux` | Flutter 质量、Go 质量、Android、Web | Flutter、Android SDK、Go |
| `macos` | iOS、macOS | Flutter、Xcode、CocoaPods |
| `windows` | Windows | Flutter、Visual Studio C++ 桌面开发工作负载 |
| `ohos` | 鸿蒙 | `flutter_ohos`、DevEco SDK、Node.js、ohpm |

Runner 缺失时 job 必须保持 pending，不能使用 `allow_failure` 掩盖。SDK 由 Runner 预装，流水线不重复下载。

## 流水线

`quality` 阶段并行运行 `flutter analyze`、`flutter test`、`go test ./...` 和 `go vet ./...`；通过后 `build` 阶段并行构建六端。各 build job 产物保存七天：Android APK、Web bundle、无签名 iOS app、macOS Release、Windows Release、鸿蒙 `entry-default-signed.hap`。

iOS 仅执行 `flutter build ios --release --no-codesign`。发布 IPA、证书、描述文件与商店上传不属于当前流水线；未来应使用受保护、手动触发的发布 job 和 GitLab 受保护变量。

## 安全边界

CI 不输出或归档 `.env`、token、协作密钥、证书与描述文件。流水线不部署服务、不发布应用、不保存构建缓存。

## 验证

在 GitLab Pipeline Editor 中运行 CI Lint；推送分支后确认 2 个质量 job 与 6 个构建 job 分别被匹配标签的 Runner 接管，并检查八个预期 job 的 artifact。

## 后续项

- 受保护 tag 的手动签名与发布。
- GitLab Dependency Scanning 与 Secret Detection 的校准接入。
- 当成本或耗时成为问题后，再使用 `rules:changes` 做变更感知构建。
