# Saber 画板内核替换实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not create a worktree unless the user explicitly asks for one.

**Goal:** 将 FlowMuse 的 markdraw 画板编辑、输入、渲染和控制器内核替换为 Saber 画板内核，同时保留多人协作、文字识别、分页页面、无界白板、智能排版、PDF 背景页和 Excalidraw 协作格式。

**Architecture:** Saber 的 page/stroke/canvas/input/history 成为编辑运行态；FlowMuse 保留 Excalidraw JSON 作为本地存储、协作、导入导出的 canonical wire format。新增 `FlowMuseSaberBridge` 负责 `ExcalidrawScene <-> SaberBoardDocument` 双向投影，避免改动协作服务器和现有白板业务入口。

**Tech Stack:** Flutter OHOS、Dart 3.11.1、Riverpod、Socket.IO、Excalidraw JSON、Saber GPLv3 canvas/stroke/page 代码、perfect_freehand、one_dollar_unistroke_recognizer、path_drawing、vector_math。

---

## 全局执行规则

- 只允许修改 `2024-se-17/` 内文件，实际 Flutter 工程在 `FlowMuse-App/`。
- 不新增测试文件，不新增 CI/CD，不引入 worktree。
- 所有提交信息必须使用中文。
- 每个任务完成且存在文件变更后立即 commit，不能把多个任务攒成一个大提交。
- 依赖下载、版本解析或鸿蒙构建失败时停止并报告，不得改成自写替代实现。
- 不保留 markdraw markdown 旧格式兼容；对外统一保存和协作为 Excalidraw JSON。现有 `.markdraw` UI/导出入口在替换完成后移除或改为 `.excalidraw`。
- GPLv3 是已确认接受的前提：移植 Saber 代码时必须保留许可证声明和第三方许可证文档。
- Flutter 命令禁止调用 `flutter.bat`、`dart.bat`；统一使用：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" <flutter-args>
```

- Dart 格式化统一使用：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" format <paths>
```

- 常用验收命令超时建议：`pub get` 5 分钟，`analyze` 8 分钟，`build apk` 20 分钟，`build hap` 25 分钟。同一命令连续超时两次时停止并向用户报告。

## 目标文件结构

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/`
  - Saber stroke、page、tool id、canvas painter、interactive viewer、history、selection、input manager。
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge/`
  - Excalidraw JSON 与 Saber 运行态双向转换。
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/`
  - FlowMuse 包装后的 Saber editor、canvas、toolbar glue、text overlay、collaboration overlay。
- `FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart`
  - 保持对外入口不变，但导出 Saber 新实现，不再导出 markdraw editor/controller。
- `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
  - 从 `MarkdrawController/MarkdrawEditor/MarkdrawFileHandler` 切到 `SaberBoardController/SaberBoardEditor/SaberBoardFileHandler`。
- `FlowMuse-App/lib/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart`
  - 保持协作协议不变，内部改用新控制器。

## Task 1: 基线审计与依赖预检

**Files:**

- Modify: `FlowMuse-App/pubspec.yaml`
- Modify after pub get: `FlowMuse-App/pubspec.lock`

- [ ] 在仓库根执行：

```powershell
git status --short
```

Expected: 没有未提交变更；若有用户变更，记录路径并避开。

- [ ] 检查当前 Flutter/Dart 工具链：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --version
```

Expected: Dart `3.11.1` 或同系列；不要升级工具链。

- [ ] 对照 `D:\Github\FlowMuse\saber\pubspec.yaml`，只添加画板内核实际需要的直接依赖：

```yaml
  logging: ^1.2.0
  path_drawing: ^1.0.1
  one_dollar_unistroke_recognizer: ^1.1.1
```

`collection`、`fixnum`、`vector_math` 已在 lock 中出现，但如果源码直接 import，则也显式写入 `pubspec.yaml`：

```yaml
  collection: ^1.0.0
  fixnum: ^1.1.0
  vector_math: ^2.1.2
```

不要添加 `flutter_quill`、`bson`、`defer_pointer`、`keybinder`，除非后续任务明确需要；本计划不移植 Saber 的 Quill 文本层和 SBN 存储层。

- [ ] 运行：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" pub get
```

Expected: 依赖解析成功，`pubspec.lock` 更新。

- [ ] 运行：

```powershell
git diff -- FlowMuse-App/pubspec.yaml FlowMuse-App/pubspec.lock
```

Expected: 只有依赖变更，无无关格式化。

- [ ] 提交：

```powershell
git add FlowMuse-App/pubspec.yaml FlowMuse-App/pubspec.lock
git commit -m "chore: 准备 saber 画板内核依赖"
```

