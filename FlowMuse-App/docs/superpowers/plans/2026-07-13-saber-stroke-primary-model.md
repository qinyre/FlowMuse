# Saber Stroke 主模型迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 FlowMuse 手写主模型从 markdraw `FreedrawElement` 切换为 Saber `Stroke` 体系，并保持联机协作和文字识别可用。

**Architecture:** 新增 `saber_ink` 子系统承载 Saber stroke、tool id、stroke option、painter、tool adapter 和 scene patch；`Scene` 聚合非手写元素与 `SaberInkScene`。迁移期间旧 `FreedrawElement` 只作为导入源存在，新绘制路径只产生 Saber stroke。

**Tech Stack:** Flutter/Dart、perfect_freehand、one_dollar_unistroke_recognizer、现有 FlowMuse editor_core、Saber GPLv3 源码。

---

## 执行约束

- 只修改 `FlowMuse-App` 内文件。
- 不新增测试文件。
- 不使用 worktree。
- 每个任务完成后运行指定验证命令，成功后单独提交。
- Flutter 命令必须用 `C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe` 直接调用，不使用 `.bat` 包装脚本。
- 每次提交只暂存本任务相关文件，避免混入无关改动。

通用验证命令：

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

说明：当前项目可能存在既有 analyzer warning/info；执行者必须区分新增 error 与既有 warning。debug APK 构建必须通过。

## 文件结构

新增目录：

- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/model/`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/rendering/`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/tools/`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/serialization/`
- `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/recognition/`

主要新增文件：

- `saber_ink/model/tool_id.dart`
- `saber_ink/model/stroke.dart`
- `saber_ink/model/circle_stroke.dart`
- `saber_ink/model/rectangle_stroke.dart`
- `saber_ink/model/laser_stroke.dart`
- `saber_ink/model/saber_ink_scene.dart`
- `saber_ink/model/saber_ink_metadata.dart`
- `saber_ink/serialization/stroke_options_codec.dart`
- `saber_ink/serialization/saber_stroke_codec.dart`
- `saber_ink/serialization/saber_ink_document.dart`
- `saber_ink/rendering/saber_ink_painter.dart`
- `saber_ink/rendering/saber_pencil_shader.dart`
- `saber_ink/tools/saber_pen_tool.dart`
- `saber_ink/tools/saber_shape_pen_tool.dart`
- `saber_ink/tools/saber_eraser_adapter.dart`
- `saber_ink/tools/saber_select_adapter.dart`
- `saber_ink/tools/saber_laser_tool.dart`
- `saber_ink/recognition/saber_ink_recognition_adapter.dart`
- `saber_ink/saber_ink.dart`

主要修改文件：

- `core/scene/scene.dart`
- `editor/editor_state.dart`
- `editor/tool_result.dart`
- `editor/tool_type.dart`
- `editor/tools/tool_factory.dart`
- `editor/tools/freedraw_tool.dart`
- `editor/tools/eraser_tool.dart`
- `editor/tools/select_tool.dart`
- `editor/tools/laser_tool.dart`
- `rendering/static_canvas_painter.dart`
- `ui/markdraw_controller.dart`
- `ui/desktop_toolbar.dart`
- `ui/compact_toolbar.dart`
- `ui/tool_icon.dart`
- `core/io/scene_document_converter.dart`
- `core/serialization/markdraw_document.dart`
- `core/serialization/document_serializer.dart`
- `core/serialization/document_parser.dart`
- `core/serialization/excalidraw_json_codec.dart`

主要删除或停止使用文件在最后阶段处理：

- `rendering/rough/saber_stroke_geometry.dart`
- `rendering/rough/freedraw_renderer.dart`
- `core/elements/freedraw_element.dart`
- 旧 `BrushType` 手写路径

---

### Task 1: 搬入 Saber ToolId 与基础 metadata

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/model/tool_id.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/model/saber_ink_metadata.dart`
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/saber_ink.dart`
- Modify: `FlowMuse-App/docs/third_party/saber.md`

- [ ] **Step 1: 创建 `ToolId`**

从 `D:\Github\FlowMuse\saber\packages\sbn\lib\tool_id.dart` 搬入必要枚举和解析逻辑。只保留 FlowMuse 需要的工具：

