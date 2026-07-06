# Markdraw Excalidraw Core Design

## 背景

FlowMuse 当前白板实现已经把元素 JSON、版本字段、顺序字段和删除字段向 Excalidraw 靠拢，但编辑内核仍是轻量自研版本。现有能力主要集中在创建矩形、椭圆、箭头、笔迹和文本；选择、编辑、图片、Frame、分组、绑定箭头、线段编辑、导入导出和协作语义都没有完整对齐 Excalidraw。

本地 `D:\Github\FlowMuse\markdraw` 已经提供 Flutter 版 Excalidraw-inspired 白板内核，包含完整元素集、选择编辑、分组、Frame、图片、绑定箭头、elbow routing、撤销重做、Excalidraw JSON 导入导出、Excalidraw library、PNG/SVG 导出和大量测试。按项目规则，后续不继续扩展当前简化画布，而是复用 `markdraw` 作为 FlowMuse 白板核心。

## 目标

- 用 `markdraw` 接管 FlowMuse 的白板编辑内核。
- 除手绘视觉风格外，白板数据结构、导入导出、编辑语义和协作基础继续向 Excalidraw 对齐。
- 删除当前轻量白板内核在生产路径中的职责，避免维护两套模型。
- 保留 FlowMuse 的应用壳、路由、资料库、主题与跨端 Flutter/Harmony 工程结构。

## 非目标

- 本阶段不重写 `markdraw` 的完整源码。
- 本阶段不新增 CI/CD。
- 本阶段不自己重新实现选择、Frame、绑定箭头、导出等 `markdraw` 已有能力。
- 本阶段不追求手绘视觉风格；视觉风格可以后续通过配置或渲染适配收敛为 FlowMuse 风格。
- 本阶段不实现真实服务端协作，只为后续协作层接入准备统一场景模型。

## 当前差距

### 数据模型

FlowMuse 的 `WhiteboardElement` 覆盖了 Excalidraw 的不少字段，但仍有结构性差距：

- 缺少 `roundness` 等 Excalidraw 基础字段。
- `boundElements`、`startBinding`、`endBinding` 使用裸 `Map`，没有强类型约束。
- `diamond`、`line`、`image`、`frame`、`magicframe`、`embeddable`、`iframe` 只是部分枚举或字段存在，交互和渲染没有完整接入。
- `restoreElements`、`restoreAppState`、`serializeAsJSON` 等 Excalidraw 恢复/序列化语义未完整移植。

### 编辑与渲染

FlowMuse 当前画布是单层 `CustomPainter` 和简单 `GestureDetector`。Excalidraw 需要的选择、多选、框选、移动、缩放、旋转、线段编辑、文本编辑、图片、Frame、分组、锁定、层级、快捷键、snap、交互 overlay 等能力尚未形成。

`markdraw` 已经提供这些能力，并且其公开 API 以 `MarkdrawEditor` 和 `MarkdrawController` 为主，适合接入 FlowMuse 页面。

### 协作

FlowMuse 当前 `SceneReconciler` 是 Excalidraw `reconcileElements` 的简化版，只按版本和 `versionNonce` 取舍并排序。上游 Excalidraw 还包含：

- 本地正在编辑元素的远端更新保护。
- `orderByFractionalIndex`、`syncInvalidIndices`、`validateFractionalIndices`。
- Portal socket 的 `SCENE_INIT`、`SCENE_UPDATE`、`MOUSE_LOCATION`、`IDLE_STATUS` 等消息。
- 远端加密存储、文件同步、在线状态和光标同步。

迁移后协作层应以 `markdraw` 场景和 Excalidraw JSON 元素为边界重建，不继续依赖旧 `CollaborativeElement` 的简化模型作为最终协议。

## 方案

### 1. 接入方式

在 `2024-se-17/pubspec.yaml` 增加本地 path dependency：

```yaml
dependencies:
  markdraw:
    path: ../markdraw
```

`markdraw` 已在同一工作区内，优先作为本地库复用。若其依赖缺失或 Harmony Flutter 兼容性出现阻塞，不降级自研；先报告具体依赖或平台问题。

