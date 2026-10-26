# 项目冗余清理与开发入口整理

## Context

从 `origin/main` 的 `9d7f93a5`（已合并 PDF 本地书写优化）创建 `chore/project-cleanup`。本轮整理仓库内的源码、依赖、原生声明与开发文档，不部署、不清理用户数据或构建缓存。

## 清理判据

- 先检查全部 Git 跟踪源码、测试、工具、条件导入、公开导出及原生配置；文本只出现一次不等于无用，例如 Go 的 `Unwrap` 由标准接口调用，平台插件由生成器注册。
- 移除必须同时满足：当前运行入口无调用、测试和工具无调用、没有仍需维护的兼容或外部接口契约。
- 不以体积、文件名或“旧版本”为删除依据。保留历史笔刷、旧协作兼容、数据库迁移、导出净化、第三方许可证、有效测试与验收材料。
- Git 保存源码历史，不另建备份副本；不删除 `build/` 中仍用于编译的中间产物。

## 实现范围

1. 清理不再使用的笔记菜单组件和辅助方法；保留当前 `NoteCard` 菜单及移动/标签对话框。
2. 清理没有调用方的旧同步笔迹回放包装；保留现有录制、输入模型和 `integration_test` 的定时性能回放。
3. 移除没有 Dart 或传递调用方的 `flutter_colorpicker`、`equatable`、`shared_preferences` 与 `shared_preferences_ohos`。同步 OHOS 直接依赖和锁文件，仅删除已经断开依赖的 preferences fork。
4. 清理后端无调用的 `requestHeader` 和 `looksLikeMath`；不改协作中转、鉴权或识别解析行为。
5. 停止追踪已被忽略规则覆盖、由 Flutter 自动生成的平台插件注册文件，保留本地生成结果。
6. 重写根 README 和 App README：说明当前协作笔记定位、能力与边界、真实工具链、开发启动、配套实时墨迹开关及构建验证入口；不把历史发布结果当作当前平台验证。
7. 补充 AGENTS 的清理、性能与发布约束；纠正 `.agent/` 中生成文件、HTTP 适配路径及安全边界的过期说明。

## 验证方案

- 全仓引用复核；依赖离线解析与锁文件检查，确认没有无关版本升级。
- Flutter analyze、相关资料库/输入/存储测试及全量 Flutter 测试。
- Go 全量测试与 vet；数据库集成测试若未配置独立测试库，明确记录跳过。
- Web release 构建及已有 Web 启动/预压缩自检。
- 原生插件依赖变化须尝试 HAP 构建；缺失 SDK 时记录具体阻塞，不把静态检查视为鸿蒙实机验证。
- Android 构建验证插件移除后的注册与编译；不覆盖安装设备，不重启生产服务。

## 结果

### 已清理

- 删除无调用的 `NoteActionsMenu` 与其私有枚举；`NoteCard` 标题旁菜单、移动笔记本/选择标签对话框保持现有实现。
- 删除 `LibraryIndex.tagsOfNote`、`temporaryCacheSizeBytes`、`StrokeReplayRunner` 及其专属 `StrokeReplayMetricsProducer`。当前定时回放入口仍为 `integration_test/`；旧计划中的 runner 说明保留为历史记录，不作为现行调用证据。
- 后端仅删除 `requestHeader` 和 `looksLikeMath`。`Unwrap` 为错误链接口，保留；协作、识别输入解析与安全检查均不改。
- 移除 4 个直接依赖，锁文件净减 10 个包，保留包的完整条目逐项一致；同步移除 OHOS 原生依赖及 preferences fork 的 59 个跟踪文件。安全存储插件仍保留，其 Android `encryptedSharedPreferences` 不属于本次移除的 Dart 插件。
- 7 个自动生成的桌面插件注册/依赖列表停止追踪，磁盘上的生成结果保留。`flutter pub get --offline` 已重新生成插件清单，移除项不再注册。

### 保留理由

| 项目 | 原因 |
| --- | --- |
| Markdraw 公开导出、录制器及定时回放 | 属于现有 API 或测试能力，不能仅按入口中的文本引用数量删除 |
| 经典/V2 笔刷、协作降级、旧格式兼容与迁移 | 仍服务于历史笔记及不同版本客户端 |
| `code_assets`、`path_provider*`、`flutter_math_fork` | 仍在解析依赖图并参与应用构建 |
| `third_party/engine.io` | 当前 `go.mod` replace 使用，承载 WebSocket 批量帧丢包修复 |
| 独立 `layoutrecognitionv3` 与旧识别链 | 注册入口不同，并非仅因名称类似就重复 |
| 性能夹具、Golden/像素矩阵、第三方许可证、历史研发材料 | 属于可复核证据或分发义务 |
| `build/`、`.pub-cache`、Gradle/Hvigor 缓存 | 不作为本次源码冗余清理目标，不新建备份副本 |

### 已验证

- 全部 908 个应用 Dart 源码/测试/工具的本仓库 import、export 和条件 URI 存在性检查通过；不把注释中的示例当成真实依赖。
- Flutter analyze 无问题；相关测试 **83 通过**；全量测试 **2059 通过、5 个既有跳过**。
- `go test -count=1 ./...`、`go vet ./...` 通过。未配置独立测试数据库，PostgreSQL 专项集成场景跳过；不能据此宣称真实迁移通过。
- Web 启动 Node 自检 **2 通过**，预压缩 Python 自检 **1 通过**；已改 Markdown 的本地链接与代码围栏检查通过。
- 完整日志位于本地忽略目录 `FlowMuse-App/build/project-cleanup/`。

平台构建和浏览器检查结果将在完成后补充；当前未部署任何服务或安装设备。