```dart
enum SaberToolId {
  fountainPen('fountainPen'),
  ballpointPen('ballpointPen'),
  pencil('pencil'),
  highlighter('highlighter'),
  shapePen('shapePen'),
  laserPointer('laserPointer');

  const SaberToolId(this.id);
  final String id;

  static SaberToolId parse(String? value, {SaberToolId fallback = SaberToolId.fountainPen}) {
    return switch (value) {
      'fountainPen' || 'fountain-pen' => SaberToolId.fountainPen,
      'ballpointPen' || 'ballpoint' => SaberToolId.ballpointPen,
      'pencil' => SaberToolId.pencil,
      'highlighter' => SaberToolId.highlighter,
      'shapePen' || 'shape-pen' => SaberToolId.shapePen,
      'laserPointer' || 'laser' => SaberToolId.laserPointer,
      _ => fallback,
    };
  }
}
```

- [ ] **Step 2: 创建 stroke metadata**

`SaberInkMetadata` 必须包含协作字段和识别字段：

```dart
class SaberInkMetadata {
  const SaberInkMetadata({
    required this.id,
    this.version = 1,
    this.versionNonce = 0,
    this.updated,
    this.index,
    this.isDeleted = false,
    this.customData,
  });

  final String id;
  final int version;
  final int versionNonce;
  final int? updated;
  final String? index;
  final bool isDeleted;
  final Map<String, Object?>? customData;
}
```

并实现 `copyWith`、`bumpVersion()`、`softDelete()`、`toJson()`、`fromJson()`。

- [ ] **Step 3: 创建 barrel export**

`saber_ink.dart` 导出 `model/tool_id.dart` 与 `model/saber_ink_metadata.dart`。

- [ ] **Step 4: 更新第三方说明**

在 `docs/third_party/saber.md` 增加本次迁移会直接搬入 `tool_id.dart` 和 stroke model 的说明。

- [ ] **Step 5: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
```

Expected:

- 无新增 error。
- 如果仅有既有 warning/info，记录在提交说明中。

- [ ] **Step 6: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/docs/third_party/saber.md
git commit -m "引入 Saber 工具标识和笔迹元数据"
```

---

### Task 2: 搬入 Saber Stroke 核心

**Files:**
- Create: `saber_ink/model/stroke.dart`
- Create: `saber_ink/model/circle_stroke.dart`
- Create: `saber_ink/model/rectangle_stroke.dart`
- Create: `saber_ink/model/laser_stroke.dart`
- Create: `saber_ink/serialization/stroke_options_codec.dart`
- Modify: `saber_ink/saber_ink.dart`

- [ ] **Step 1: 移植 StrokeOptions codec**

从 Saber `_stroke.dart` 使用的 `StrokeOptions.toJson/fromJson` 行为中抽取 FlowMuse codec。字段必须覆盖：

- `size`
- `thinning`
- `smoothing`
- `streamline`
- `simulatePressure`
- `isComplete`
- `start.taperEnabled`
- `start.customTaper`
- `end.taperEnabled`
- `end.customTaper`

如果 `perfect_freehand` 当前版本已经提供 `StrokeOptions.toJson/fromJson`，包装调用；否则显式读写 Map。

- [ ] **Step 2: 移植 `SaberStroke`**

从 `D:\Github\FlowMuse\saber\lib\components\canvas\_stroke.dart` 搬入核心行为并做 FlowMuse 适配：

- `points`
- `isEmpty`
- `length`
- `color`
- `pressureEnabled`
- `options`
- `toolId`
- `metadata`
- low/high polygon 缓存
- low/high path 缓存
- `shift`
- `markPolygonNeedsUpdating`
- `addPoint`
- `addPoints`
- `popFirstPoint`
- `optimisePoints`
- `getPolygon`
- `getPath`
- `skipPoints`
- `smoothPathFromPolygon`
- `detectShape`
- `isStraightLine`
- `convertToLine`
- `snapLine`
- `copy`

`pageIndex` 和 `page` 不搬入；FlowMuse 页面归属放入 metadata customData 或现有 layout customData。