## Task 2: GPLv3 许可证归档

**Files:**

- Create: `FlowMuse-App/docs/licenses/saber-gplv3.md`
- Create or modify: `FlowMuse-App/docs/licenses/README.md`

- [ ] 创建 `FlowMuse-App/docs/licenses/`，复制 `D:\Github\FlowMuse\saber\LICENSE.md` 的完整内容到 `saber-gplv3.md`。
- [ ] 在 `README.md` 写明：
  - FlowMuse 移植了 Saber 画板核心代码。
  - Saber 许可证为 GPLv3。
  - 移植范围限于 canvas/stroke/page/input 相关代码。
  - Saber 原仓库参考路径为本工作区 `D:\Github\FlowMuse\saber`，不要写个人署名。
- [ ] 运行：

```powershell
git diff -- FlowMuse-App/docs/licenses
```

Expected: 只有许可证归档和说明。

- [ ] 提交：

```powershell
git add FlowMuse-App/docs/licenses
git commit -m "docs: 归档 saber 画板内核许可证"
```

## Task 3: 移植 Saber 最小基础类型

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/has_size.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/tool_id.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/stroke_options_defaults.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/point_vector_utils.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_core.dart`

- [ ] 从 `saber/packages/sbn/lib/has_size.dart` 移植 `HasSize`，去掉 `sbn` 包名依赖。
- [ ] 从 `saber/packages/sbn/lib/tool_id.dart` 移植 `ToolId`，保留枚举顺序：`highlighter` 在普通笔之前，以维持荧光笔底层渲染顺序。
- [ ] 将 `ToolId.textEditing` 只保留为内部状态，不让它参与 Excalidraw 导出。
- [ ] 从 `saber/lib/data/tools/stroke_properties.dart` 移植 `StrokeOptionsExtension.setDefaults()`，在应用启动时由 Task 8 接入。
- [ ] 将 Saber 中 Dart 3.12 的简写语法改为 Dart 3.11 兼容写法，例如 `.parsePenType` 改为 `ToolId.parsePenType`，`.zero` 改为 `Offset.zero`。
- [ ] `point_vector_utils.dart` 只放 point 平移、有限性过滤、`Offset <-> PointVector` 转换，不引入 BSON。
- [ ] 导出所有基础类型到 `saber_core.dart`。
- [ ] 格式化：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" format FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core
```

- [ ] 运行：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" analyze
```

Expected: 新文件无语法错误；若旧 markdraw 相关 warning 已存在，不在本任务处理。

- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core
git commit -m "feat: 移植 saber 画板基础类型"
```

## Task 4: 移植 Saber Stroke 模型与路径缓存

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/stroke.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/circle_stroke.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/rectangle_stroke.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_core.dart`

- [ ] 从 `saber/lib/components/canvas/_stroke.dart` 移植 `Stroke`，保留：
  - `points`
  - `pageIndex`
  - `ToolId`
  - `color`
  - `pressureEnabled`
  - `StrokeOptions`
  - `lowQualityPolygon/highQualityPolygon`
  - `lowQualityPath/highQualityPath`
  - `optimisePoints`
  - `detectShape`
  - `convertToLine`
  - `copy`
- [ ] 新增 FlowMuse 协作元数据字段：

```dart
final String elementId;
int version;
int versionNonce;
int updated;
String? index;
bool isDeleted;
Map<String, Object?>? customData;
```

- [ ] 创建 `FlowMuseStrokeMetadata` 值对象承载上述字段，避免 `Stroke` 构造参数过长。
- [ ] 从 `saber/lib/components/canvas/_circle_stroke.dart` 和 `_rectangle_stroke.dart` 移植形状笔结果。
- [ ] 移除 Saber 原始 JSON/SBN 序列化入口；序列化统一由 Task 6 的 bridge 负责。
- [ ] 将所有 `Color.toARGB32()` 改为当前 Flutter 可用写法；如果项目已有扩展，优先复用，否则用 `color.value`。
- [ ] 格式化 `saber_core`。
- [ ] 运行 `flutter analyze` 全项目，修掉本任务引入的错误。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core
git commit -m "feat: 移植 saber 笔迹模型和路径缓存"
```

