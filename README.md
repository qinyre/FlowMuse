# FlowMuse

跨平台协同白板（笔记）应用。基于自研的 Excalidraw 风格白板内核 markdraw，支持多人实时协作、手写笔压感书写，覆盖 Android / iOS / macOS / Windows / Web / 鸿蒙多端。

## 仓库结构

```
.
├── FlowMuse-App/      # Flutter 客户端（跨端 + 鸿蒙适配）
├── FlowMuse-Server/   # Go 协作后端（Socket.IO + Docker）
└── docs/              # 设计文档、部署指南、技术调研
```

## 客户端（FlowMuse-App）

Flutter 应用，技术栈：Flutter、Riverpod、go_router、markdraw 内核、perfect_freehand、socket_io_client。

### 功能模块

- **library** — 笔记库：笔记/文件夹/标签管理、列表与封面
- **whiteboard** — 白板编辑器：内置 markdraw 内核（绘图工具、元素、序列化）+ 协作
- **account** — 账号：登录、会话、token 安全存储
- **search / settings / tags / notebooks** — 检索、设置、标签、笔记本

### markdraw 内核

自研的 Excalidraw 风格白板内核（`lib/features/whiteboard/editor_core/`），不依赖第三方白板 SDK。提供：
- 绘图工具：自由画笔（压感）、矩形、椭圆、菱形、直线、箭头、文本、橡皮、选择、激光、画框
- 元素模型与场景管理、Catmull-Rom 贝塞尔平滑
- Excalidraw JSON 与 markdraw 文本格式的双向序列化
- 历史记录（撤销/重做）、对齐、图层、分组

### 鸿蒙（HarmonyOS）适配

客户端通过 `ohos/` 目录支持鸿蒙。鸿蒙端的额外适配在分支 `markdraw-harmonyos-probe`：

- **手写笔压感**：基于 `PointerEvent.pressure`（实测可用）+ perfect_freehand 的 outline-stroke 算法实现平滑变粗笔迹，跨端通用。
- **编译兼容**：vendor 一份 `code_assets` fork（`tool/vendor/code_assets`）加入 `ohos` 枚举，解决 flutter_ohos 触发 native-assets hooks 时的 OS 解析崩溃，对其他平台零影响。
- 详见 `docs/` 下的设计文档与验收记录。

### 构建运行

```bash
cd FlowMuse-App
flutter pub get

# 各平台
flutter run -d <device>            # Android / iOS / macOS / Windows / Linux / Web
# 鸿蒙：在 DevEco Studio 打开 FlowMuse-App/ohos 构建，或 flutter run -d <ohos-device>

# 配置协作服务端地址
cp .env.example .env  # 如有；否则编辑 .env
```

## 服务端（FlowMuse-Server）

Go 1.25 协作后端，提供 Socket.IO 实时通信、房间管理、场景存储与加密。

### 部署

```bash
cd FlowMuse-Server
docker compose up -d   # 一站式部署
```

详见 `docs/` 下的部署指南。

## 技术文档

设计、计划、调研与验收记录见 `docs/`，涵盖白板内核、协作协议、鸿蒙适配与手写笔压感的演进过程。

## 许可

私有项目。