- [ ] **Step 3: 保留 simulated pressure 固化**

`getPolygon(quality: high)` 必须保留 Saber 行为：

```dart
final rememberSimulatedPressure =
    quality == SaberStrokeQuality.high && options.simulatePressure && options.isComplete;
final polygon = getStroke(
  skipPoints(points, quality.skip),
  options: quality == SaberStrokeQuality.low
      ? options.copyWith(simulatePressure: false, smoothing: 0, streamline: 0)
      : options,
  rememberSimulatedPressure: rememberSimulatedPressure,
);
if (rememberSimulatedPressure) {
  options.simulatePressure = false;
  optimisePoints();
}
```

- [ ] **Step 4: 移植 shape strokes**

从 Saber `_circle_stroke.dart` 和 `_rectangle_stroke.dart` 搬入：

- `SaberCircleStroke`
- `SaberRectangleStroke`
- shape-specific fields
- shape-specific path rendering helper
- shape-specific json codec

- [ ] **Step 5: 移植 laser stroke**

从 Saber `laser_pointer.dart` 和 `_canvas_painter.dart` 搬入 laser 表现。`SaberLaserStroke` 必须提供：

- outer path
- inner path
- fade timestamp
- size/options
- prune/expired 判断

- [ ] **Step 6: 更新 barrel export**

`saber_ink.dart` 导出本任务新增文件。

- [ ] **Step 7: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
```

Expected: 无新增 error。

- [ ] **Step 8: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink
git commit -m "搬入 Saber 笔迹核心模型"
```

---

### Task 3: 引入 SaberInkScene 与 ink ToolResult

**Files:**
- Create: `saber_ink/model/saber_ink_scene.dart`
- Modify: `core/scene/scene.dart`
- Modify: `editor/tool_result.dart`
- Modify: `editor/editor_state.dart`

- [ ] **Step 1: 创建 `SaberInkScene`**

`SaberInkScene` 必须是不可变值对象，包含：

```dart
class SaberInkScene {
  const SaberInkScene({
    this.strokes = const [],
    this.laserStrokes = const [],
    this.currentStroke,
  });

  final List<SaberStroke> strokes;
  final List<SaberLaserStroke> laserStrokes;
  final SaberStroke? currentStroke;
}
```

实现：

- `activeStrokes`
- `orderedStrokes`
- `getStrokeById(String id)`
- `addStroke(SaberStroke stroke)`
- `updateStroke(SaberStroke stroke)`
- `softDeleteStroke(String id)`
- `removeLaserStroke(String id)`
- `setCurrentStroke(SaberStroke? stroke)`
- `setLaserStrokes(List<SaberLaserStroke> strokes)`

- [ ] **Step 2: 扩展 `Scene`**

在 `core/scene/scene.dart` 增加：

```dart
final SaberInkScene ink;
```

所有 `Scene._(...)`、`addElement`、`removeElement`、`updateElement`、`addFile`、`removeFile`、`withSmartLayout` 必须保留当前 `ink`。

- [ ] **Step 3: 新增 ink results**

在 `editor/tool_result.dart` 增加：

- `AddInkStrokeResult`
- `UpdateInkStrokeResult`
- `RemoveInkStrokeResult`
- `SetCurrentInkStrokeResult`
- `SetLaserStrokesResult`
- `SetInkSelectionResult`

如果当前 `selectedIds` 只能表达 `ElementId`，新增 `InkSelectionId` 或先用 `String` 集合单独存在于 `EditorState`。

- [ ] **Step 4: 扩展 `EditorState`**

在 `EditorState` 增加：

```dart
final Set<String> selectedInkStrokeIds;
```

`applyResult` 对 ink results 调用 `scene.copyWith(ink: ...)` 或 `scene.withInk(...)`。

- [ ] **Step 5: 更新 `isSceneChangingResult`**

ink add/update/remove 必须返回 true。current stroke 和 laser transient result 返回 false，避免污染 undo 栈。

- [ ] **Step 6: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
```

Expected: 无新增 error。

- [ ] **Step 7: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/core/scene/scene.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tool_result.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/editor_state.dart
git commit -m "让场景承载 Saber 笔迹集合"
```