## Task 5: 建立 Saber 页面与运行态文档

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_page.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_board_document.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_object_layer.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_core.dart`

- [ ] 实现 `SaberPage`：
  - `id`
  - `index`
  - `Size size`
  - `Rect sceneBounds`
  - `CanvasPageTemplate template`
  - `CanvasPageFlow pageFlow`
  - `List<Stroke> strokes`
  - `List<Stroke> laserStrokes`
  - `String source`
- [ ] 实现 `SaberObjectLayer`，只保存非 stroke 的 FlowMuse/Excalidraw 元素：
  - text
  - image
  - rectangle/ellipse/diamond/line/arrow/frame
  - page marker
  - PDF background image
  - smartLayout
  - files
- [ ] 实现 `SaberBoardDocument`：
  - `List<SaberPage> pages`
  - `SaberObjectLayer objectLayer`
  - `CanvasLayoutType layoutType`
  - `CanvasPageTemplate defaultTemplate`
  - `CanvasPageFlow pageFlow`
  - `String backgroundColor`
  - `String? name`
- [ ] 提供只读 getter：
  - `allStrokes`
  - `activeStrokes`
  - `activeObjectElements`
  - `isPaged`
  - `isUnbounded`
- [ ] 提供不可变更新方法：
  - `copyWith`
  - `replacePage`
  - `addStroke`
  - `updateStroke`
  - `softDeleteStroke`
  - `replaceObjectLayer`
- [ ] 不引入 Quill；FlowMuse 文本继续通过 Excalidraw `TextElement` 和现有 text overlay 管理。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core
git commit -m "feat: 建立 saber 白板运行态文档"
```

## Task 6: 实现 Excalidraw 与 Saber 双向桥接

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge/flow_muse_saber_bridge.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge/stroke_element_mapper.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge/object_layer_mapper.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge/saber_bridge.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart`

- [ ] `stroke_element_mapper.dart` 实现：
  - `FreedrawElement -> Stroke`
  - `Stroke -> FreedrawElement`
  - `CircleStroke -> EllipseElement`
  - `RectangleStroke -> RectangleElement`
  - shape pen line stroke -> `LineElement`
- [ ] 保留 Excalidraw 协作字段：
  - `id`
  - `version`
  - `versionNonce`
  - `updated`
  - `index`
  - `isDeleted`
  - `customData`
  - `groupIds`
  - `frameId`
- [ ] `customData.flowMuse.brushType` 映射到 `ToolId`：
  - `pencil -> ToolId.pencil`
  - `ballpoint -> ToolId.ballpointPen`
  - `fountain-pen -> ToolId.fountainPen`
  - `highlighter -> ToolId.highlighter`
  - `brush-pen -> ToolId.fountainPen`，并保留 `customData`，不新增 brush pen 私有模型。
- [ ] `object_layer_mapper.dart` 复用现有 `SceneDocumentConverter`、`ExcalidrawJsonCodec`、`Scene`、`Element` 类型，确保非 stroke 元素原样进入 `SaberObjectLayer`。
- [ ] `FlowMuseSaberBridge.fromScene(Scene scene, CanvasLayout layout, CanvasSettings settings)`：
  - 从 page marker 元素恢复 pages。
  - 无 page marker 但 layout 是 paged 时调用 `layout.ensurePage()`。
  - unbounded 时创建一个虚拟 page，尺寸覆盖当前内容 bounds，作为 Saber canvas 容器。
- [ ] `FlowMuseSaberBridge.toScene(SaberBoardDocument document, {bool includeDeleted = true})`：
  - 生成 page marker 元素。
  - 合并 stroke 映射元素和 objectLayer 元素。
  - 按 Excalidraw fractional index 排序。
  - 保留 deleted strokes，服务协作删除保留策略。
- [ ] 不写迁移兼容代码：旧 `.markdraw` markdown 解析不接入新桥接。
- [ ] 格式化 bridge 目录。
- [ ] 运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_bridge FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart
git commit -m "feat: 建立 saber 与 excalidraw 双向桥接"
```

## Task 7: 移植 Saber CanvasPainter

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_canvas_painter.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_canvas_background_painter.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_pencil_shader.dart`
- Modify: `FlowMuse-App/pubspec.yaml` if shader assets need path adjustment
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_core.dart`

- [ ] 从 `saber/lib/components/canvas/_canvas_painter.dart` 移植绘制顺序：
  - highlighter strokes 先按颜色分层绘制。
  - 普通 strokes 后绘制。
  - laser strokes 临时绘制。
  - current stroke 总是高质量绘制。
  - selection 虚线 overlay 由 Task 11 接入。
