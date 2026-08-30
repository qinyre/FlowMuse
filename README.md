# FlowMuse（流形白板）

FlowMuse 是一个面向课堂笔记、会议协作和灵感记录的跨平台协同白板。客户端基于 Flutter 和自研 Markdraw 白板内核，服务端使用 Go，支持 Android、HarmonyOS、Web、Windows、macOS 和 iOS。

它适合三类场景：一个人手写和整理笔记、多人一起在白板上讨论、把手写内容交给识别和 AI 工具继续加工。协作消息和快照使用 AES-GCM 端到端加密；在协作数据上，服务端只负责转发和保存密文。

当前主线已经包含协作元素归属显示和按创建者聚焦；鸿蒙真机 Profile/GPU 验收仍待完成。

## 主要功能

- 手写笔迹、压感、自然介质铅笔/毛笔（颗粒浓淡、提按出锋）、形状、文本、图片、Frame、绑定箭头、分页、撤销和重做
- 笔记本、标签、搜索、封面和 SQLite 本地保存，断网也可以使用基础白板功能
- PDF 分页导入，以及 .markdraw、.excalidraw 文件导入导出
- 多端实时协作、在线成员、远端光标和 AES-GCM 端到端加密
- 按元素创建者查看协作内容；聚焦只改变本机显示，不改变文档层级或其他人的编辑
- 手写识别、公式/形状识别、智能排版和跨端语音转文字
- AI 问答、文本生成、思维导图和智能排版；AI 写入前会先展示预览
- AI 可在用户主动操作后附带框选截图或当前 PDF 页
- HarmonyOS 手写笔、原生 HTTP、文件、PDF、语音和 Pen Kit 能力适配

## 运行前准备

普通平台使用 Flutter 3.41.10 和 Dart 3.11.1。HarmonyOS 使用 flutter_ohos 3.41.10-ohos-0.0.1-canary1，并需要 DevEco Studio。

如果只想查看或编辑本地白板，不启动服务端即可。实时协作、账号、手写识别和服务端智能排版需要启动 FlowMuse-Server。

## 最快启动

### 运行客户端

~~~bash
cd FlowMuse-App
flutter pub get
flutter devices
flutter run -d <device-id>
~~~

Web：

~~~bash
cd FlowMuse-App
flutter run -d chrome
~~~

Windows 桌面端：

~~~powershell
cd FlowMuse-App
flutter run -d windows
~~~

客户端默认读取 FlowMuse-App/assets/config/app.env。连接局域网或自建服务时，可在启动命令中覆盖地址：

~~~bash
flutter run -d <device-id> \
  --dart-define=FLOWMUSE_COLLAB_SERVER_URL=http://<server-ip>:48931 \
  --dart-define=FLOWMUSE_SHARE_ORIGIN=http://<web-origin>
~~~

真机不能通过 127.0.0.1 访问电脑服务，请使用电脑局域网 IP 或可访问的公网地址。

HarmonyOS 必须使用 flutter_ohos，不能用标准 Flutter SDK 构建 HAP：

~~~bash
cd FlowMuse-App
flutter build hap
~~~

### 启动服务端

需要 Docker 和 Docker Compose：

~~~bash
cd FlowMuse-Server
cp .env.example .env
docker compose up --build
~~~

Windows PowerShell：

~~~powershell
cd FlowMuse-Server
Copy-Item .env.example .env
docker compose up --build
~~~

服务默认监听 http://127.0.0.1:48931。启动后先检查：

~~~text
http://127.0.0.1:48931/health
~~~

手写识别和服务端智能排版需要在 FlowMuse-Server/.env 配置 MyScript 或 OpenAI 兼容服务。密钥不要提交到仓库；部署 Web 时还要设置正确的 FLOWMUSE_ALLOWED_ORIGINS。

### 两个客户端测试协作

1. 启动服务端，确认 health 地址返回正常。
2. 在 Chrome 和 Windows 客户端使用同一个服务地址启动。
3. 一端创建房间，另一端通过完整房间链接加入。
4. 两端分别创建笔迹、文本和形状，确认内容、光标和成员状态同步。
5. 点击协作者头像或元素属性面板中的创建者入口，确认聚焦只改变当前客户端的透明度，并保持原来的遮挡顺序。
6. 导出 .markdraw、.excalidraw 或 .json，确认外部文件不包含 collaborationOwner。

## AI 助手

客户端进入“设置 → 实验室”，填写 OpenAI 兼容 Base URL、API Key 和模型名称。API Key 保存在平台安全存储中，AI 返回动作后会先展示预览，确认后才修改笔记。

## 开发检查

Flutter：

~~~bash
cd FlowMuse-App
flutter analyze
flutter test
~~~

Go：

~~~bash
cd FlowMuse-Server
go test ./...
go vet ./...
~~~

GitHub Actions 入口是 [.github/workflows/quality.yml](.github/workflows/quality.yml)，会执行 Flutter 依赖解析、分析、测试以及 Go 测试和 vet。涉及 HarmonyOS 原生代码、Platform Channel 或 vendor 包时，还需要运行 flutter build hap，并记录真机验证结果。

## 代码和文档位置

- FlowMuse-App：Flutter 客户端、Markdraw 内核和 HarmonyOS 原生适配
- FlowMuse-Server：Go 协作、账户、文件和识别服务
- [项目需求](docs/项目说明/项目需求.md)和[架构约束](docs/项目说明/架构约束.md)
- [技术设计](docs/技术设计/前端架构.md)：前端架构、接口、数据模型和部署说明
- [研发记录](docs/研发记录/)：功能计划、调研、审查和落地记录
- [.agent/decisions.md](.agent/decisions.md)：架构决策记录
- [AGENTS.md](AGENTS.md)：开发流程、跨端约束和完成前验证清单

## 当前边界

- 不做语音/视频会议，也不定位为复杂矢量设计工具。
- 创建者归属只用于显示，不作为权限、锁定或鉴权依据。
- 外部导出会剥离创建者元数据，协作密文和内部本地存储保留。
- 鸿蒙真机 Profile/GPU 验收仍需完成，自动化测试不能替代真实设备测试。
- docs/周报与总结报告、docs/验收材料和 docs/参赛文档属于本地忽略材料，不作为 GitHub 公共文档。

## 团队

陈宏宇、任逸青、李天宇
