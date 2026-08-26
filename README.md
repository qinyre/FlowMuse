# FlowMuse（流形白板）

FlowMuse 是一款面向课堂笔记、会议协作和灵感记录的跨平台协同白板应用，由武汉大学 2024 级软件工程专业实训团队"队名还没想好"开发。

项目基于 Flutter 与自研 Markdraw 白板内核，支持 Android、HarmonyOS、Web、Windows、macOS 和 iOS；后端使用 Go、Socket.IO、PostgreSQL 与 MinIO。

当前主线已包含协作元素归属显示与按创建者聚焦功能；鸿蒙真机 Profile/GPU 验收仍需在真实设备上完成。

## 核心能力

- 自由书写、压感笔迹、形状、文本、橡皮擦、分页与撤销重做
- 笔记本、标签、搜索、封面与本地持久化
- 多端实时协作、在线成员感知与 AES-GCM 端到端加密
- 协作元素归属显示与按创建者聚焦（非破坏性视图过滤，外部导出不携带创建者信息）
- PDF 分页导入以及 `.markdraw`、`.excalidraw` 文件导入导出
- 手写识别、智能排版和跨端语音转文字
- 可配置 OpenAI 兼容模型的 AI 助手，支持问答、文本生成与思维导图
- AI 助手可附带框选截图（拖框任取画布矩形）/ PDF 页，理解手写与视觉内容
- HarmonyOS 原生文件、网络、PDF、语音识别与手写笔能力适配

## 功能依赖说明

| 功能 | 是否需要服务端 | 说明 |
|---|---:|---|
| 本地白板与笔记管理 | 否 | 可离线书写、保存、搜索和导入导出 |
| 实时协作与账号 | 是 | 需要连接 `FlowMuse-Server` |
| 手写识别与智能排版 | 是 | 服务端还需配置 MyScript/OpenAI 兼容识别服务 |
| AI 助手 | 否 | 由用户在客户端自行配置 OpenAI 兼容模型，直接连接模型服务 |
| 语音转文字 | 否 | 使用 Android、HarmonyOS 或 Web 提供的系统语音识别能力 |

## 平台与验证矩阵

| 平台 | 启动方式 | 重点验证 |
|---|---|---|
| Web | `flutter run -d chrome` | 协作、AI、语音转文字（浏览器支持时） |
| Windows | `flutter run -d windows` | 协作、桌面输入、文件导入导出 |
| Android / iOS / macOS | 标准 Flutter SDK | 书写、协作和平台文件能力 |
| HarmonyOS | `flutter_ohos` + DevEco Studio | 手写笔、原生通道、PDF、语音和真机性能 |

## 项目结构

```text
.
├── FlowMuse-App/       # Flutter 客户端与 HarmonyOS 原生适配
├── FlowMuse-Server/    # Go 协作、账户、文件与识别服务
├── docs/               # 需求、设计与研发记录（验收/周报为本地材料）
├── .agent/             # 项目架构决策与 Agent 协作知识库
├── .github/workflows/  # GitHub Actions 质量门禁
├── AGENTS.md           # 开发与跨端约束
└── .gitlab-ci.yml      # GitLab Runner 质量门禁（如启用）
```

## 快速开始

### 1. 运行客户端

环境要求：

| 目标平台 | 已验证工具链 |
|---|---|
| Android / Web / Windows / macOS / iOS | Flutter `3.41.10`、Dart `3.11.1` |
| HarmonyOS | `flutter_ohos 3.41.10-ohos-0.0.1-canary1`、Dart `3.11.1`、DevEco Studio |

建议使用以上版本复现构建环境。普通平台可使用标准 Flutter SDK；HarmonyOS 必须使用 `flutter_ohos`，不能用标准 Flutter SDK 构建 HAP。

```bash
cd FlowMuse-App
flutter pub get
flutter devices
flutter run -d <device-id>
```

Web 端可直接运行：

```bash
flutter run -d chrome
```

客户端默认读取 `FlowMuse-App/assets/config/app.env`。连接自建服务时可在启动命令中覆盖地址：

```bash
flutter run -d <device-id> \
  --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://<server-ip>:48931 \
  --dart-define=FLOWMUSE_SHARE_ORIGIN=http://<web-origin>
```

真机不能通过 `127.0.0.1` 访问电脑上的服务，请使用电脑局域网 IP 或可访问的公网地址。

### 2. 运行服务端

环境要求：Docker 与 Docker Compose。Compose 会同时启动 PostgreSQL、MinIO、Mailpit 和 FlowMuse 服务。

```bash
cd FlowMuse-Server
cp .env.example .env
docker compose up --build
```

Windows PowerShell 使用：

```powershell
Copy-Item .env.example .env
docker compose up --build
```

服务默认监听 `http://127.0.0.1:48931`，可通过以下地址确认状态：

```text
http://127.0.0.1:48931/health
```

如需手写识别或服务端智能排版，在 `FlowMuse-Server/.env` 中配置对应的 MyScript/OpenAI 兼容服务。密钥不得提交到仓库。生产环境还应把 `FLOWMUSE_ALLOWED_ORIGINS` 设置为实际 Web 域名，而不是 `*`。

### 3. Web/桌面协作冒烟测试

1. 启动服务端并确认 `/health` 可访问。
2. 在 Chrome 和 Windows 客户端使用同一服务地址启动。
3. 一端创建房间，另一端通过完整房间链接加入。
4. 两端分别创建笔迹、文本和形状，确认场景、光标和成员状态同步。
5. 点击协作者头像或元素属性面板中的创建者入口，确认聚焦只在本机变淡且不改变 z 序。
6. 导出 `.markdraw`、`.excalidraw` 或 `.json`，确认外部文件不含 `collaborationOwner`。

## AI 助手配置

客户端进入“设置 → 实验室”后填写：

- OpenAI 兼容 Base URL
- API Key
- 模型名称

可先使用“测试连接”验证配置。API Key 保存在平台安全存储中，AI 操作会先展示预览，确认后才修改笔记。

## 质量检查

Flutter：

```bash
cd FlowMuse-App
flutter analyze
flutter test
```

Go：

```bash
cd FlowMuse-Server
go test ./...
go vet ./...
```

GitHub Actions 入口为 [`.github/workflows/quality.yml`](.github/workflows/quality.yml)，会执行 Flutter 依赖解析、分析、测试以及 Go 测试和 vet。

涉及 HarmonyOS 原生代码、Platform Channel 或 vendor 包时，还需执行：

```bash
cd FlowMuse-App
flutter build hap
```

## 开发约束与文档

开始开发前请先阅读 [AGENTS.md](AGENTS.md)。关键资料：

- [项目需求](docs/项目说明/项目需求.md)
- [架构约束](docs/项目说明/架构约束.md)
- [前端架构](docs/技术设计/前端架构.md)
- [接口设计](docs/技术设计/接口设计.md)
- [数据模型](docs/技术设计/数据模型.md)
- [架构决策](.agent/decisions.md)
- [研发记录](docs/研发记录/)

## 已知边界

- 不做语音/视频会议，也不定位为复杂矢量设计工具。
- 创建者归属只用于显示，不作为权限、锁定或鉴权依据；外部导出会剥离该元数据。
- 鸿蒙真机 Profile/GPU 验收仍需在真实设备上完成，自动化测试不能替代该项验收。
- `docs/周报与总结报告/`、`docs/验收材料/` 和 `docs/参赛文档/` 为本地忽略材料，不作为 GitHub 公共文档。

## 团队

陈宏宇、任逸青、李天宇