---

### Task 4: 接入 SaberInkPainter

**Files:**
- Create: `saber_ink/rendering/saber_ink_painter.dart`
- Create: `saber_ink/rendering/saber_pencil_shader.dart`
- Modify: `rendering/static_canvas_painter.dart`
- Modify: `ui/editor_canvas.dart`
- Modify: `saber_ink/saber_ink.dart`

- [ ] **Step 1: 移植 pencil shader wrapper**

以当前 `rendering/rough/pencil_shader.dart` 和 Saber `components/canvas/pencil_shader.dart` 为基础，创建 `SaberPencilShader`。保留：

- shader availability
- shader create
- RGB float 传参
- mask blur 计算

- [ ] **Step 2: 创建 `SaberInkPainter`**

从 Saber `_canvas_painter.dart` 搬入手写渲染顺序。构造参数：

```dart
class SaberInkPainter {
  const SaberInkPainter({
    required this.ink,
    required this.currentScale,
    required this.primaryColor,
    required this.invert,
    required this.selectedStrokeIds,
  });
}
```

实现绘制方法：

- `draw(Canvas canvas, Rect canvasRect)`
- `_drawHighlighterStrokes`
- `_drawNonHighlighterStrokes`
- `_drawLaserStroke`
- `_drawCurrentStroke`
- `_drawDetectedShape`
- `_drawSelection`
- `_selectPath`
- `shouldUsePencilShader`

- [ ] **Step 3: 替换 `StaticCanvasPainter` 手写绘制入口**

在 `StaticCanvasPainter.paint` 中：

1. 页面、网格仍由 FlowMuse 画。
2. 非手写 element 仍走 `ElementRenderer`。
3. Saber ink 由 `SaberInkPainter.draw` 画。
4. 不再在 static layer 渲染 `FreedrawElement` 新路径。

- [ ] **Step 4: 接入 transient current stroke**

`editor_canvas.dart` 当前传 `previewElement` 和 laser trail。保留非手写 preview，同时把 `controller.editorState.scene.ink.currentStroke` 和 laser strokes 交给 `StaticCanvasPainter` 可访问的 `scene.ink`。

- [ ] **Step 5: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Expected:

- `analyze lib` 无新增 error。
- debug APK 构建成功。

- [ ] **Step 6: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/static_canvas_painter.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart
git commit -m "接入 Saber 笔迹渲染器"
```

---

### Task 5: 替换手写 Pen/Highlighter/ShapePen 工具

**Files:**
- Create: `saber_ink/tools/saber_pen_tool.dart`
- Create: `saber_ink/tools/saber_shape_pen_tool.dart`
- Modify: `editor/tools/freedraw_tool.dart`
- Modify: `editor/tools/tool_factory.dart`
- Modify: `ui/markdraw_controller.dart`
- Modify: `ui/desktop_toolbar.dart`
- Modify: `ui/compact_toolbar.dart`
- Modify: `ui/tool_icon.dart`
- Modify: `core/elements/brush_type.dart`

- [ ] **Step 1: 创建 Saber pen tool**

`SaberPenTool` 替代 `FreedrawTool` 的点采集，行为：

- pointer down 创建 `SaberStroke(options.copyWith(isComplete: false))`
- pointer move 调用 `addPoint`
- pointer up 设置 `options.isComplete = true`、`markPolygonNeedsUpdating`，返回 `AddInkStrokeResult`
- wet ink 通过 `SetCurrentInkStrokeResult` 更新
- pressureEnabled 按 tool id 决定

- [ ] **Step 2: 创建 Saber shape pen tool**

`SaberShapePenTool` 使用 Saber `ShapePen` 行为：

- move 时 debounce detect shape
- overlay 显示 detected shape
- up 时根据 `RecognizedUnistroke.name` 生成 line/rectangle/circle/polygon stroke
- line 使用 Saber `convertToLine`
- rectangle/circle 使用 one-dollar 的 `convertToRect/convertToCircle`
- triangle/star 使用 `convertToCanonicalPolygon`

- [ ] **Step 3: 让旧 `FreedrawTool` 委托给 Saber tool**

短期保留 `FreedrawTool` 文件名以减少外部引用变化，但内部根据 `ToolContext.saberToolId` 委托：

- shapePen -> `SaberShapePenTool`
- highlighter/pencil/ballpoint/fountainPen -> `SaberPenTool`

完成后新绘制路径不能再返回 `AddElementResult(FreedrawElement)`。

- [ ] **Step 4: 更新 controller tool context**

`ToolContext` 增加：

```dart
final SaberToolId saberToolId;
```

`MarkdrawController` 的当前笔状态切换到 Saber tool id。保留 UI 上的粗细、颜色、压感灵敏度，但写入 Saber `StrokeOptions`。

- [ ] **Step 5: 更新工具栏**

桌面和移动工具栏显示：

- 铅笔
- 圆珠笔
- 钢笔
- 荧光笔
- 形状笔

`BrushType` 只作为旧导入映射存在；UI 不再直接依赖 `BrushType.values`。

- [ ] **Step 6: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 新画钢笔/铅笔/圆珠笔/荧光笔时，scene 中增加 ink stroke，不增加 `FreedrawElement`。
- shapePen 识别成功时增加 Saber shape stroke。

- [ ] **Step 7: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/editor FlowMuse-App/lib/features/whiteboard/editor_core/src/ui FlowMuse-App/lib/features/whiteboard/editor_core/src/core/elements/brush_type.dart
git commit -m "用 Saber 工具替换手写输入"
```