- [ ] 复用当前项目已有 `FlowMuse-App/shaders/pencil.frag`，不新增 shader 文件。
- [ ] 移植铅笔 shader 管理逻辑，命名为 `SaberPencilShader`；鸿蒙不支持时只日志降级为普通铅笔，不抛异常。
- [ ] 移植背景 painter 的页面底色、网格、横线、点阵；模板名必须映射到现有 `CanvasPageTemplate`。
- [ ] 当前 `StaticCanvasPainter` 暂不删除；本任务只让 Saber painter 能独立编译。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core FlowMuse-App/pubspec.yaml FlowMuse-App/pubspec.lock
git commit -m "feat: 移植 saber 画布渲染器"
```

## Task 8: 应用启动接入 Saber 默认笔迹参数

**Files:**

- Modify: `FlowMuse-App/lib/main.dart`
- Modify as needed: `FlowMuse-App/lib/app/flow_muse_app.dart`

- [ ] 在应用启动早期调用 `StrokeOptionsExtension.setDefaults()`。
- [ ] 在同一位置初始化 `SaberPencilShader.init()`，使用 `unawaited` 或启动前 `await` 均可；不要因 shader 失败阻断应用。
- [ ] 确保没有重复调用旧 `PencilShader.init()`；若旧 markdraw shader 初始化存在，替换为 Saber 新入口。
- [ ] 格式化修改文件。
- [ ] 运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/main.dart FlowMuse-App/lib/app/flow_muse_app.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core
git commit -m "feat: 启用 saber 笔迹默认参数"
```

## Task 9: 移植 Saber 交互视口

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_interactive_viewer.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_viewport_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart` only if new adapter needs shared helpers

- [ ] 从 `saber/lib/components/canvas/interactive_canvas.dart` 移植 `InteractiveCanvasViewer`。
- [ ] 改为 FlowMuse 命名：`SaberInteractiveViewer`。
- [ ] 保留：
  - builder 只渲染可视页面。
  - wheel/trackpad pan。
  - Ctrl/Meta + wheel zoom。
  - pinch zoom。
  - fling inertia。
  - min/max zoom。
- [ ] 移除 `keybinder` 依赖，键盘缩放和方向键移动交给现有 `KeyboardHandler` 或 Task 15 的 editor glue。
- [ ] `SaberViewportController` 提供与旧 `ViewportState` 对齐的方法：
  - `screenToScene(Offset)`
  - `sceneToScreen(Offset)`
  - `visibleRect(Size)`
  - `zoom`
  - `offset`
  - `setViewport(ViewportState)`
- [ ] unbounded 白板使用无限 `boundaryMargin`；paged 使用页面集合 bounds 加外边距。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/viewport_state.dart
git commit -m "feat: 移植 saber 交互视口"
```

## Task 10: 移植 Saber 笔工具和形状笔

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_pen_tool.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_shape_pen_tool.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_eraser_tool.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_laser_tool.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_type.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core/saber_core.dart`

- [ ] 从 Saber `Pen`、`ShapePen`、`Highlighter`、`Pencil`、`LaserPointer` 行为移植工具逻辑，但不要移植 prefs/i18n。
- [ ] FlowMuse 的 `BrushState` 继续作为 UI 状态来源，映射到 Saber `StrokeOptions`。
- [ ] Shape pen 使用 `one_dollar_unistroke_recognizer`：
  - 识别 line 时调用 `convertToLine()`。
  - 识别 rectangle 时输出 `RectangleStroke`。
  - 识别 circle 时输出 `CircleStroke`。
  - 识别 triangle/star 时保留普通 stroke。
- [ ] Eraser v1 只做整笔删除：命中 stroke path 或 object element 时 soft delete。不要实现像素级橡皮或半笔擦除。
- [ ] Laser stroke 不进入 Excalidraw scene，不参与本地保存，只广播存在感和本机临时渲染。
- [ ] 继续保留 `BrushType.canAutoRecognize` 逻辑：highlighter 不触发 OCR。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_core FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_type.dart
git commit -m "feat: 移植 saber 笔工具和形状笔"
```

