# Saber Stroke 主模型迁移设计

## 背景

FlowMuse 当前白板核心仍以 Excalidraw/markdraw 风格的 `Element` 模型为主，手写笔迹由 `FreedrawElement`、`FreedrawTool`、`FreedrawRenderer` 和 `RoughCanvasAdapter.drawFreedraw` 串起来。上一轮迁移已经把部分 Saber 笔形参数、shapePen 识别、激光笔视觉、高亮图层和笔迹命中逻辑接入现有模型，但这些实现仍然被 `FreedrawElement` 的数据结构限制，无法完整复刻 Saber 的运行时表现。

用户确认后，本次迁移目标调整为：FlowMuse 内部手写主模型切换为 Saber 的 `Stroke` 体系。允许修改现有数据结构，允许删除 markdraw 手写相关代码并用 Saber 代码替换；联机协作和文字识别功能必须接回新模型并保持可用。

## 目标

1. 手写、铅笔、圆珠笔、钢笔、荧光笔、形状笔、橡皮擦、选择命中和激光笔表现以 Saber 实现为准。
2. 手写主存储从 `FreedrawElement` 切换到 Saber 风格的 `Stroke`、`CircleStroke`、`RectangleStroke`、`LaserStroke`、`ToolId` 和 `StrokeOptions`。
3. FlowMuse 的联机协作继续可用，但同步 payload 改为支持 Saber stroke 变更。
4. FlowMuse 的文字识别继续可用，识别请求从 Saber stroke 点序列生成。
5. Excalidraw JSON 继续支持导入导出，但不再作为手写主模型。
6. 不新增测试文件，验证通过静态分析、debug APK 构建和手动功能路径完成。

## 非目标

1. 不迁移 Saber 的 Nextcloud、文件系统同步、Quill 文档编辑器壳、完整设置系统或整页笔记管理。
2. 不迁移 Saber `.sbn/.sbn2` 为 FlowMuse 的唯一文件格式；可以借鉴其 stroke JSON/BSON 字段，但 FlowMuse 需要自己的场景文档版本。
3. 不一次性重写 FlowMuse 的非手写元素能力，例如文字、图片、Frame、箭头、库面板、导出面板和协作 UI。
4. 不新增 CI/CD 或自动化测试。

## 架构选择

采用 **Saber Stroke 作为手写主模型，FlowMuse Element 作为非手写模型并存** 的过渡架构。

场景结构拆成两类内容：

- `SaberInkScene`：管理所有 Saber stroke，包括普通笔迹、形状笔生成的 stroke/圆/矩形、荧光笔和激光笔运行时轨迹。
- `FlowMuseElementScene`：继续管理文字、图片、Frame、箭头、页面背景、PDF 背景和其他非手写元素。

`Scene` 或新的 `WhiteboardScene` 聚合这两部分，并提供统一排序、选择、序列化、协作 patch 和导出接口。手写不再落到 `FreedrawElement`，但导入旧文档时会把旧 `FreedrawElement` 爆炸式转换成 Saber stroke。

## 核心模块

### Saber Ink Core

新增或搬入以下 Saber 代码到 `FlowMuse-App/lib/features/whiteboard/editor_core/src/saber_ink/`：

- `stroke.dart`：移植 Saber `_stroke.dart`，保留 `points`、low/high polygon/path 缓存、`rememberSimulatedPressure`、`optimisePoints`、`convertToLine`、`snapLine`、shape detection。
- `circle_stroke.dart`：移植 Saber `_circle_stroke.dart`，用于 shapePen 圆形识别结果。
- `rectangle_stroke.dart`：移植 Saber `_rectangle_stroke.dart`，用于 shapePen 矩形识别结果。
- `laser_stroke.dart`：移植 Saber laser stroke 表现，外发光和 inner path 以 Saber 为准。
- `tool_id.dart`：从 Saber `packages/sbn/lib/tool_id.dart` 移植必要枚举，不引入完整 sbn 包。
- `stroke_options_codec.dart`：封装 `perfect_freehand.StrokeOptions` 的序列化字段。
- `saber_ink_scene.dart`：持有 stroke 列表、运行时当前 stroke、低/高质量路径缓存失效、命中检测和排序。

### Saber Tools Adapter

新增 `src/saber_ink/tools/`：

- `saber_pen_tool.dart`：替代当前 `FreedrawTool` 的手写行为，按当前 `ToolId` 创建 Saber `Stroke`。
- `saber_shape_pen_tool.dart`：使用 Saber `ShapePen` 行为，拖动中支持识别预览，结束时使用 `convertToRect`、`convertToCircle`、`convertToCanonicalPolygon` 等 one-dollar 转换。
- `saber_eraser_tool.dart`：按 Saber 低质量 path/polygon 进行擦除命中。
- `saber_select_adapter.dart`：保留 FlowMuse 选择框、分组、移动框架等 UI 语义，但对 ink stroke 使用 Saber path 命中和选择比例。
- `saber_laser_tool.dart`：用 Saber laser stroke 运行时模型替代当前线段式激光轨迹。

这些工具仍通过 FlowMuse `ToolResult` 或其后继 patch 系统输出变更，不直接修改 controller 状态。

### Rendering

新增 `SaberInkPainter`，直接复刻 Saber `CanvasPainter` 的手写渲染顺序：