---

### Task 6: 替换橡皮擦、选择和激光笔

**Files:**
- Create: `saber_ink/tools/saber_eraser_adapter.dart`
- Create: `saber_ink/tools/saber_select_adapter.dart`
- Create: `saber_ink/tools/saber_laser_tool.dart`
- Modify: `editor/tools/eraser_tool.dart`
- Modify: `editor/tools/select_tool.dart`
- Modify: `editor/tools/laser_tool.dart`
- Modify: `rendering/interactive/laser_renderer.dart`
- Modify: `ui/markdraw_controller.dart`

- [ ] **Step 1: 创建 eraser adapter**

`SaberEraserAdapter.hitTest` 使用 Saber low-quality path 和 polygon，返回 hit stroke ids。删除结果返回 `RemoveInkStrokeResult`，并保留现有 element 删除逻辑。

- [ ] **Step 2: 改造 `EraserTool`**

`EraserTool` 的 `_hitTestAndExpand` 先查 ink stroke，再查 element。拖动过程中 overlay 同时支持：

- `eraserElementIds`
- `eraserInkStrokeIds`

- [ ] **Step 3: 创建 select adapter**

`SaberSelectAdapter` 提供：

- point hit-test
- marquee selection percent
- selection path
- selected stroke highlight

`SelectTool` 保留 element 移动/resize/rotate 逻辑，但 selection set 同时维护 element ids 和 ink stroke ids。

- [ ] **Step 4: 替换 laser tool**

`LaserTool` 不再维护 `LaserPoint` 线段 trail；改为创建 `SaberLaserStroke`，move 时 add point，timer/prune 走 Saber stroke expiration。

- [ ] **Step 5: 删除旧 laser renderer 依赖**

`rendering/interactive/laser_renderer.dart` 停止被使用或改成兼容 wrapper，实际绘制由 `SaberInkPainter._drawLaserStroke` 完成。

- [ ] **Step 6: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 橡皮擦能删 ink stroke 和旧 element。
- 框选能选中 ink stroke 和 element。
- 激光笔显示 Saber 外光和 inner path，并自动淡出。