## Task 11: 实现 SaberBoardController

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_controller.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_state.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_history_manager.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_selection_state.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_ui.dart`

- [ ] `SaberBoardState` 字段：
  - `SaberBoardDocument document`
  - `ViewportState viewport`
  - `Set<String> selectedElementIds`
  - `Set<String> selectedStrokeIds`
  - `ToolType activeToolType`
  - `BrushType activeBrushType`
  - `bool toolLocked`
- [ ] `SaberBoardController` 对外方法必须覆盖旧业务调用：
  - `loadFromContent(String content, String filename)`
  - `serializeScene({required DocumentFormat format})`
  - `serializeExcalidrawSceneJson({bool includeDeleted = true})`
  - `applyRemoteExcalidrawSceneJson(Map<String, Object?> sceneJson, {bool closeTransientUi = true})`
  - `currentScene`
  - `editorState` 替换为 `boardState`
  - `selectedElements`
  - `selectedElementIds`
  - `setLayout(CanvasLayout layout)`
  - `appendPageAfterLastAndScroll()`
  - `contentBounds`
  - `exportPng`
  - `exportSvg`
  - `exportCoverThumbnail`
  - `importImage`
  - `recognizeSelectedInk`
  - `smartLayoutSelectedInk`
- [ ] 历史栈保存 `SaberBoardDocument` 快照，不保存 widget 状态。
- [ ] 每次 scene 级变化调用 `onSceneChanged?.call(toScene())`，使白板页面自动保存和协作广播不需要改业务逻辑。
- [ ] 不在 Controller 内直接访问 Riverpod 或数据库。
- [ ] 格式化并运行 analyze，接受 `WhiteboardPage` 尚未切换造成的未引用类。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui
git commit -m "feat: 建立 saber 白板控制器"
```

## Task 12: 实现 SaberBoardCanvas Widget

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_canvas.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_object_layer_painter.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_interactive_overlay_painter.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_text_editing_overlay.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_ui.dart`

- [ ] Canvas 使用 `SaberInteractiveViewer.builder` 包裹页面布局。
- [ ] 每页内部绘制：
  - Saber background painter。
  - Saber stroke painter。
  - FlowMuse object layer painter，复用 `ElementRenderer` 绘制非 stroke Excalidraw 元素。
  - collaboration pointer/selection overlay。
  - local selection overlay。
  - text/frame label editing overlay。
- [ ] Pointer 输入进入 `SaberBoardController`：
  - stylus/mouse/touch 压感归一化沿用现有 `StrokeInputNormalizer`。
  - 不再使用旧 `StrokeInputModeler` 做二次滤波。
- [ ] Paged touch pan 保留当前行为：手形工具或 view mode 下单指滚动页面；末页拉动追加页面。
- [ ] 无界白板允许平移到内容外侧，不夹死到页面边界。
- [ ] `onPointerPresence` 和 `onVisibleSceneBoundsChanged` 继续回调给 `WhiteboardPage`。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui
git commit -m "feat: 接入 saber 白板画布组件"
```

## Task 13: 替换编辑器 UI 外壳

**Files:**

- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_editor.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_file_handler.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/markdraw.dart`

- [ ] `SaberBoardEditor` 保留旧 `MarkdrawEditor` 的构造参数语义，便于 Task 14 小范围替换：
  - controller
  - config
  - currentThemeMode
  - saveStatusLabel
  - collaboration 状态字段
  - collaborator overlays
  - onSave/onOpen/onShare/onBack/onStartCollaboration/onJoinCollaboration/onRecognizeInk/onSmartLayoutInk/onSceneChanged 等回调。
- [ ] 工具栏可以暂时复用旧 toolbar widgets，但 controller 类型必须是 `SaberBoardController`。如果旧 widget 强耦合 `MarkdrawController`，复制到 `saber_ui` 后改类型，不继续扩大旧命名。
- [ ] `SaberBoardFileHandler` 支持：
  - `saveAs` 导出 `.excalidraw`。
  - `exportPng`
  - `exportSvg`
  - `importImage`
  - `exportSmartLayout`
  - 删除 `.markdraw` 导入导出入口。
- [ ] `flow_muse_whiteboard_editor.dart` 导出新 Saber API。
- [ ] `markdraw.dart` 只临时 re-export 新 API 并加弃用注释，供未切换文件编译；Task 19 删除它。
- [ ] 格式化并运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart FlowMuse-App/lib/features/whiteboard/editor_core/markdraw.dart
git commit -m "feat: 建立 saber 白板编辑器外壳"
```

## Task 14: 切换 WhiteboardPage 到 Saber 控制器

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/share_export_coordinator.dart` if it references MarkdrawController
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/imported_document_coordinator.dart` if it references MarkdrawController

- [ ] 将字段替换：
  - `_markdrawController` -> `_saberController`
  - `MarkdrawController` -> `SaberBoardController`
  - `MarkdrawFileHandler` -> `SaberBoardFileHandler`
  - `MarkdrawEditor` -> `SaberBoardEditor`
  - `WhiteboardCollaborationAdapter(_markdrawController)` -> `WhiteboardCollaborationAdapter(_saberController)`
- [ ] 保持 `_saveMarkdrawScene()` 方法名可先不改，减少本任务 diff；内部调用新 controller。
- [ ] 所有序列化仍使用：

```dart
_saberController.serializeScene(format: DocumentFormat.excalidraw)
```

