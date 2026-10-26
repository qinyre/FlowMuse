# FlowMuse · 跨平台协作笔记

FlowMuse 将手写笔记、PDF 批注和多人白板放在同一个工作空间。一个人可以离线记录和整理，多个人可以扫码进入房间，边写边讨论；需要加工内容时，再使用识别、智能排版或 AI 助手。

客户端使用 Flutter 与内置 Markdraw 编辑器，服务端使用 Go。目标平台为 **HarmonyOS、Android、Web、Windows、macOS 和 iOS**；平台能力与实机验证范围分别记录，不把一端的结果视为六端全部通过。

[在线使用](https://app.flowmuse.cloud/library) · [功能需求](docs/项目说明/项目需求.md) · [文档导航](docs/README.md) · [开发约定](AGENTS.md)

## 能做什么

| 场景 | 当前能力 |
| --- | --- |
| 手写与编辑 | 压感书写、五种笔形、自然介质铅笔/毛笔、整笔擦除、形状、文本、图片、绑定箭头、Frame、撤销与重做 |
| PDF 批注 | 分页导入、纸张与模板、页码导航、页面预览、可见区域图片加载；批注继续使用同一套编辑和协作工具 |
| 实时协作 | 加密房间、链接/二维码入房、实时笔迹、远端光标、在线成员、人数限制与房主移出成员 |
| 协作阅读 | 查看元素创建者、按创建者聚焦、定位成员、持续跟随视角；聚焦和跟随只改变自己的视图 |
| 笔记管理 | 笔记本、标签、搜索、封面、回收站、自动保存、本地备份及 WebDAV 备份 |
| 内容加工 | 手写转文字、公式/形状识别、智能排版审阅、语音转文字；结果成为可以继续编辑的白板元素 |
| AI 助手 | 问答、生成文字、思维导图及排版；支持主动附带选区截图或 PDF 页，修改前先预览确认 |
| 账号与交流 | 邮箱/华为账号、好友、文字私聊和定向协作邀请；社交模块由服务端开关控制 |

Android 和 HarmonyOS 接入各自的原生文件、输入与语音能力。支持的鸿蒙设备及一加/OPPO 手写笔可使用笔身双击切换笔/橡皮；实际能力取决于设备、手写笔及系统授权，Web 保留普通工具栏操作。

## 数据与隐私边界

- 笔记正文和设置优先保存在本机。登录账号不等于所有本地笔记自动上传；基础编辑不需要后端。
- 协作消息、附件和快照使用 AES-GCM 端到端加密，协作服务转发和保存密文。房间链接中的密钥保留在 URL fragment（`#` 后），分享链接仍应仅交给预期成员。
- 私聊正文保存在服务端，**不属于白板的端到端加密通道**。识别与 AI 会把用户选定的内容发送给相应服务，不能把整个后端描述为“永远看不到任何笔记内容”。
- 支持 `.markdraw`、`.excalidraw` / `.json` 导入导出。外部导出会移除协作创建者元数据，内部保存和协作保留。
- 浏览器数据按 origin 隔离；更换域名、协议或清理站点数据前，先导出备份。

## 开发环境

| 部分 | 工具链 |
| --- | --- |
| Flutter 客户端 | Dart `^3.11.1`；仓库 CI 固定 `flutter_ohos 3.41.10-ohos-0.0.1-canary1`，基于 Flutter 3.41.10 |
| HarmonyOS | 上述 OHOS Flutter SDK、DevEco Studio、完整 HarmonyOS SDK 及本机签名配置 |
| Android / 桌面 / Web | 对应平台的 Flutter 构建依赖；Web 使用 Chrome，Android 需要 Android SDK/JDK |
| Go 服务端 | Go 1.25+；版本以 [go.mod](FlowMuse-Server/go.mod) 为准 |
| 本地服务环境 | Docker Engine、Docker Compose v2；PostgreSQL 17、MinIO、Mailpit 由 Compose 启动 |

HarmonyOS 构建必须使用 OHOS Flutter SDK；其余平台也建议使用 CI 同款 SDK，避免工具链与平台插件解析不一致。不要删除 `pubspec.yaml` 中仍在使用的 vendor overrides，也不要用升级全部依赖来解决环境问题。

## 启动客户端

在仓库根目录执行：

```sh
cd FlowMuse-App
flutter pub get --enforce-lockfile
flutter devices
flutter run -d chrome --web-port=8080
```

将 `chrome` 替换为设备 ID 或 `windows` 可启动其他客户端。默认后端为 `https://api.flowmuse.cloud`，分享页面为 `https://app.flowmuse.cloud`；本地编辑可离线进行，网络功能默认访问这组服务。

**调试实时墨迹时，两端需要使用配套构建参数。** 源码中的湿墨分层与实时墨迹 V2 开关默认均为 `false`，裸 `flutter run` 不代表已启用它们：

```sh
flutter run -d chrome --web-port=8080 --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
```

同样的两个参数用于配套 Android/OHOS 构建；是否进入实时模式还取决于服务端协议能力。对外界面显示产品状态，不应把内部协议版本当成功能名称。

## 启动本地后端

在 `FlowMuse-Server` 目录，首次将 `.env.example` 复制为 `.env`，已有配置不要覆盖。然后运行：

```sh
docker compose up -d --build
docker compose ps
```

检查 `http://127.0.0.1:48931/health`，应返回 `{"status":"ok"}`。本地开发默认密码、端口映射及 CORS 不能直接作为公网部署方案，配置项和日常运维见[后端说明](FlowMuse-Server/README.md)。

客户端需同时覆盖 API 与分享地址，例如同机 Web 调试：

```sh
flutter run -d chrome --web-port=8080 --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://127.0.0.1:48931 --dart-define=FLOWMUSE_SHARE_ORIGIN=http://localhost:8080 --dart-define=FLOWMUSE_LAYERED_WET_INK=true --dart-define=FLOWMUSE_LIVE_INK_V2=true
```

服务端配置 `FLOWMUSE_PUBLIC_APP_URL=http://localhost:8080`，并让 `FLOWMUSE_ALLOWED_ORIGINS` 包含浏览器实际 origin。真机联调时，将 loopback 地址换成设备可访问的电脑局域网地址；HTTPS 页面必须连接 HTTPS API。客户端配置优先级为 `--dart-define` → `assets/config/app.env` → 内置默认值，修改编译参数后必须重新构建。

## 验证改动

客户端，在 `FlowMuse-App` 下：

```sh
flutter analyze --no-pub
flutter test --no-pub
```

服务端，在 `FlowMuse-Server` 下：

```sh
go test ./...
go vet ./...
```

数据库集成测试需要独立、名称以 `_test` 结尾的数据库，通过 `FLOWMUSE_SOCIAL_TEST_DATABASE_URL` 指定；未配置时会明确跳过，不能当作迁移已验证。不要使用生产数据库。

CI 包括[基础质量检查](.github/workflows/quality.yml)、[智能排版矩阵](.github/workflows/smart-layout-v3-ci.yml)与[平台构建矩阵](.github/workflows/smart-layout-v3-platform.yml)。书写性能和鸿蒙能力仍需真实设备验证，参见[性能测试说明](FlowMuse-App/integration_test/README.md)。发布构建、Web 资源验证和图标维护见[客户端说明](FlowMuse-App/README.md)。

## 仓库导航

```text
FlowMuse-App/       Flutter 客户端、编辑器、平台适配与测试
FlowMuse-Server/    Go 账户、协作、社交、存储和识别服务
scripts/           图标生成及智能排版辅助脚本
docs/              需求、设计、研发记录与演示工程
.agent/            架构地图、决策与开发约定
AGENTS.md          编码助手的项目入口与验证要求
```

- [架构约束](docs/项目说明/架构约束.md)：Excalidraw 格式、归属、加密与平台边界。
- [技术设计](docs/技术设计/前端架构.md)：客户端分层与数据流；[接口](docs/技术设计/接口设计.md)和[数据模型](docs/技术设计/数据模型.md)。
- [决赛优化计划](docs/研发记录/plans/2026-10-24-finals-product-optimization-plan.md)：产品演进与验收方向。
- [演示视频工程](docs/参赛文档/复赛演示视频/README.md)：脚本、重建方法与选定成片。

`build/`、本机签名、密钥和运行日志不入库；编译缓存不作为源码清理对象。周报、验收材料和大部分参赛过程材料本地保留，分类见[文档导航](docs/README.md)。

## 团队

陈宏宇、任逸青、李天宇 · 武汉大学 2024 级软件工程实训项目