- [ ] **Step 7: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/editor/tools FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/interactive FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart
git commit -m "用 Saber 逻辑替换擦除选择和激光笔"
```

---

### Task 7: 序列化 FlowMuse-Saber 场景

**Files:**
- Create: `saber_ink/serialization/saber_stroke_codec.dart`
- Create: `saber_ink/serialization/saber_ink_document.dart`
- Modify: `core/serialization/markdraw_document.dart`
- Modify: `core/io/scene_document_converter.dart`
- Modify: `core/serialization/document_serializer.dart`
- Modify: `core/serialization/document_parser.dart`

- [ ] **Step 1: 创建 stroke codec**

`SaberStrokeCodec` 负责：

- `SaberStroke` to/from json
- `SaberCircleStroke` to/from json
- `SaberRectangleStroke` to/from json
- metadata to/from json
- options to/from json
- points to/from json

字段名明确为：

```json
{
  "id": "stroke-id",
  "type": "stroke",
  "toolId": "fountainPen",
  "points": [],
  "pressureEnabled": true,
  "color": "#1e1e1e",
  "options": {},
  "shape": null,
  "version": 1,
  "versionNonce": 0,
  "updated": 0,
  "index": "a0",
  "isDeleted": false,
  "customData": {}
}
```

- [ ] **Step 2: 扩展 MarkdrawDocument**

`MarkdrawDocument` 增加 `SaberInkDocument? ink` 或 `List<SaberStroke> inkStrokes`。序列化时输出 `ink` section，解析时读回。

- [ ] **Step 3: 更新 SceneDocumentConverter**

`sceneToDocument` 把 `scene.ink` 写入 document。`documentToScene` 把 document ink 写回 `Scene(ink: ...)`。

- [ ] **Step 4: 旧 FreedrawElement 导入转换**

在 `documentToScene` 处理旧 elements 时：

- 如果元素是 `FreedrawElement`，转换为 `SaberStroke` 并加入 `SaberInkScene`。
- 不把旧 `FreedrawElement` 添加回 scene elements。
- 旧 brush customData 映射到 `SaberToolId`。

- [ ] **Step 5: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 保存后重新加载，ink strokes 保留。
- 旧含 freedraw 的文档加载后，scene elements 不含 freedraw，scene ink 含 stroke。

- [ ] **Step 6: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/core/serialization FlowMuse-App/lib/features/whiteboard/editor_core/src/core/io/scene_document_converter.dart
git commit -m "序列化 Saber 笔迹场景"
```

---

### Task 8: Excalidraw 导入导出兼容层

**Files:**
- Modify: `core/serialization/excalidraw_json_codec.dart`
- Modify: `core/io/scene_document_converter.dart`
- Modify: `rendering/export/svg_element_renderer.dart`

- [ ] **Step 1: Excalidraw 导入 freedraw 到 Saber stroke**

解析 Excalidraw `freedraw` element 时：

- points -> `SaberStroke.points`
- pressures -> `PointVector.pressure`
- strokeColor -> stroke color
- strokeWidth -> options.size
- customData brushType -> `SaberToolId`

不再生成新的 `FreedrawElement`。

- [ ] **Step 2: Excalidraw 导出 Saber stroke**

导出时：

- 普通 stroke -> Excalidraw freedraw element
- `SaberRectangleStroke` -> rectangle element
- `SaberCircleStroke` -> ellipse element
- polygon shape stroke -> line closed element
- highlighter 保留 customData tool id

- [ ] **Step 3: 更新 SVG 导出**

SVG 导出遍历 scene elements 后追加 scene ink：

- 普通 stroke 用 high-quality polygon path
- rectangle/circle 用 shape path
- highlighter 用对应 opacity/blend 近似

- [ ] **Step 4: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- Excalidraw JSON 导入手写后可显示为 Saber stroke。
- FlowMuse 导出 Excalidraw JSON 后，外部 Excalidraw 能看到近似笔迹。
- SVG 导出包含 Saber ink。