- [ ] `PdfNoteConsumer.consume` 参数改为新 controller；如果 `PdfNoteConsumer` 类型强耦合旧 controller，Task 16 处理前先在本任务最小改到可编译。
- [ ] `exportCoverThumbnail()` 继续用于笔记封面。
- [ ] 格式化 `whiteboard_page.dart` 和受影响 share 文件。
- [ ] 运行 analyze，修复所有 `MarkdrawController` 类型错误。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/lib/features/whiteboard/share
git commit -m "refactor: 白板页面切换到 saber 控制器"
```

## Task 15: 切换协作适配器

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart`
- Modify if needed: `FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_debug_log.dart`

- [ ] 适配器字段从 `MarkdrawController` 改为 `SaberBoardController`。
- [ ] `currentScene()` 继续返回：

```dart
ExcalidrawScene.fromJson(
  controller.serializeExcalidrawSceneJson(includeDeleted: includeDeleted),
)
```

- [ ] `applyRemoteScene()` 继续调用：

```dart
controller.applyRemoteExcalidrawSceneJson(scene.toJson(), closeTransientUi: closeTransientUi)
```

- [ ] `selectedElementIds()` 返回 object elements 和 strokes 的 Excalidraw element id，并保持 `Set<String>`。
- [ ] `protectedElementIds()` 包含：
  - selected objects
  - selected strokes
  - editing text id
  - editing frame label id
  - current active stroke id if any
- [ ] `pointerPayload()` 使用 `SaberBoardController.toScene(localPosition)`。
- [ ] `visibleSceneBounds()` 使用新 viewport visible rect。
- [ ] 运行 analyze。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/collaboration/services/whiteboard_collaboration_adapter.dart FlowMuse-App/lib/features/whiteboard/collaboration/services/collaboration_debug_log.dart
git commit -m "refactor: 协作适配器接入 saber 场景"
```

## Task 16: 恢复分页、PDF 背景页和无界白板

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_consumer.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/pdf_note_import/pdf_note_import_service.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf/pdf_importer.dart` if controller type leaks
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_controller.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_canvas.dart`

- [ ] `SaberBoardController.setLayout(CanvasLayout layout)`：
  - paged note 创建真实 `SaberPage` 列表。
  - unbounded note 创建虚拟 infinite page，不渲染纸张阴影。
- [ ] `appendPageAfterLastAndScroll()`：
  - 新增 `SaberPage`。
  - 写入 page marker object。
  - 更新 viewport 滚到新页面。
  - 调用 `onSceneChanged`。
- [ ] `PdfNoteConsumer.pdfBackgroundBounds()` 改为从 `SaberBoardController.currentScene` 获取。
- [ ] PDF 导入仍将每页渲染成 image element 并放入 page object layer；不要转成 Saber backgroundImage 私有格式。
- [ ] `contentBounds` 在 PDF 笔记中继续裁剪绘制和输入，防止写到 PDF 外侧。
- [ ] 右侧分页进度条读取新 `pagedViewportMetrics`。
- [ ] 古籍右向左页面流继续使用 `CanvasPageFlow.rightToLeft`。
- [ ] 格式化并运行 analyze。
- [ ] 手动启动应用后验收：
  - 创建分页笔记。
  - 创建无界白板。
  - PDF 笔记导入后页面数量、背景图片和可写区域正确。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/pdf_note_import FlowMuse-App/lib/features/whiteboard/editor_core/src/core/pdf FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui
git commit -m "feat: 恢复 saber 内核下的分页和 pdf 背景页"
```

## Task 17: 恢复 OCR 与智能排版

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_controller.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_ink_recognition_adapter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/ink_recognition/ink_recognition_repository.dart` only if type imports need update
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_exporter.dart` if it assumes old controller

- [ ] Saber stroke 写入以下 recognition metadata 到 `FlowMuseStrokeMetadata.customData`：
  - `flowmuse.recognition.sessionId`
  - `flowmuse.recognition.pending`
  - `flowmuse.recognition.startedAt`
  - `flowmuse.recognition.pointTimes`