1. 先按颜色分层绘制 highlighter，使用 Saber 的 `darken/lighten` 逻辑。
2. 再绘制非 highlighter strokes。
3. 绘制 laser strokes。
4. 绘制 current stroke。
5. 绘制 shapePen detected shape preview。
6. 绘制 selection path。

FlowMuse `StaticCanvasPainter` 改为负责页面、网格、非手写元素和调用 `SaberInkPainter`。手写路径不再通过 `RoughCanvasAdapter.drawFreedraw`。

铅笔 shader 行为以 Saber 为准：

- 根据缩放阈值决定是否使用 shader。
- 使用 Saber mask blur。
- 缩放较低时使用 Saber 的快速近似色。

### Serialization

新增 FlowMuse-Saber 场景版本，例如：

```json
{
  "type": "flowmuse-scene",
  "version": 2,
  "ink": {
    "strokes": []
  },
  "elements": [],
  "files": {},
  "settings": {}
}
```

`ink.strokes` 使用 Saber stroke 字段语义，包括：

- stroke id
- tool id
- point list
- pressure enabled
- color
- stroke options
- shape type
- rect/circle/polygon shape data
- deleted/version/index metadata

旧 `FreedrawElement` 导入时一次性转换为 Saber stroke，不保留向后兼容运行时代码。Excalidraw 导出时把 Saber stroke 转成 Excalidraw freedraw/line/ellipse/rectangle 近似元素；导入 Excalidraw freedraw 时转成 Saber stroke。

### Collaboration

协作层改为同步 `WhiteboardPatch`：

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

Saber stroke 需要加入 FlowMuse 现有协作所需字段：

- `id`
- `version`
- `versionNonce`
- `updated`
- `index`
- `isDeleted`

冲突策略沿用 Excalidraw 风格的版本优先与软删除策略：同 id 变更按 `version/versionNonce/updated` 解析，删除保留 tombstone，排序使用 fractional index。

### 文字识别

文字识别保留现有 `InkRecognitionRequest` 和回调入口。当前识别模式下产生的 Saber stroke 在 `customData` 或 stroke metadata 中记录：

- recognition session id
- pending flag
- startedAt
- pointTimes

识别请求从 Saber `Stroke.points` 生成；识别完成后仍走现有结果应用流程，把识别出的文字或排版结果写入 FlowMuse 非手写元素。shapePen 不进入文字识别。

### UI

工具栏笔形以 Saber tool id 为准：

- pencil
- ballpoint
- fountainPen
- highlighter
- shapePen
- laserPointer
- eraser
- select

现有颜色、粗细、压感灵敏度控制保留，但状态存储绑定到 Saber tool option。当前 markdraw `BrushType` 最终删除或变成迁移期间的临时映射。

## 迁移阶段

### 阶段 1：Saber Ink Core 落地

复制并适配 Saber stroke 类型、tool id、stroke options codec、painter 依赖。FlowMuse 能在现有场景中持有并渲染 Saber strokes，但旧 `FreedrawElement` 暂时仍可存在。

### 阶段 2：手写工具替换

用 Saber 工具替换当前手写路径。新画出的笔迹只产生 Saber stroke，不再产生 `FreedrawElement`。文字识别从 Saber stroke 接回。shapePen、highlighter、laser 表现按 Saber 对齐。

### 阶段 3：场景与协作切主模型

引入 `WhiteboardScene` 或扩展现有 `Scene`，协作 payload 支持 ink patches，序列化格式升级。导入旧文档时把 `FreedrawElement` 爆炸式转换成 Saber stroke。

### 阶段 4：删除 markdraw 手写实现

删除或隔离以下旧手写实现：

- `FreedrawRenderer`
- `SaberStrokeGeometry` 临时桥接层
- `RoughCanvasAdapter.drawFreedraw`
- `FreedrawTool`
- `BrushType` 中仅为旧 freedraw 服务的逻辑
- `FreedrawElement` 的新增路径

非手写 element、导出、协作 UI 和文字识别 UI 保留。

## 验证方式

每个阶段完成后运行：

```powershell
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe analyze lib
C:\tools\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe C:\tools\flutter_ohos\bin\cache\flutter_tools.snapshot build apk --debug
```

手动检查路径：

1. 钢笔、铅笔、圆珠笔、荧光笔、shapePen、laser 可绘制。
2. 铅笔 zoom in/out 视觉切换符合 Saber。
3. 荧光笔多颜色叠加符合 Saber。
4. shapePen 线、矩形、圆、三角形、星形识别可用。
5. 橡皮擦和选择框对手写 stroke 命中符合 Saber。
6. 文字识别模式下，手写 stroke 能触发原识别回调并写回文字结果。
7. 联机协作双方能同步新增、删除、更新 ink stroke。
8. 旧文档中的 `FreedrawElement` 能被导入并转换为 Saber stroke。
9. Excalidraw 导入导出仍能处理手写近似元素。

## 已知风险

1. Saber 是 GPLv3，FlowMuse 已确认接受 GPLv3 代码进入项目；第三方说明必须继续保留。
2. 当前项目禁止新增测试，因此迁移需要依赖分阶段构建验证和人工流程验证。
3. 协作 payload 切换会影响远端兼容，必须一次性更新发送端和接收端。
4. 如果旧 `FreedrawElement` 与新 Saber stroke 长期共存，会形成双模型复杂度；阶段 4 必须清掉旧手写路径。
5. 当前仓库可能存在未提交的其他功能改动，实施时必须只暂存本迁移相关文件。