- [ ] **Step 5: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/serialization/excalidraw_json_codec.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/core/io/scene_document_converter.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/export/svg_element_renderer.dart
git commit -m "兼容 Saber 笔迹的 Excalidraw 导入导出"
```

---

### Task 9: 接回文字识别

**Files:**
- Create: `saber_ink/recognition/saber_ink_recognition_adapter.dart`
- Modify: `ui/markdraw_controller.dart`
- Modify: `recognition/ink_recognition.dart`
- Modify: `saber_ink/tools/saber_pen_tool.dart`

- [ ] **Step 1: 创建 recognition adapter**

`SaberInkRecognitionAdapter` 提供：

- `isRecognitionStroke(SaberStroke stroke)`
- `sessionIdFor(SaberStroke stroke)`
- `requestFromStrokes(List<SaberStroke> strokes)`
- `clearPendingMetadata(SaberStroke stroke)`

请求点使用 `stroke.points`，时间使用 metadata 中的 `pointTimes`。

- [ ] **Step 2: 在 pen tool 写入识别 metadata**

当 `context.inkRecognitionMode == true` 且 tool id 不是 highlighter/shapePen/laser 时：

- 写入 session id
- 写入 pending flag
- 写入 startedAt
- 写入 pointTimes

- [ ] **Step 3: 更新 controller 调度**

把 `MarkdrawController._scheduleInkRecognitionFromResult` 从扫描 `FreedrawElement` 改为扫描 `AddInkStrokeResult/UpdateInkStrokeResult`。

- [ ] **Step 4: 识别结果写回**

保留现有识别结果应用逻辑：识别出的文字、公式、形状仍生成 FlowMuse 非手写 elements，并删除或软删除 pending ink strokes。

- [ ] **Step 5: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 开启文字识别后手写，能触发原 `onRecognizeInk`。
- 识别结果能生成文字元素。
- shapePen 不进入文字识别。

- [ ] **Step 6: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/recognition/ink_recognition.dart
git commit -m "接回 Saber 笔迹文字识别"
```

---

### Task 10: 协作 patch 适配 Saber ink

**Files:**
- Modify: `editor/tool_result.dart`
- Modify: `editor/editor_state.dart`
- Modify: `ui/markdraw_controller.dart`
- Search and modify current collaboration integration files found by:

```powershell
rg "applyRemote|serializeExcalidrawSceneJson|onSceneChanged|collab|remote" FlowMuse-App/lib -g "*.dart"
```

- [ ] **Step 1: 定位协作入口**

运行上面的 `rg` 命令，列出实际协作发送和接收文件。把这些文件加入本任务修改范围。

- [ ] **Step 2: 定义 WhiteboardPatch**

在合适的 editor/collaboration 文件中定义 patch 类型：

- `InkStrokeAdded`
- `InkStrokeUpdated`
- `InkStrokeDeleted`
- `InkStrokeReordered`
- `ElementAdded`
- `ElementUpdated`
- `ElementDeleted`
- `FileAdded`
- `FileRemoved`
- `SceneSettingsUpdated`

每个 ink patch 使用 `SaberStrokeCodec` 序列化 stroke。

- [ ] **Step 3: 发送端适配**

`onSceneChanged` 或现有协作发送端必须包含 `scene.ink`。如果当前协作只发送完整 Excalidraw JSON，先切换为完整 FlowMuse-Saber scene JSON；patch 增量随后在同一格式内表达。

- [ ] **Step 4: 接收端适配**

远端应用逻辑必须能：

- 添加 ink stroke
- 根据 `version/versionNonce/updated` 更新 ink stroke
- 软删除 ink stroke
- 保留 tombstone
- 不破坏 non-ink elements

- [ ] **Step 5: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 本地完整 scene 序列化包含 ink。
- 模拟远端 apply 后 ink strokes 出现在 scene。
- 删除 ink stroke 后 tombstone 保留。

- [ ] **Step 6: 提交**

```powershell
git add FlowMuse-App/lib/features/whiteboard/editor_core/src FlowMuse-App/lib
git commit -m "让协作同步支持 Saber 笔迹"
```

提交前必须运行：

```powershell
git diff --cached --name-only
```

确认没有混入无关文件。

---

### Task 11: 清理 markdraw 手写旧路径

**Files:**
- Delete or stop exporting:
  - `rendering/rough/saber_stroke_geometry.dart`
  - `rendering/rough/freedraw_renderer.dart`
- Modify:
  - `rendering/rough/rough_canvas_adapter.dart`
  - `rendering/rough/rough_adapter.dart`
  - `rendering/element_renderer.dart`
  - `core/elements/elements.dart`
  - `core/elements/freedraw_element.dart`
  - `core/elements/brush_type.dart`
  - `editor/tools/freedraw_tool.dart`
  - `editor/tools/tools.dart`

- [ ] **Step 1: 确认没有新路径引用 FreedrawElement**

Run:

```powershell
rg "FreedrawElement|drawFreedraw|FreedrawRenderer|SaberStrokeGeometry|BrushType" FlowMuse-App/lib/features/whiteboard/editor_core/src -g "*.dart"
```

Expected:

- 只允许旧文档导入转换器和兼容解析器引用 `FreedrawElement`。
- 新绘制、新渲染、新协作路径不得引用。

- [ ] **Step 2: 删除旧 renderer**

删除 `freedraw_renderer.dart` 和 `saber_stroke_geometry.dart`。从 `rough.dart` barrel export 移除它们。

- [ ] **Step 3: 移除 rough adapter freedraw API**

从 `RoughAdapter` 和 `RoughCanvasAdapter` 删除 `drawFreedraw`。`ElementRenderer` 不再渲染 `FreedrawElement`，旧导入已在转换层处理。

- [ ] **Step 4: 收缩 BrushType**

如果 `BrushType` 只剩旧转换用途，将其移动到 serialization compat 文件；UI 和工具层使用 `SaberToolId`。

- [ ] **Step 5: 保留旧导入最小兼容**

如果 parser 仍需要构造 `FreedrawElement` 作为中间结构，则把 `FreedrawElement` 标记为 `@Deprecated('Only used for legacy import conversion')`，并确保不会进入 scene。

- [ ] **Step 6: 验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual expected:

- 新建手写文档不产生 `FreedrawElement`。
- 旧文档导入能显示原手写。

- [ ] **Step 7: 提交**

```powershell
git add -A FlowMuse-App/lib/features/whiteboard/editor_core/src
git commit -m "清理旧 markdraw 手写路径"
```

---

### Task 12: 最终验证与文档收口

**Files:**
- Modify: `FlowMuse-App/docs/data-model.md`
- Modify: `FlowMuse-App/docs/architecture.md`
- Modify: `FlowMuse-App/docs/third_party/saber.md`

- [ ] **Step 1: 更新数据模型文档**

说明 FlowMuse scene v2：

- `ink.strokes`
- `elements`
- `files`
- `settings`
- 旧 freedraw 导入转换策略
- Excalidraw 导入导出兼容策略

- [ ] **Step 2: 更新架构文档**

说明 whiteboard editor core 的新分层：

- `saber_ink/model`
- `saber_ink/tools`
- `saber_ink/rendering`
- `saber_ink/serialization`
- `saber_ink/recognition`
- FlowMuse non-ink elements
- collaboration patch

- [ ] **Step 3: 更新第三方说明**

确认列出实际搬入的 Saber 文件和 GPLv3 来源。

- [ ] **Step 4: 全量验证**

Run:

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

Manual checklist:

- 钢笔、铅笔、圆珠笔、荧光笔、shapePen、laser 可绘制。
- 铅笔 zoom in/out 视觉切换符合 Saber。
- 荧光笔多颜色叠加符合 Saber。
- shapePen 线、矩形、圆、三角形、星形识别可用。
- 橡皮擦和选择框对手写 stroke 命中符合 Saber。
- 文字识别模式下，手写 stroke 能触发原识别回调并写回文字结果。
- 联机协作双方能同步新增、删除、更新 ink stroke。
- 旧文档中的 `FreedrawElement` 能导入并转换为 Saber stroke。
- Excalidraw 导入导出仍能处理手写近似元素。

- [ ] **Step 5: 提交**

```powershell
git add FlowMuse-App/docs/data-model.md FlowMuse-App/docs/architecture.md FlowMuse-App/docs/third_party/saber.md
git commit -m "更新 Saber 主模型迁移文档"
```

---

## Plan Self-Review

- Spec coverage: 规格中的 Saber stroke 主模型、渲染、工具替换、序列化、协作、文字识别、旧路径清理和文档更新均有对应任务。
- 占位内容扫描：本计划不包含未决项、空洞步骤或未定义的后续占位任务。
- Type consistency: 计划统一使用 `SaberToolId`、`SaberStroke`、`SaberInkScene`、`SaberStrokeCodec`、`AddInkStrokeResult` 等名称。
- Project constraints: 计划不新增测试、不使用 worktree、不触碰 `FlowMuse-App` 外文件。