- [ ] `SaberInkRecognitionAdapter.pendingStrokes(sessionId)` 从 active Saber strokes 找待识别笔迹。
- [ ] `InkRecognitionRequest` 使用 stroke 的绝对 scene 坐标点和 pointTimes。
- [ ] 自动识别：最后一笔结束后 1 秒 debounce；有新笔接入时合并同 session。
- [ ] 手动识别：框选 stroke 后生成 request；识别成功后 soft delete 原 strokes，插入识别返回的 TextElement/shape elements。
- [ ] 智能排版仍以 Excalidraw scene 投影发送给服务端，返回的 `SmartLayoutDocument` 写回 `SaberBoardDocument.objectLayer.smartLayout`。
- [ ] highlighter 不参与 OCR。
- [ ] 格式化并运行 analyze。
- [ ] 手动验收：
  - 自动识别手写中文。
  - 框选识别。
  - OCR 结果在协作端同步。
  - 智能排版导出 Markdown/LaTeX。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui FlowMuse-App/lib/features/whiteboard/ink_recognition FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout
git commit -m "feat: 恢复 saber 内核下的文字识别和智能排版"
```

## Task 18: 恢复导入导出和分享路径

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui/saber_board_file_handler.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/png_exporter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/svg_exporter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/share_export_coordinator.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/share/services/imported_document_coordinator.dart`

- [ ] PNG 导出从 `SaberBoardDocument -> Scene` 投影后复用现有 `PngExporter`，避免重写导出器。
- [ ] SVG 导出同样使用 Excalidraw scene 投影。
- [ ] `.excalidraw` 导出使用 `FlowMuseSaberBridge.toScene()` 后 `ExcalidrawJsonCodec.serialize()`。
- [ ] 移除 `.markdraw` 导出和导入入口；所有 UI 文案改为“导出 Excalidraw 文件”。
- [ ] 图片导入仍创建 `ImageElement` + `ImageFile`，写入 object layer files。
- [ ] 外部文档导入只接受 `.excalidraw`；如果当前 share 模块还声明 `.markdraw`，删除相关分支和文案。
- [ ] 格式化并运行 analyze。
- [ ] 手动验收：
  - PNG 导出。
  - SVG 导出。
  - Excalidraw 导出后重新打开。
  - 图片导入并协作同步。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ui FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export FlowMuse-App/lib/features/whiteboard/share
git commit -m "feat: 恢复 saber 内核下的导入导出"
```

## Task 19: 替换公开导出并清理 markdraw 命名 API

**Files:**

- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart`
- Delete: `FlowMuse-App/lib/features/whiteboard/editor_core/markdraw.dart`
- Delete or stop exporting old markdraw UI/controller files under `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/`
- Delete old freedraw/input/rendering files only when no longer referenced:
  - `src/editor/tools/freedraw_tool.dart`
  - `src/input/stroke_input_modeler.dart`
  - `src/input/one_euro_filter.dart`
  - `src/rendering/rough/freedraw_renderer.dart`
  - `src/rendering/rough/pencil_shader.dart`

- [ ] 运行引用检查：

```powershell
rg -n "Markdraw|markdraw" FlowMuse-App/lib
```

Expected: 不再有运行时代码引用；允许许可证、旧字体目录名或历史 docs 出现。

- [ ] 删除旧 markdraw editor/controller/canvas 文件。优先用 `apply_patch` 删除；如果使用命令，必须逐个明确路径，不使用通配删除。
- [ ] `flow_muse_whiteboard_editor.dart` 只导出：
  - existing Excalidraw core model/serialization still used by bridge
  - `src/saber_core/saber_core.dart`
  - `src/saber_bridge/saber_bridge.dart`
  - `src/saber_ui/saber_ui.dart`
- [ ] 检查 `pubspec.yaml` 字体：如果 `Excalifont/Virgil` 只服务旧 markdraw 手绘风，可保留到最终 UI 决定，不在本任务删除资源。
- [ ] 格式化受影响文件。
- [ ] 运行 analyze，清理所有 unused import/export。
- [ ] 提交：

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core
git commit -m "refactor: 移除旧 markdraw 画板内核"
```

## Task 20: 清理产品文档和开发文档

**Files:**

- Modify: `REQUIREMENTS.md`
- Modify: `FlowMuse-App/README.md`
- Modify if present: `.agent/architecture.md`
- Modify if present: `.agent/conventions.md`
- Modify if present: `docs/` 中描述 markdraw 内核为当前实现的最新文档

- [ ] 将“markdraw 内核”当前状态改为“Saber 画板内核 + Excalidraw 协作格式”。
- [ ] 写清楚新架构：
  - Saber 负责输入、笔迹、页、渲染、运行态历史。
  - Excalidraw JSON 负责协作、保存、导入导出。
  - FlowMuse object layer 负责文本、图片、Frame、箭头、智能排版、PDF 背景。
- [ ] 删除或更新 `.markdraw` 文件格式相关当前能力描述。
- [ ] 不写署名。
- [ ] 运行：

```powershell
git diff --check
```

Expected: 无尾随空格。

- [ ] 提交：

```powershell
git add REQUIREMENTS.md FlowMuse-App/README.md .agent docs
git commit -m "docs: 更新 saber 画板内核架构说明"
```

## Task 21: 全量静态验收

**Files:**

- Modify only if analyze/build exposes compile errors in implementation files.

- [ ] 运行依赖确认：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" pub get
```