### 2. 页面集成

`WhiteboardPage` 保留 FlowMuse 顶部应用壳信息、房间状态入口和主题上下文，但中心画布区域改为 `MarkdrawEditor`。

每个打开的 notebook 绑定一个 `MarkdrawController`。页面进入时从 `WhiteboardSceneRepository` 读取保存内容并加载到 controller；controller 变更时通过 `onSceneChanged` 自动保存。

### 3. 存储格式

旧 `WhiteboardScene` 生产路径不再作为主要场景模型。新的持久化格式采用 `markdraw` 导出的 Excalidraw JSON 字符串。

Repository 边界改为：

- `loadSceneContent(notebookId)` 返回 Excalidraw JSON 字符串，空白 notebook 返回一个空 Excalidraw 场景。
- `saveSceneContent(notebookId, content)` 保存 controller 导出的 Excalidraw JSON。

不用考虑旧版本向前兼容；已有旧 `WhiteboardElement` JSON 可以直接废弃或只保留测试参考。

### 4. 旧代码处理

第一步不立即删除所有旧模型文件，避免一次改动过大；但生产 UI 不再使用旧 `WhiteboardCanvas` 和旧 `WhiteboardViewModel.addElementFromDrag` 路径。

完成替换并验证后，再删除不再需要的旧 widget、model 测试和简化协作模型，保留后续协作重建所需的加密与房间链接代码。

### 5. 协作后续边界

本次核心替换完成后，协作层进入下一阶段：

- 以 Excalidraw JSON elements 为同步对象。
- 将 `markdraw` scene 转换为 ordered Excalidraw elements。
- 移植 Excalidraw 的 reconcile 规则，包括本地编辑保护和 index 修复。
- 保留当前 `CollaborationCrypto` 和 `CollaborationRoom`，重写消息 payload 和 repository 边界。

## 测试策略

不新增大规模测试框架。只调整现有 Flutter 测试，覆盖迁移风险最高的行为：

- 白板页面能打开并显示 `MarkdrawEditor`。
- notebook 打开时能从 repository 加载 Excalidraw JSON。
- controller 场景变更后能保存 Excalidraw JSON。
- 旧轻量画布创建元素的测试删除或替换为 `markdraw` 集成测试。
- 保留现有加密和房间链接测试，协作 payload 测试在下一阶段重写。

验证命令使用 Flutter exe 全路径，遵守项目规则，不调用 `dart.bat` 或 `flutter.bat` 包装脚本。

## 实施顺序

1. 添加 `markdraw` 本地依赖并拉取依赖。
2. 改造 whiteboard repository，使其保存 Excalidraw JSON 字符串。
3. 在 `WhiteboardPage` 中创建和管理 `MarkdrawController`。
4. 用 `MarkdrawEditor` 替换旧 `WhiteboardCanvas`。
5. 调整或删除失效的旧白板测试。
6. 运行 Flutter 测试和分析。
7. 如果连接了项目规则指定的安卓实体设备，本项目是 Flutter 开发，不执行原生 Android 安装流程。

## 风险

- `markdraw` 依赖可能引入当前项目未声明的包，需要通过 `flutter pub get` 解决。
- `markdraw` 的手绘渲染默认开启，视觉可能与 FlowMuse 当前产品气质不一致；这不是本阶段阻塞，后续通过配置和渲染适配处理。
- Harmony Flutter 对部分文件 I/O、剪贴板或平台插件能力可能有限；本阶段先不接入 `MarkdrawFileHandler`，避免引入平台文件选择器风险。
- 当前 FlowMuse 白板状态由 Riverpod Notifier 管理，`markdraw` 由 `ChangeNotifier` controller 管理，需要在页面层明确生命周期，避免重复创建 controller。

## 完成标准

- FlowMuse 白板页面使用 `markdraw` 编辑器作为主画布。
- 能打开 notebook、编辑场景并保存为 Excalidraw JSON。
- 生产路径不再依赖旧轻量 `WhiteboardCanvas` 创建元素。
- 现有相关测试调整后通过。
- 变更保持 Flutter/Harmony 项目结构，不新增 CI/CD，不署名。