- [ ] 运行静态分析：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" analyze
```

Expected: 无 error。若出现旧测试 import 失败，不新增测试；只修复生产代码或必要的旧测试引用删除。

- [ ] 运行格式检查：

```powershell
git diff --check
```

- [ ] 若有修复，按涉及文件提交：

```powershell
git add <修复文件>
git commit -m "fix: 修复 saber 内核静态检查问题"
```

如果没有文件变更，不提交。

## Task 22: Android 与鸿蒙构建验收

**Files:**

- Modify only if build exposes compile errors in implementation files.

- [ ] 构建 Android debug APK：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" build apk --debug --no-pub
```

Expected: 生成 debug APK。Flutter 开发不执行实体设备自动安装要求。

- [ ] 构建 HarmonyOS HAP：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" build hap --debug --no-pub
```

Expected: 生成 debug HAP。

- [ ] 若构建失败，优先修复：
  - Dart 3.12 语法误移植。
  - 条件导入缺失。
  - OHOS native-assets 不兼容依赖。
  - shader asset 路径。
  - 未清理的 markdraw export。
- [ ] 若有修复，提交：

```powershell
git add <修复文件>
git commit -m "fix: 修复 saber 内核跨端构建问题"
```

如果没有文件变更，不提交。

## Task 24: 最终收尾

**Files:**

- No planned modifications.

- [ ] 确认没有 markdraw 运行时代码引用：

```powershell
rg -n "Markdraw|markdraw" FlowMuse-App/lib
```

Expected: 不出现运行时代码引用。

- [ ] 确认没有新测试文件：

```powershell
git status --short
rg --files FlowMuse-App/test
```

Expected: `test/` 内没有本计划新增文件；若因执行误新增测试，删除后再继续。

- [ ] 查看提交历史：

```powershell
git log --oneline -n 30
```

Expected: 每个任务有独立中文 commit。

- [ ] 最终状态：

```powershell
git status --short
```

Expected: 工作树干净。

- [ ] 不自动 push，除非用户明确要求。

## Task 23: 结束任务，提请用户手动验收

**Files:**

- Modify only if manual verification exposes bugs.

提请用户按以下步骤验收，结束任务。

- [ ] 启动应用：

```powershell
& "C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe" --packages="C:\tools\flutter_ohos\packages\flutter_tools\.dart_tool\package_config.json" "C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot" run
```

- [ ] 验收分页笔记：
  - 创建普通分页笔记。
  - 写入钢笔、铅笔、圆珠笔、荧光笔。
  - 末页拉动添加页面。
  - 页面进度条正确。
  - 退出再进入，内容保持。
- [ ] 验收无界白板：
  - 创建无界白板。
  - 大范围平移缩放。
  - 输入笔迹、形状、文本、图片。
  - 导出 PNG/SVG/Excalidraw。
- [ ] 验收 Saber 笔迹手感：
  - 压感笔迹随 stylus pressure 变化。
  - 鼠标/触摸无压感时使用模拟压力。
  - 铅笔 shader 支持时有效，不支持时不崩溃。
  - 荧光笔在普通笔下层渲染。
- [ ] 验收形状笔：
  - 手绘直线转线段。
  - 手绘矩形转矩形。
  - 手绘圆转椭圆。
- [ ] 验收对象层：
  - 文本编辑。
  - 图片导入。
  - Frame。
  - 箭头绑定和箭头标签。
  - 分组、选择、移动、缩放。
- [ ] 验收 OCR：
  - 自动识别。
  - 框选手动识别。
  - 识别结果替换原 stroke。
- [ ] 验收 PDF：
  - 新建 PDF 笔记。
  - 多页背景正确。
  - 只能在 PDF content bounds 内书写。
- [ ] 验收智能排版：
  - 对选中内容发起智能排版。
  - Markdown/LaTeX 导出正常。
- [ ] 验收协作：
  - 两端进入同一房间。
  - 双方同时书写 stroke。
  - 一方移动对象，另一方同步。
  - 远端光标、选区、在线状态正常。
  - 断线重连后场景不丢 stroke。
- [ ] 若发现 bug，按最小影响文件修复并提交：

```powershell
git add <修复文件>
git commit -m "fix: 修复 saber 内核验收问题"
```
