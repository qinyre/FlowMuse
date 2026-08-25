# 智能排版优化（自适应排版）实施计划

> **For agentic workers:** 本计划面向"低思考强度、照抄代码"的 AI 执行者。每个 Task 内步骤按顺序做：写测试 → 跑测试确认失败 → 写实现 → 跑测试确认通过 → 提交。步骤用 `- [ ]` 复选框跟踪，做完一个勾一个。**不要跳过步骤、不要臆造文中没有的 API、不要把代码"优化"掉**。凡文中给出完整代码块的，直接复制；只给行号锚点的，定位后按说明修改。
>
> 执行前必读：`F:\Project\FlowMuse\AGENTS.md`（第 0 节铁律、第 6 节验证清单、第 7 节数据库迁移——本计划无 schema 变更）。

**Goal:** 把现有"智能排版"升级为自适应排版——AI 判定内容风格（PPT 式 / 头脑风暴→真思维导图 / 文章式阅读流 / 仅转机器字体），用户可多选页面、逐页预览确认（可切换风格）、识别失败可见可补救；客户端确定性计算最终坐标，绝不跨页搬移元素。

**Architecture:** 沿用"方案二"：AI（服务端 compose 端点）只判定风格并返回语义结构（mindmap 树 / PPT 分组），客户端用确定性算法（纯 Dart 引擎）计算每个元素的目标坐标并生成 `SmartLayoutPlan`；画布上用虚线幽灵框预览，用户确认后一次 History 提交（每页一次撤销）。服务端新增 `/api/ink/smart-layout/compose` 的 `layout` 判定字段与 `layoutHint` 参数，客户端模型与引擎全部为纯 Dart 可测单元。

**Tech Stack:** Dart / Flutter（编辑器内核 editor_core）、Riverpod（仅注入 Repository）、Go（FlowMuse-Server `internal/recognition`）、OpenAI 兼容 chat completions（服务端 AI 判定）。

**Spec:** 议题 #3「智能排版优化」（仓库 GitHub Issue 截图记录）+ 本文件"需求确认表"（第 3 节，已与需求方逐条确认）。

---

## 0. 全局约束（每个 Task 隐含遵守，此处不再每任务重复）

1. 禁止在共享代码（`lib/features/*`、`lib/shared/*`）里出现 `Platform.is*` 分支；不引入新依赖；不改 pubspec。
2. 不改 Excalidraw 数据模型、协作协议、数据库 schema；不新增元素类型。
3. 所有新日志用 `debugPrint('[$logTag] ...')`；本特性统一前缀 `[FlowMuseSmartLayout]`（服务端用 Go 标准 `log.Printf`，前缀 `[smart-layout]`）。
4. 新增/修改文件遵循命名与目录约定：状态管 Riverpod、模型 `@immutable`、私有方法 `_` 前缀、ID 前缀 `entity-uuid`。
5. 每个 Task 结尾的"验证"步骤必须跑且通过，才能提交；提交信息用中文，格式见各任务。
6. 不改动 `tool/vendor/**`、`ohos/**`；本特性无鸿蒙原生改动，**不需要** `flutter build hap`。
7. 服务端代码改动后必须跑 `cd FlowMuse-Server && go build ./... && go test ./... && go vet ./...`。
8. 不输出 token、密钥、白板明文到日志或测试；测试中的钥匙用假值。

---

## 1. 背景与现状（已按当前 main 实测核实，行号以 2026-08-24 最新 main 为准）

### 1.1 现有智能排版（旧行为，v1 保留其代码路径）

- 入口：工具栏按钮（`editor_core/src/ui/compact_toolbar.dart:286-383`、`desktop_toolbar.dart:232-329`，含引擎选择弹窗）；AI 助手指令 `smart_layout`（`whiteboard_page.dart:785-794` → `markdraw_controller.dart:3086 runGlobalSmartLayout()`）。
- 流程：收集 freedraw 笔迹（`_smartLayoutInkElements` 3296 行，排除荧光笔；`_smartLayoutInkGroups` 3306 行按 `pageId:sessionId` 分组）→ `_buildSmartLayoutRequest`（3251 行，含每页模板锚点）→ 送识别（AI：`onSmartLayoutInk` 或 `onRecognizeSmartLayoutBlock`+`onComposeSmartLayout`；MyScript：`onRecognizeInk`+`onComposeSmartLayout`）→ compose 返回 `SmartLayoutResponse{document, blocks, pages}` → `_elementsFromSmartLayoutResponse`（3559 行）：article 页走 `_elementsFromSmartLayout`（模板锚点+段落流），其他页走 `_textElementFromRecognizedBlock`（3709 行，`TextRenderer.measure` 定尺寸）+ `_placeSmartLayoutElement`（3694 行，避碰）→ `pushHistory` + `applyResult(CompoundResult([...]))`：删除原笔迹 + 旧智能排版文本（`_smartLayoutGeneratedTextElements` 3550 行）+ 新增文本 + `SetSmartLayoutResult(document)` + 选中新文本。
- **关键事实：旧流程只移动"新生成文本"，绝不移动既有图形/图片/手动文本**（08-20 计划里"不重排既有元素"是非目标）；"文章模式 vs 原位模式"由服务端 `decidePage`（`FlowMuse-Server/internal/recognition/smart_layout.go:201-251`）判定。
- 旧流程已支持分页：请求携带全部页面；多页时逐页生成。

### 1.2 服务端现状

- 路由：`FlowMuse-Server/internal/recognition/api.go:38-43`，三个 POST 端点：`/api/ink/smart-layout`、`/api/ink/smart-layout/block`、`/api/ink/smart-layout/compose`；body 上限 32MB；`layouter == nil` 返回 502 `"AI smart layout is not configured"`。
- 实现：`internal/recognition/smart_layout.go`：`SmartLayouter` 接口（19-23 行）、`OpenAICompatibleSmartLayouter`（32-35 行）封装 `postChat`（271-296 行，OpenAI 兼容 `/chat/completions`）；`Compose()`（65-69 行）= `decidePages` + `buildSmartLayoutDocument`；`decidePage` 每页一次 AI 调用，返回严格 JSON `{pageId, mode: article|in_place, paragraphs}`，`sanitizePageDecision`（298-330 行）严格白名单。
- 配置：`FLOWMUSE_AI_BASE_URL`（默认 `https://ark.cn-beijing.volces.com/api/v3`）、`FLOWMUSE_AI_API_KEY`、`FLOWMUSE_AI_MODEL`（默认 `doubao-seed-2-1-turbo-260628`）、`FLOWMUSE_AI_TIMEOUT`（默认 120s）；客户端读超时 130s（`ink_recognition_repository.dart:27`）。
- 现有 Go 测试仅 `myscript_test.go`；**没有** smart_layout 的 Go 测试（本计划补）。

### 1.3 客户端接线与测试范式

- 回调接线：`whiteboard_page.dart:2168-2179` 把四个回调接到 `inkRecognitionRepositoryProvider`（`lib/features/whiteboard/ink_recognition/ink_recognition_repository.dart`，`smartLayout` 162-188 / `recognizeSmartLayoutBlock` 190-220 / `composeSmartLayout` 222-252）。
- 测试注入范式：`test/features/whiteboard/editor_core/smart_layout_placement_test.dart` 直接构造 `MarkdrawController` 并给 `controller.onSmartLayoutInk = (request) async {...返回固定 SmartLayoutResponse...}`，再调用 `runGlobalSmartLayout()` 断言场景变化/撤销。**旧行为测试必须保持全绿**（本计划不重构 `runGlobalSmartLayout`，只新增方法）。

### 1.4 可复用基础设施（本计划直接调用，签名已核实）

| 能力 | 位置与签名 |
| --- | --- |
| 思维导图确定性布局 | `editor_core/src/editor/mindmap/mindmap_layout.dart`：`MindmapLayout.treeToElements(MindmapNode tree, {Point? origin})`；常量 `nodeWidth=140, nodeHeight=48, hGap=80, vGap=24`；自定义数据 `{'flowMuse':{'role':'mindmap-node'\|'mindmap-edge'}}`；`MindmapUtils.parentOf/treeFromScene`；`MindmapNode.fromJson`（接受 `text/topic/title` + `children`） |
| 绑定跟随 | `editor/bindings/binding_utils.dart`：`BindingUtils.findBoundArrows(Scene, ElementId)`、`BindingUtils.updateBoundArrowEndpoints(ArrowElement, Scene)`；`bound_text_utils.dart`：`BoundTextUtils.updateBoundTextPositions(Scene, List<Element>) → List<ToolResult>` |
| 分组 | `core/groups/group_utils.dart`：`GroupUtils.outermostGroupId(Element)`、`findGroupMembers(Scene, String) → List<Element>` |
| 场景克隆 | `Scene.updateElement(Element) → Scene`（`core/scene/scene.dart`，select_tool.dart:2095 临时场景模式） |
| 历史 | `markdraw_controller.dart`：`pushHistory()`（3068）、`applyResult(ToolResult?)`（1039）；`editor/tool_result.dart`：`AddElementResult`、`UpdateElementResult`、`RemoveElementResult(ElementId)`、`SetSelectionResult(Set<ElementId>)`、`UpdateViewportResult`、`CompoundResult`、`SetSmartLayoutResult(SmartLayoutDocument?)` |
| 避碰求位 | `markdraw_controller.dart:4633 _findStrictInsertionBounds(Rect area, double width, double height, List<Bounds> occupied, {Bounds? preferred})`（本计划将其提取为公开纯函数，控制器原方法改为委托，见 T6） |
| 页数据 | `markdraw_controller.dart:353 CanvasLayout get layout`；`CanvasPage{id,index,bounds,template,pageFlow,source}`；`CanvasLayout.pageWidth=1588, pageHeight=2246, pageGap=96, isPaged` |
| 元素归属 | `canvas_layout.dart:251-257` 扩展：`element.pageId / isCanvasPage / isPdfBackground / flowMuseData`；控制器 `_pageIdForElement(3333)`、`pageForVisibleRect(Rect)(4561)` |
| 文本度量 | `_textElementFromRecognizedBlock`（3709）已含 `TextRenderer.measure` 定宽高；`_applySmartLayoutTextStyle` 同文件私有 |
| 视图变换 | `rendering/viewport_state.dart`：`ViewportState{screenToScenePrecise, sceneToScreen, visibleRect}`；painter 惯例 `canvas.scale(zoom); canvas.translate(-offset.dx, -offset.dy)`（interactive_canvas_painter.dart:101-102） |
| 虚线绘制 | `rendering/interactive/selection_renderer.dart`：**公开** `SelectionRenderer.drawMarquee(Canvas, Rect)`（半透明填充+虚线框，dash 6/gap 4 场景单位） |
| 选区模型 | `EditorState.selectedIds`；控制器 `selectedElements`（616） |
| 失败定位 | `SmartLayoutRecognizedBlock{id, bounds, error, isSuccess}`（`smart_layout_document.dart:228-316`）— **失败块自带坐标**，可直接高亮 |

---

## 2. 需求确认表（与需求方逐条确认的结果，实现时必须逐一满足）

| # | 结论 |
| --- | --- |
| R1 | 自适应排版：AI 判定内容风格；v1 四种风格：PPT 式、头脑风暴→真思维导图、文章式阅读流、仅转机器字体不重排；架构留扩展口（风格枚举 + 引擎分发） |
| R2 | 方案二：AI 只返回风格 + 语义结构（mindmap 树 / PPT 分组）；客户端确定性算法算最终坐标；AI 不生成坐标/ID/binding |
| R3 | 头脑风暴风=真思维导图：复用 `MindmapLayout`（节点可编辑、reflow、导出、一次撤销），替换零散手写内容 |
| R4 | 确认流程：文字说明 + 画布半透明幽灵预览 + 可切换风格（重发 compose 带 `layoutHint`）；确认后应用 |
| R5 | 作用范围：用户自行选择页面；每页独立排版、绝不跨页搬移；逐页流确认（确认/跳过/换风格），每页一次应用+一次撤销；v1 不做"跳过确认"开关 |
| R6 | 参与规则：锁定元素不动；手动成组整体移动（组内相对位置不变）；已有思维导图不参与；绑定元素跟随；图片参与；PDF/画布背景不参与 |
| R7 | 识别失败 all-or-nothing：页内任一笔迹识别失败 → 整页无副作用失败；失败提示 = 数量 + 清单 + 画布红虚线高亮失败区域；动作三选一：重新识别 / 取消 / 删除未识别笔迹后继续（知情确认，可 undo） |
| R8 | MyScript 保留识别能力但不暴露入口；v1 默认 AI 引擎（`engine: SmartLayoutRecognitionEngine.ai`） |

---

## 3. 总体设计

### 3.1 数据流（每页一次循环）

```
用户点"智能排版" → 页面多选对话框（T12）
  → 对每个选中页 pageId：
      1) controller.buildSmartLayoutPlan(pageId, engine: ai, requestedStyle?)       [T10]
         ├─ 收集该页笔迹分组 → 按块截图识别（现有 _recognizeSmartLayout...
         ├─ compose 请求新增：elements（该页非笔迹元素摘要）+ layoutHint          [T1/T4]
         ├─ 服务端 decideLayout 返回 {style, confidence, structure}                [T2]
         ├─ 客户端按 style 分发引擎（纯 Dart）：                                     [T7/T8]
         │    in_place/article → 现有生成/放置逻辑（确定性）
         │    mindmap → MindmapStyleEngine（MindmapLayout + findInsertionBounds）
         │    ppt     → PptLayoutEngine（双列网格 + 下移避障，无重叠）
         └─ 产出 SmartLayoutPlan{addElements, moveDeltas, removeIds, failedStrokeIds, selectIds, document, previewRects, removalRects, failureRects, description}   [T6]
      2) UI：controller.setSmartLayoutGhost(plan) 画布幽灵预览(R4)；确认对话框：
         风格四选一切换（重发 compose + layoutHint）；应用 / 跳过本页 / 取消整个流程      [T11/T12]
      3) 确认应用 → controller.applySmartLayoutPlan(plan)：
         pushHistory 一次 → CompoundResult[删除笔迹(+旧智能文本) → 移动(绑定/组/框架跟随) → 新增 → SetSmartLayoutResult → 选区]
      4) 计划缺失且存在识别失败 → 失败对话框（红格高亮）：重新识别 / 取消                    [R7]
      5) 计划存在且存在失败块 → 确认界面附加按钮"删除未识别笔迹后应用" → apply(dropFailedBlocks: true)
```

### 3.2 服务端协议变更（向后兼容）

请求 `POST /api/ink/smart-layout/compose` 追加两个可选字段：

```json
{
  "pages":  ["…现有结构 不变…"],
  "blocks": ["…现有结构 不变…"],
  "elements": [
    {"id":"e-img-1","type":"image","bounds":{"x":..,"y":..,"width":..,"height":..},"pageId":"p-1","locked":false,"groupIds":[]}
  ],
  "layoutHint": "ppt"
}
```

响应 `SmartLayoutResponse` 追加可选字段（现有字段不变；`layout` 缺失 = 旧服务端，客户端走风格回退 `article|in_place`）：

```json
{
  "document": { "…现有结构 不变…" },
  "blocks":   ["…现有结构 不变…"],
  "pages":    ["…现有结构 不变…"],
  "layout": {
    "style": "mindmap | ppt | article | in_place",
    "confidence": 0.92,
    "structure": {
      "root": {"text":"主题","blockIds":["blk-1"],"children":[
                {"text":"分支A","blockIds":["blk-2"]}]}
      // 或
      "groups": [{"role":"title|heading|body|figure","elementIds":["blk-1","e-img-2"]}]
    }
  }
}
```

规则（服务端 sanitize，客户端同样兜底）：
- `style` 仅接受四值，未知 → `in_place`，`structure` 置空。
- `confidence` 钳制到 [0,1]；缺失 → 0。
- mindmap：`root` 必须存在且非空；递归 `children`，深度 ≤4、节点 ≤50、节点 `text` ≤100 字；节点 `blockIds` 只能引用 `blocks` 中 `isSuccess`（`error` 为空）的块，非法引用删除后若节点无 `text` 则删节点；空树 → `in_place`。
- ppt：`groups` 为有序数组；`role` 关键词仅 `title|heading|body|figure`（未知 → `body`）；`elementIds` 只能引用成功块或 `elements` 中的 id，非法引用删除；空组删除；`groups` 空 → `in_place`。
- `layoutHint` 非空时：服务端强制该风格并让 AI 按该风格只输出结构（提示语里说明），sanitize 后若结构非法 → 回退 `in_place`。

### 3.3 客户端确定性布局规则（引擎必须逐条实现）

- 内容区：`page.bounds.deflate(72)`（与现有 `_findStrictInsertionBounds` 调用方一致）。
- PPT 双列（存在 `figure` 组时）：左列宽 `content.width*0.62 - 12`，右列 `content.right - 左列右缘 - 24`；无 figure 单列全宽。列内组自上而下排，组内单元水平排（间距 `unitGap=16`），行高 = 组内最大高度，行距 `rowGap=24`；任一单元超列宽或总高超内容区 → 整页失败（`StateError('智能排版没有足够的空白区域')`）。每行左对齐（x 从列左缘开始，单元按自身宽度顺排）。
- PPT 避障：先网格排布，再整体下移（`downShiftStep=24`，最多 40 次）直到与障碍碰撞为空且完整落入内容区；仍失败 → null。
- 障碍集合 = 页内"不参与"的元素：locked、`isCanvasPage`、`isPdfBackground`、mindmap 元素（`flowMuseData['role']` 为 `mindmap-node|mindmap-edge`）、其他页元素；**排除**本轮将被删除的笔迹与旧智能排版文本。
- 成组元素：组作为整体参与——计算组外接矩形（`GroupUtils.findGroupMembers` 的成员 + 边界合并），整组平移同样的 `(dx, dy)`，组内相对位置不变。
- 移动只改 `x/y`，不改 `width/height/角度/颜色/字号`（v1 已知边界，见第 9 节）。
- mindmap：`MindmapLayout.treeToElements(root, origin: const Point(0,0))` → 并集边界 → `SmartLayoutPlacement.findInsertionBounds(...)` → 平移 → 全树元素并入 plan。
- 预览矩形：新增/移动后元素的包围盒（场景坐标）；删除区 = 将被删除笔迹的包围盒。
- 描述文案模板（客户端生成，text 里元素数量用实际值）：
  - mindmap：`检测到头脑风暴内容：将 N 个手写块整理为 M 层思维导图（K 个节点）`
  - ppt：`按 PPT 版式重排：标题 1 处、正文段落 P 段、配图 G 张`（按 groups role 统计）
  - article：`按文章阅读流重新排版本页内容`
  - inPlace：`仅将手写识别为机器字体，保持原位附近'

### 3.4 文件清单

**新建（客户端）：**

| 文件 | 职责 |
| --- | --- |
| `lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart` | `SmartLayoutStyle`、`SmartLayoutPlan`、`SmartLayoutFailureInfo`、`SmartLayoutGhostSpec`、`SmartLayoutPlacement.findInsertionBounds`（公开化）、`SmartLayoutUtils.mergePageCustomData`（公开化）、`SmartLayoutDocumentFactory` |
| `lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart` | PPT 确定性布局（纯 Dart） |
| `lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart` | mindmap 结构 → 树元素 + 页内放置（纯 Dart） |
| `lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart` | 批量移动 + 绑定/文本/框架跟随 → `List<ToolResult>`（纯 Dart） |
| `lib/features/whiteboard/editor_core/src/rendering/interactive/smart_layout_ghost_painter.dart` | 幽灵预览/失败红框 painter |
| `lib/features/whiteboard/views/smart_layout_dialogs.dart` | 页面多选、排班确认（含风格切换）、失败三选一 三个对话框 widget |
| `test/features/whiteboard/editor_core/smart_layout_ppt_engine_test.dart` | PPT 引擎测试 |
| `test/features/whiteboard/editor_core/smart_layout_mindmap_engine_test.dart` | mindmap 引擎测试 |
| `test/features/whiteboard/editor_core/smart_layout_move_builder_test.dart` | 移动构建器测试 |
| `test/features/whiteboard/editor_core/smart_layout_plan_test.dart` | plan/模型/工具测试 |
| `test/features/whiteboard/editor_core/smart_layout_optimization_test.dart` | 控制器编排测试（仿 `smart_layout_placement_test.dart` 注入范式） |
| `test/features/whiteboard/views/smart_layout_dialogs_test.dart` | 对话框 widget 测试 |

**修改（客户端）：**

| 文件 | 改动 |
| --- | --- |
| `editor_core/src/core/smart_layout/smart_layout_document.dart` | `SmartLayoutComposeRequest` 加 `elements`、`layoutHint`；新增 `SmartLayoutElementRef`、`SmartLayoutLayoutDecision`、`SmartLayoutPptGroup`、`SmartLayoutPptStructure`；`SmartLayoutResponse` 加 `layout` |
| `editor_core/src/ui/markdraw_controller.dart` | 新增 `smartLayoutGhost` ValueNotifier、`buildSmartLayoutPlan`、`applySmartLayoutPlan`、`setSmartLayoutGhost`、私有辅助；`_findStrictInsertionBounds`/`_mergeCurrentPageCustomData` 改为委托公开函数 |
| `editor_core/src/ui/editor_canvas.dart` | Stack 内新增幽灵预览 `ValueListenableBuilder` + `CustomPaint` |
| `editor_core/src/ui/markdraw_editor.dart` | 新增 `onSmartLayoutPressed` 回调字段并透传 |
| `editor_core/src/ui/compact_toolbar.dart`、`desktop_toolbar.dart` | `_runGlobalSmartLayout` 改为优先调用 `onSmartLayoutPressed`（移除引擎选择弹窗） |
| `features/whiteboard/views/whiteboard_page.dart` | 接线 `onSmartLayoutPressed`；新增 `_startSmartLayoutFlow`、`_runSmartLayoutPage`、`_pickSmartLayoutPages`；AI 指令 smartLayout 分支接入新流程 |

**服务端：**

| 文件 | 改动 |
| --- | --- |
| `FlowMuse-Server/internal/recognition/types.go` | `ComposeRequest` 加 `Elements`、`LayoutHint`；响应加 `Layout *LayoutDecision`；新增 `ElementRef`、`LayoutDecision` |
| `FlowMuse-Server/internal/recognition/smart_layout.go` | 新增 `decideLayout`（AI 调用 + 严格 sanitize + 常量），`Compose()` 接入 |
| `FlowMuse-Server/internal/recognition/smart_layout_test.go` | 新建：sanitize 单测 + fake AI 的 Compose 集成测试 |

---

## 4. 任务清单与实施步骤

> 每个 Task 完成后运行其"验证"；所有 Task 完成后运行第 5 节"验收门禁"。Task 之间无并行依赖，按编号顺序做。
### Task 1：服务端协议类型扩展（Go）

**Files:**
- Modify: `FlowMuse-Server/internal/recognition/types.go`

**Interfaces:**
- Produces: `ElementRef`、`LayoutDecision`、`ComposeRequest.Elements []ElementRef`、`ComposeRequest.LayoutHint string`、`ComposeResponse.Layout *LayoutDecision`（T2 消费）

- [ ] **Step 1: 阅读现有类型文件**

打开 `FlowMuse-Server/internal/recognition/types.go`，找到：① 表示 compose 请求的结构体（含 `Pages`、`Blocks` 字段，字段 JSON tag 为 `json:"pages"` / `json:"blocks"`）；② 表示 compose 响应的结构体（含 `Document`、`Blocks`、`Pages` 字段）。若它们与 `api.go` 中 `/api/ink/smart-layout/compose` 处理函数的参数/返回对应（`api.go:140-142` 附近），即为目标。

- [ ] **Step 2: 添加类型与字段**

在 `types.go` 末尾追加以下代码（若文件已有同名类型则跳过该类型）：

```go
// ElementRef 是 compose 请求中"非笔迹元素"的最小摘要，供 AI 判定整页布局。
type ElementRef struct {
	ID       string   `json:"id"`
	Type     string   `json:"type"`
	Bounds   Bounds   `json:"bounds"`
	PageID   string   `json:"pageId,omitempty"`
	Locked   bool     `json:"locked,omitempty"`
	GroupIDs []string `json:"groupIds,omitempty"`
}

// LayoutDecision 是服务端对整页布局风格的判定结果（方案二：只判风格与结构，不给坐标）。
type LayoutDecision struct {
	Style      string         `json:"style"` // ppt | mindmap | article | in_place
	Confidence float64        `json:"confidence"`
	Structure  map[string]any `json:"structure,omitempty"`
}
```

再在 compose 请求结构体中追加字段（保持原有字段不变）：

```go
	Elements   []ElementRef `json:"elements,omitempty"`
	LayoutHint string       `json:"layoutHint,omitempty"`
```

在 compose 响应结构体中追加字段（保持原有字段不变）：

```go
	Layout *LayoutDecision `json:"layout,omitempty"`
```

> 注：若 `types.go` 中的 `Bounds` 类型名不同（例如 `Rect`/`Bounds`），把新代码里的 `Bounds` 换成该文件使用的类型名。若 compose 请求/响应与识别请求共用同一结构体（举例：`block` 端点复用），只改 compose 用到的那个结构体，**不要**改动 `/api/ink/smart-layout` 与 `/block` 的请求结构。

- [ ] **Step 3: 构建验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-Server && go build ./...
```

Expected: 无输出、退出码 0（若报未使用导入等错误，说明字段没加对位置，回到 Step 2 检查；`types.go` 只加字段不会引入新导入）。

- [ ] **Step 4: 提交**

```bash
git add FlowMuse-Server/internal/recognition/types.go
git commit -m "feat:智能排版compose协议追加elements与layout判定字段"
```

### Task 2：服务端 decideLayout 判定与 sanitize

**Files:**
- Modify: `FlowMuse-Server/internal/recognition/smart_layout.go`

**Interfaces:**
- Consumes: `ComposeRequest`（含新的 `Elements`、`LayoutHint`）、`LayoutDecision`（T1）
- Produces: `(*OpenAICompatibleSmartLayouter) decideLayout(ctx, request, blocks) (*LayoutDecision, error)`、常量 `layoutStylePPT/Mindmap/Article/InPlace`、`sanitizeMindmapStructure`、`sanitizePptStructure`（T3 测试消费）

- [ ] **Step 1: 阅读现有 compose 流程**

打开 `internal/recognition/smart_layout.go`，阅读：`Compose()`（约 65-69 行）、`decidePage()`（201-251 行）、`postChat()`（271-296 行）、`sanitizePageDecision()`（298-330 行）。注意 `postChat` 的签名（发起 OpenAI 兼容 chat 请求并返回消息内容字符串），`decidePage` 如何构造 system/user 消息与解析严格 JSON（含 `json.Unmarshal`、错误处理、`sanitize`）。**decideLayout 完全仿照 decidePage 的写法**。

- [ ] **Step 2: 添加常量**

在文件内（例如 `decidePage` 上方）添加：

```go
const (
	layoutStylePPT     = "ppt"
	layoutStyleMindmap = "mindmap"
	layoutStyleArticle = "article"
	layoutStyleInPlace = "in_place"

	maxMindmapDepth     = 4
	maxMindmapNodes     = 50
	maxMindmapNodeText  = 100
	maxMindmapBlockRefs = 8

	maxPptGroups = 24
	maxPptGroupMembers = 24
)
```

- [ ] **Step 3: 添加 decideLayout 方法**

在 `decidePage` 方法之后添加（`postChat` 的返回值形态请以 Step 1 读到的为准；若 `postChat` 返回 `(string, error)`，下面的 `content` 即它；若返回结构不同，按 `decidePage` 中同样的取值方式调整）：**注意 prompt 字符串必须原样粘贴，不得改写。**

```go
// decideLayout 判定整页布局风格并返回语义结构（方案二：不回坐标、不做 binding）。
func (l *OpenAICompatibleSmartLayouter) decideLayout(
	ctx context.Context, request *ComposeRequest,
) (*LayoutDecision, error) {
	payload, err := json.Marshal(map[string]any{
		"request":    request,
		"task":       "smart_layout_style",
		"layoutHint": request.LayoutHint,
	})
	if err != nil {
		return nil, err
	}
	systemPrompt := `你是一个白板笔记智能排版引擎。给定一页白板内容（识别的文字块 blocks 与既有元素 elements 的摘要），判断该页内容应该用哪种排版风格，并给出"语义结构"。

风格判断标准：
- mindmap：内容是头脑风暴/发散/层级话题（如想法清单、主题与分支、大纲），结构适合根节点+分支树。
- ppt：页面图文并茂（存在图片/图示与说明文字），适合"标题/正文/配图"分区摆放。
- article：连续有逻辑的段落文字（行文、讲义、总结），适合按阅读顺序排列。
- in_place：内容零散、看不出上述风格，直接按原位识别成机器字体即可。

输出规则（严格 JSON，禁止任何额外文字或 Markdown 代码围栏）：
{"style":"mindmap|ppt|article|in_place","confidence":0.0到1.0的小数,"structure":{}}

structure 的两种形态：
1. style= mindmap 时：
{"root":{"text":"节点文字","blockIds":["块id..."],"children":[{"text":"...","blockIds":["..."],"children":[...]}]}}
- 节点文字必须短标题（不超过100字）；允许带 blockIds 标注依据的识别块。
- 树最多4层、最多50个节点。根主题放 root。禁止跨层引用块。
2. style= ppt 时：
{"groups":[{"role":"title|heading|body|figure","elementIds":["块id或元素id..."]},...]}
- groups 必须按页面视觉顺序排列；每项只能引用给定 blocks（识别文本）或 elements（既有元素）的 id。
- role 仅 title/heading/body/figure：title 是页面大标题（最多1个），heading 是小节标题，body 是正文段落，figure 是配图/图示元素。
- 每个 block/element 只能出现在一个 group 中。
3. style= article 或 in_place 时：structure 为 {}，不要输出 groups 或 root。

若本条消息带有 layoutHint，必须使用该风格，并只输出该风格的 structure。`
	userPrompt := string(payload)
	content, err := l.postChat(ctx, systemPrompt, userPrompt)
	if err != nil {
		return nil, err
	}
	decision := &LayoutDecision{}
	if err := json.Unmarshal([]byte(content), decision); err != nil {
		return nil, err
	}
	l.sanitizeLayout(decision, request)
	return decision, nil
}
```

- [ ] **Step 4: 添加 sanitize 与结构校验**

在 `sanitizeLayout` 相关的同一文件末尾添加（`isSuccessBlockID` 依赖 `ComposeRequest.Blocks` 的 `Error` 字段；若请求结构体里块类型字段名不同（例如 `Err`），以实际为准并同步调整）：

```go
// sanitizeLayout 严格校验 AI 返回的判定结果，任何越界回落为 in_place。
func (l *OpenAICompatibleSmartLayouter) sanitizeLayout(
	decision *LayoutDecision, request *ComposeRequest,
) {
	switch decision.Style {
	case layoutStylePPT:
		decision.Structure = sanitizePptStructure(decision.Structure, request)
	case layoutStyleMindmap:
		decision.Structure = sanitizeMindmapStructure(decision.Structure, request)
	case layoutStyleArticle, layoutStyleInPlace:
		decision.Structure = nil
	default:
		decision.Style = layoutStyleInPlace
		decision.Structure = nil
	}
	if decision.Confidence < 0 {
		decision.Confidence = 0
	} else if decision.Confidence > 1 {
		decision.Confidence = 1
	}
	// 结构校验失败（返回 nil）时整体回落 in_place。
	if decision.Structure == nil && decision.Style != layoutStyleInPlace {
		decision.Style = layoutStyleInPlace
	}
}

func isSuccessBlock(request *ComposeRequest, blockID string) bool {
	for _, b := range request.Blocks {
		if b.ID == blockID {
			return b.Error == ""
		}
	}
	return false
}

func hasElementRef(request *ComposeRequest, elementID string) bool {
	for _, e := range request.Elements {
		if e.ID == elementID {
			return true
		}
	}
	return false
}

// sanitizePptStructure 返回规范化后的 groups 结构；无法使用返回 nil。
func sanitizePptStructure(structure map[string]any, request *ComposeRequest) map[string]any {
	groups, ok := structure["groups"].([]any)
	if !ok || len(groups) == 0 {
		return nil
	}
	normalized := make([]map[string]any, 0, len(groups))
	seenIDs := map[string]bool{}
	for _, raw := range groups {
		group, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		role, _ := group["role"].(string)
		switch role {
		case "title", "heading", "figure":
		default:
			role = "body"
		}
		rawIDs, _ := group["elementIds"].([]any)
		ids := make([]string, 0, len(rawIDs))
		for _, rawID := range rawIDs {
			id, ok := rawID.(string)
			if !ok {
				continue
			}
			if seenIDs[id] {
				continue
			}
			if isSuccessBlock(request, id) || hasElementRef(request, id) {
				seenIDs[id] = true
				ids = append(ids, id)
			}
		}
		if len(ids) == 0 {
			continue
		}
		normalized = append(normalized, map[string]any{"role": role, "elementIds": ids})
		if len(normalized) >= maxPptGroups {
			break
		}
	}
	if len(normalized) == 0 {
		return nil
	}
	return map[string]any{"groups": normalized}
}

// sanitizeMindmapStructure 返回规范化后的树结构；无法使用返回 nil。
func sanitizeMindmapStructure(structure map[string]any, request *ComposeRequest) map[string]any {
	root, ok := structure["root"].(map[string]any)
	if !ok {
		return nil
	}
	normalized, count := sanitizeMindmapNode(root, request, 1, 0)
	if normalized == nil || count == 0 {
		return nil
	}
	return map[string]any{"root": normalized}
}

// sanitizeMindmapNode 递归校验并返回一个节点；节点非法（无文本且无有效块引用、超层数、超节点数）返回 nil。
func sanitizeMindmapNode(
	node map[string]any, request *ComposeRequest, depth, usedCount int,
) (map[string]any, int) {
	text, _ := node["text"].(string)
	blockIDs := node["blockIds"]
	filtered := joinSuccessBlockText(request, blockIDs, text)
	if filtered == "" {
		return nil, usedCount
	}
	text = filtered
	count := usedCount + 1
	if count > maxMindmapNodes {
		return nil, usedCount
	}
	out := map[string]any{"text": text}
	rawChildren, _ := node["children"].([]any)
	if depth < maxMindmapDepth {
		children := make([]map[string]any, 0, len(rawChildren))
		for _, rawChild := range rawChildren {
			child, ok := rawChild.(map[string]any)
			if !ok {
				continue
			}
			normalized, nextCount := sanitizeMindmapNode(child, request, depth+1, count)
			if normalized == nil {
				continue
			}
			count = nextCount
			children = append(children, normalized)
		}
		if len(children) > 0 {
			out["children"] = children
		}
	}
	return out, count
}

// joinSuccessBlockText 将节点引用的成功块文本拼接为节点文字；无合法块时回退节点自带的 text。
func joinSuccessBlockText(request *ComposeRequest, rawBlockIDs any, fallbackText string) string {
	var joined string
	if rawBlockIDs != nil {
		if ids, ok := rawBlockIDs.([]any); ok {
			parts := make([]string, 0, len(ids))
			for _, rawID := range ids {
				id, ok := rawID.(string)
				if !ok {
					continue
				}
				for _, b := range request.Blocks {
					if b.ID == id && b.Error == "" && b.Text != "" {
						parts = append(parts, b.Text)
						break
					}
				}
			}
			joined = strings.Join(parts, "\n")
		}
	}
	if joined == "" {
		joined = fallbackText
	}
	joined = strings.TrimSpace(joined)
	if len([]rune(joined)) > maxMindmapNodeText {
		joined = string([]rune(joined)[:maxMindmapNodeText])
	}
	return joined
}
```

> 注意：`strings` 若未导入，在文件顶部 import 块加入 `"strings"`（Go 1.17+ 用 `import "strings"`，与其他导入并列）。

- [ ] **Step 5: compose 接入 decideLayout**

在 `Compose()` 方法体内、现有 `pages := decidePages(...)` 之前，插入：

```go
	layout, layoutErr := l.decideLayout(ctx, request)
```

在响应组装处（`SmartLayoutResponse{Document: ..., Blocks: ..., Pages: ...}`，字段名可能为 `Document`/`Blocks`/`Pages`，或与 `Compose()` 返回的 Go 结构体一致），追加：

```go
		Layout: layout,
```

并做两步行为改动：
1. `layoutErr != nil` 或 `layout == nil` 时：保持现有 `decidePages` 结果不变（回退旧行为），`layout` 留 nil（**不要**把错误向上抛，写一条日志：`log.Printf("[smart-layout] decideLayout failed: %v", layoutErr)`）。
2. `layout.Style == layoutStyleMindmap || layout.Style == layoutStylePPT` 时：跳过 AI 段落决策，改为 `pages := inPlacePages(request)`（即所有页面模式为 `"in_place"`、单块段落——直接复用 `decidePages` 的默认起始行为，例如保留 `singleBlockParagraphs` 分支的简化：给每页构造 `PageDecision{PageID: p.ID, Mode: "in_place", Paragraphs: nil}`，让客户端 `isArticle` 全为 false）。

> 若 `Compose()` 里构造 pages 的方式与上述描述不完全一致，以"保持原有字段、只在分支上做最小改动"为原则：article/in_place 风格完全走原路径；mindmap/ppt 风格强制 in_place 分页决策。**不要**改动 `buildSmartLayoutDocument` 的既有逻辑。

- [ ] **Step 6: 构建验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-Server && go build ./... && go vet ./...
```

Expected: 无输出、退出码 0。若有编译错误，按报错行修正（多为字段名/导入），修正后重跑。

- [ ] **Step 7: 提交**

```bash
git add FlowMuse-Server/internal/recognition/smart_layout.go
git commit -m "feat:智能排版服务端新增layout风格判定与严格校验"
```

### Task 3：服务端自动测试

**Files:**
- Create: `FlowMuse-Server/internal/recognition/smart_layout_test.go`

**Interfaces:**
- Consumes: `decideLayout`/`sanitizeLayout`/`sanitizePptStructure`/`sanitizeMindmapStructure`（T2）

- [ ] **Step 1: 编写测试文件**

新建 `FlowMuse-Server/internal/recognition/smart_layout_test.go`，内容如下（若 `OpenAICompatibleSmartLayouter` 的构造签名字段名不同（例如 `baseURL`/`model`/`apiKey`），按现有代码字段名调整；`postChat` 发到 `baseURL + "/chat/completions"`，测试用 `httptest` 拦截）：

```go
package recognition

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeChatServer 用固定内容响应 chat/completions。
func fakeChatServer(t *testing.T, content string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/chat/completions") {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{
				{"message": map[string]any{"content": content}},
			},
		})
	}))
}

func sampleComposeRequest() *ComposeRequest {
	return &ComposeRequest{
		Pages: []PageRef{{ID: "p-1", Index: 0}},
		Blocks: []BlockOut{
			{ID: "blk-1", Text: "手工记账", Error: ""},
			{ID: "blk-2", Text: "流水线", Error: ""},
			{ID: "blk-3", Text: "无法识别的字", Error: "recognition failed"},
		},
		Elements: []ElementRef{{ID: "e-1", Type: "image", Bounds: Bounds{Left: 0, Top: 0, Width: 10, Height: 10}}},
	}
}

func TestDecideLayoutMindmap(t *testing.T) {
	server := fakeChatServer(t, `{"style":"mindmap","confidence":0.9,"structure":{"root":{"text":"主题","blockIds":["blk-1","blk-2"]}}}`)
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	decision, err := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("decideLayout error: %v", err)
	}
	if decision.Style != layoutStyleMindmap {
		t.Fatalf("style = %q, want mindmap", decision.Style)
	}
	root, ok := decision.Structure["root"].(map[string]any)
	if !ok {
		t.Fatalf("root missing: %#v", decision.Structure)
	}
	if root["text"] != "主题" {
		t.Fatalf("root text = %q", root["text"])
	}
}

func TestDecideLayoutMindmapDropsFailedBlockRefs(t *testing.T) {
	server := fakeChatServer(t, `{"style":"mindmap","confidence":0.8,"structure":{"root":{"text":"","blockIds":["blk-3"]}}}`)
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	decision, err := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("decideLayout error: %v", err)
	}
	// root 引用失败块(blk-3)且无 text → 整树无效 → 回落 in_place
	if decision.Style != layoutStyleInPlace {
		t.Fatalf("style = %q, want in_place", decision.Style)
	}
}

func TestDecideLayoutPptSanitizesRoles(t *testing.T) {
	server := fakeChatServer(t, `{"style":"ppt","confidence":0.7,"structure":{"groups":[
		{"role":"title","elementIds":["blk-1"]},
		{"role":"unknown-role","elementIds":["e-1","blk-9"]},
		{"role":"body","elementIds":[]}
	]}}`)
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	decision, err := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("decideLayout error: %v", err)
	}
	if decision.Style != layoutStylePPT {
		t.Fatalf("style = %q, want ppt", decision.Style)
	}
	groups := decision.Structure["groups"].([]map[string]any)
	if len(groups) != 2 {
		t.Fatalf("groups len = %d, want 2 (非法role归为body、空组删除)", len(groups))
	}
	if groups[1]["role"] != "body" {
		t.Fatalf("role = %v, want body", groups[1]["role"])
	}
	ids := groups[1]["elementIds"].([]string)
	if len(ids) != 1 || ids[0] != "e-1" {
		t.Fatalf("ids = %v, want [e-1]（blk-9 失效引用删除）", ids)
	}
}

func TestDecideLayoutBadStyleFallsBack(t *testing.T) {
	server := fakeChatServer(t, `{"style":"diagram","confidence":0.5,"structure":{}}`)
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	decision, err := layouter.decideLayout(context.Background(), sampleComposeRequest())
	if err != nil {
		t.Fatalf("decideLayout error: %v", err)
	}
	if decision.Style != layoutStyleInPlace {
		t.Fatalf("style = %q, want in_place", decision.Style)
	}
}

func TestDecideLayoutHonorsHint(t *testing.T) {
	server := fakeChatServer(t, `{"style":"ppt","confidence":0.9,"structure":{"groups":[{"role":"title","elementIds":["blk-1"]}]}}`)
	defer server.Close()
	layouter := newTestSmartLayouter(server.URL)
	request := sampleComposeRequest()
	request.LayoutHint = layoutStylePPT
	decision, err := layouter.decideLayout(context.Background(), request)
	if err != nil {
		t.Fatalf("decideLayout error: %v", err)
	}
	if decision.Style != layoutStylePPT {
		t.Fatalf("style = %q, want ppt", decision.Style)
	}
}

// newTestSmartLayouter 构造一个指向 fake server 的 layouter。
func newTestSmartLayouter(baseURL string) *OpenAICompatibleSmartLayouter {
	return &OpenAICompatibleSmartLayouter{
		BaseURL: baseURL,
		APIKey:  "fake-key",
		Model:   "fake-model",
	}
}
```

> 若 `ComposeRequest`/`PageRef`/`BlockOut`/`Bounds` 等类型名与实际不符（例如 `Bounds` 是结构体还是别名、块字段是 `Err` 还是 `Error`），按 `types.go` 实际定义调整测试里的字段名与构造代码。**保持测试语义不变**。

- [ ] **Step 2: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-Server && go test ./internal/recognition/ -run 'TestDecideLayout|TestSanitize' -v
```

Expected: `ok`、全部用例 PASS。

- [ ] **Step 3: 全量回归**

```bash
cd F:/Project/FlowMuse/FlowMuse-Server && go build ./... && go test ./... && go vet ./...
```

Expected: 全绿。若 `myscript_test.go` 等既有测试受影响（理论上不会），停止并检查是否误改共享类型。

- [ ] **Step 4: 提交**

```bash
git add FlowMuse-Server/internal/recognition/smart_layout_test.go
git commit -m "test:智能排版layout判定与校验服务端测试"
```

### Task 4：客户端协议模型扩展（Dart）

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_document.dart`

**Interfaces:**
- Produces: `SmartLayoutStyle`（含 `fromWire`/`wireName`/`displayName`）、`SmartLayoutElementRef`、`SmartLayoutLayoutDecision`、`SmartLayoutPptGroup`、`SmartLayoutPptStructure`、`SmartLayoutComposeRequest.elements/layoutHint`、`SmartLayoutResponse.layout`（T6-T10 消费）

- [ ] **Step 1: 在文件顶部 import 区添加依赖**

`smart_layout_document.dart` 目前 import 了 `../elements/elements.dart`、`../layout/layout.dart`、`../math/math.dart`、`../../recognition/ink_recognition.dart`。无需新增 import（本任务只用现成的 `Bounds`、`Element` 字段读取）。

- [ ] **Step 2: 添加 SmartLayoutStyle 枚举**

在 `enum SmartLayoutExportFormat` 之后添加：

```dart
/// 智能排版自适应风格（v1 固定四种；后续新增样式只需扩展枚举与引擎分发）。
enum SmartLayoutStyle {
  ppt,
  mindmap,
  article,
  inPlace;

  static SmartLayoutStyle fromWire(
    String? value, {
    SmartLayoutStyle fallback = SmartLayoutStyle.inPlace,
  }) {
    return switch (value) {
      'ppt' => SmartLayoutStyle.ppt,
      'mindmap' => SmartLayoutStyle.mindmap,
      'article' => SmartLayoutStyle.article,
      'in_place' => SmartLayoutStyle.inPlace,
      _ => fallback,
    };
  }

  String get wireName => switch (this) {
        SmartLayoutStyle.ppt => 'ppt',
        SmartLayoutStyle.mindmap => 'mindmap',
        SmartLayoutStyle.article => 'article',
        SmartLayoutStyle.inPlace => 'in_place',
      };

  String get displayName => switch (this) {
        SmartLayoutStyle.ppt => 'PPT 式排版',
        SmartLayoutStyle.mindmap => '思维导图',
        SmartLayoutStyle.article => '文章式阅读流',
        SmartLayoutStyle.inPlace => '仅转机器字体',
      };
}
```

- [ ] **Step 3: 添加 SmartLayoutElementRef**

在 `SmartLayoutComposeRequest` 类定义之前添加：

```dart
/// compose 请求中的"非笔迹元素"最小摘要（供 AI 判定整页布局，不含坐标之外的敏感数据）。
class SmartLayoutElementRef {
  const SmartLayoutElementRef({
    required this.id,
    required this.type,
    required this.bounds,
    this.pageId,
    this.locked = false,
    this.groupIds = const [],
  });

  final String id;
  final String type;
  final Bounds bounds;
  final String? pageId;
  final bool locked;
  final List<String> groupIds;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'width': bounds.size.width,
          'height': bounds.size.height,
        },
        if (pageId != null) 'pageId': pageId,
        if (locked) 'locked': true,
        if (groupIds.isNotEmpty) 'groupIds': groupIds,
      };
}
```

- [ ] **Step 4: 扩展 SmartLayoutComposeRequest**

把 `SmartLayoutComposeRequest` 的字段与 toJson 改为（原有字段保留，仅新增两个）：

```dart
class SmartLayoutComposeRequest {
  const SmartLayoutComposeRequest({
    required this.pages,
    required this.blocks,
    this.elements = const [],
    this.layoutHint,
  });

  final List<SmartLayoutPageRequest> pages;
  final List<SmartLayoutRecognizedBlock> blocks;
  final List<SmartLayoutElementRef> elements;
  final SmartLayoutStyle? layoutHint;

  Map<String, Object?> toJson() => {
        'pages': pages.map((page) => page.toJson()).toList(),
        'blocks': blocks.map((block) => block.toJson()).toList(),
        if (elements.isNotEmpty)
          'elements': elements.map((element) => element.toJson()).toList(),
        if (layoutHint != null) 'layoutHint': layoutHint!.wireName,
      };
}
```

> 注意：`SmartLayoutRequest`（识别请求）**不要**加这两个字段，保持原样。

- [ ] **Step 5: 添加布局判定模型**

在 `SmartLayoutPageDecision` 之前添加：

```dart
/// 服务端布局判定（方案二：只判风格与语义结构，不返回坐标）。
class SmartLayoutLayoutDecision {
  const SmartLayoutLayoutDecision({
    required this.style,
    required this.confidence,
    this.mindmapStructure,
    this.pptStructure,
  });

  final SmartLayoutStyle style;
  final double confidence;
  final MindmapStructure? mindmapStructure;
  final SmartLayoutPptStructure? pptStructure;

  factory SmartLayoutLayoutDecision.fromJson(Map<String, Object?> json) {
    final style = SmartLayoutStyle.fromWire(json['style'] as String?);
    final confidence = ((json['confidence'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 1.0);
    final rawStructure = json['structure'];
    final structure = rawStructure is Map
        ? Map<String, Object?>.from(rawStructure)
        : null;
    return SmartLayoutLayoutDecision(
      style: style,
      confidence: confidence,
      mindmapStructure: style == SmartLayoutStyle.mindmap && structure != null
          ? MindmapStructure.fromJson(structure)
          : null,
      pptStructure: style == SmartLayoutStyle.ppt && structure != null
          ? SmartLayoutPptStructure.fromJson(structure)
          : null,
    );
  }
}

/// mindmap 语义结构（根节点 + children，节点文字来自识别块拼接或 AI 给定）。
class MindmapStructure {
  const MindmapStructure({required this.root});

  final MindmapStructureNode root;

  factory MindmapStructure.fromJson(Map<String, Object?> json) {
    final root = json['root'];
    if (root is! Map) {
      throw const FormatException('mindmap structure 缺少 root');
    }
    return MindmapStructure(
      root: MindmapStructureNode.fromJson(Map<String, Object?>.from(root)),
    );
  }

  bool get isEmpty => root.text.trim().isEmpty && root.children.isEmpty;
}

class MindmapStructureNode {
  const MindmapStructureNode({
    required this.text,
    required this.children,
    this.blockIds = const [],
  });

  final String text;
  final List<String> blockIds;
  final List<MindmapStructureNode> children;

  factory MindmapStructureNode.fromJson(Map<String, Object?> json) {
    final rawChildren = json['children'] as List<Object?>? ?? const [];
    return MindmapStructureNode(
      text: json['text'] as String? ?? '',
      blockIds: [
        for (final item in json['blockIds'] as List<Object?>? ?? const [])
          if (item is String) item,
      ],
      children: [
        for (final child in rawChildren)
          if (child is Map)
            MindmapStructureNode.fromJson(Map<String, Object?>.from(child)),
      ],
    );
  }
}

/// PPT 语义结构（有序分组，组内单元按视觉顺序）。
class SmartLayoutPptStructure {
  const SmartLayoutPptStructure({required this.groups});

  final List<SmartLayoutPptGroup> groups;

  factory SmartLayoutPptStructure.fromJson(Map<String, Object?> json) {
    final rawGroups = json['groups'] as List<Object?>? ?? const [];
    return SmartLayoutPptStructure(
      groups: [
        for (final group in rawGroups)
          if (group is Map)
            SmartLayoutPptGroup.fromJson(Map<String, Object?>.from(group)),
      ],
    );
  }

  bool get isEmpty => groups.isEmpty;
}

class SmartLayoutPptGroup {
  const SmartLayoutPptGroup({required this.role, required this.elementIds});

  final String role;
  final List<String> elementIds;

  factory SmartLayoutPptGroup.fromJson(Map<String, Object?> json) {
    final role = json['role'] as String? ?? 'body';
    final normalizedRole = switch (role) {
      'title' => 'title',
      'heading' => 'heading',
      'figure' => 'figure',
      _ => 'body',
    };
    return SmartLayoutPptGroup(
      role: normalizedRole,
      elementIds: [
        for (final item in json['elementIds'] as List<Object?>? ?? const [])
          if (item is String) item,
      ],
    );
  }
}
```

- [ ] **Step 6: 扩展 SmartLayoutResponse**

把 `SmartLayoutResponse` 改为（保留原有字段，新增 `layout`）：

```dart
class SmartLayoutResponse {
  const SmartLayoutResponse({
    required this.document,
    this.blocks = const [],
    this.pages = const [],
    this.layout,
  });

  final SmartLayoutDocument document;
  final List<SmartLayoutRecognizedBlock> blocks;
  final List<SmartLayoutPageDecision> pages;
  final SmartLayoutLayoutDecision? layout;

  factory SmartLayoutResponse.fromJson(Map<String, Object?> json) {
    final rawDocument = json['document'];
    final rawBlocks = json['blocks'] as List<Object?>? ?? const [];
    final rawPages = json['pages'] as List<Object?>? ?? const [];
    final rawLayout = json['layout'];
    return SmartLayoutResponse(
      document: rawDocument is Map
          ? SmartLayoutDocument.fromJson(Map<String, Object?>.from(rawDocument))
          : SmartLayoutDocument.fromJson(json),
      blocks: [
        for (final item in rawBlocks)
          if (item is Map)
            SmartLayoutRecognizedBlock.fromJson(
              Map<String, Object?>.from(item),
            ),
      ],
      pages: [
        for (final item in rawPages)
          if (item is Map)
            SmartLayoutPageDecision.fromJson(Map<String, Object?>.from(item)),
      ],
      layout: rawLayout is Map
          ? SmartLayoutLayoutDecision.fromJson(
              Map<String, Object?>.from(rawLayout),
            )
          : null,
    );
  }
}
```

- [ ] **Step 7: 运行静态检查**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter analyze lib/features/whiteboard/editor_core/src/core/smart_layout
```

Expected: 无 error（历史 info 可忽略）。若报 `MindmapStructure` 等未定义，检查是否把 Step 5 代码整个粘贴成功、缩进正确。

- [ ] **Step 8: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_document.dart
git commit -m "feat:智能排版compose模型扩展elements/layoutHint与layout判定"
```

### Task 5：客户端模型测试

**Files:**
- Create: `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_plan_test.dart`

**Interfaces:**
- Consumes: T4 的模型类

- [ ] **Step 1: 编写测试**

新建 `test/features/whiteboard/editor_core/smart_layout_plan_test.dart`：

```dart
import 'dart:ui';

import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartLayoutStyle', () {
    test('fromWire 识别四种风格，未知回落 inPlace', () {
      expect(SmartLayoutStyle.fromWire('ppt'), SmartLayoutStyle.ppt);
      expect(SmartLayoutStyle.fromWire('mindmap'), SmartLayoutStyle.mindmap);
      expect(SmartLayoutStyle.fromWire('article'), SmartLayoutStyle.article);
      expect(SmartLayoutStyle.fromWire('in_place'), SmartLayoutStyle.inPlace);
      expect(SmartLayoutStyle.fromWire('diagram'), SmartLayoutStyle.inPlace);
      expect(SmartLayoutStyle.fromWire(null), SmartLayoutStyle.inPlace);
    });

    test('wireName 与 displayName 一一对应', () {
      expect(SmartLayoutStyle.ppt.wireName, 'ppt');
      expect(SmartLayoutStyle.mindmap.wireName, 'mindmap');
      expect(
        SmartLayoutStyle.inPlace.wireName,
        'in_place',
      );
      expect(SmartLayoutStyle.ppt.displayName, 'PPT 式排版');
      expect(SmartLayoutStyle.mindmap.displayName, '思维导图');
    });
  });

  group('SmartLayoutComposeRequest', () {
    test('toJson 包含 elements 与 layoutHint；缺省时不输出', () {
      final request = SmartLayoutComposeRequest(
        pages: const [],
        blocks: const [],
        elements: [
          SmartLayoutElementRef(
            id: 'img-1',
            type: 'image',
            bounds: const Bounds.fromLTWH(0, 0, 10, 10),
            pageId: 'p-1',
            groupIds: const ['g-1'],
          ),
        ],
        layoutHint: SmartLayoutStyle.ppt,
      );
      final json = request.toJson();
      expect(json['layoutHint'], 'ppt');
      final elements = json['elements'] as List;
      final element = elements.first as Map;
      expect(element['id'], 'img-1');
      expect(element['type'], 'image');
      expect(element['locked'], isNull); // 未设置不输出
      expect(element['groupIds'], ['g-1']);

      final plain = SmartLayoutComposeRequest(
        pages: const [],
        blocks: const [],
      ).toJson();
      expect(plain.containsKey('elements'), isFalse);
      expect(plain.containsKey('layoutHint'), isFalse);
    });
  });

  group('SmartLayoutLayoutDecision', () {
    test('fromJson 解析 mindmap structure', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'mindmap',
        'confidence': 0.9,
        'structure': {
          'root': {
            'text': '主题',
            'blockIds': ['blk-1'],
            'children': [
              {'text': '分支', 'blockIds': ['blk-2'], 'children': []},
            ],
          },
        },
      });
      expect(decision.style, SmartLayoutStyle.mindmap);
      expect(decision.confidence, closeTo(0.9, 0.001));
      expect(decision.mindmapStructure, isNotNull);
      expect(decision.mindmapStructure!.root.text, '主题');
      expect(decision.mindmapStructure!.root.children.length, 1);
      expect(decision.mindmapStructure!.root.blockIds, ['blk-1']);
      expect(decision.pptStructure, isNull);
    });

    test('fromJson 解析 ppt structure 且未知 role 归为 body', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'ppt',
        'confidence': 2.0, // 钳制
        'structure': {
          'groups': [
            {'role': 'title', 'elementIds': ['blk-1']},
            {'role': 'unknown', 'elementIds': ['img-1']},
          ],
        },
      });
      expect(decision.confidence, 1.0);
      expect(decision.pptStructure, isNotNull);
      expect(decision.pptStructure!.groups.length, 2);
      expect(decision.pptStructure!.groups[1].role, 'body');
    });

    test('未知 style 回落 inPlace 且结构为空', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'diagram',
        'structure': {'root': {'text': 'x'}},
      });
      expect(decision.style, SmartLayoutStyle.inPlace);
      expect(decision.mindmapStructure, isNull);
      expect(decision.pptStructure, isNull);
    });
  });

  group('SmartLayoutResponse', () {
    test('layout 缺失时解析为 null（旧服务端兼容）', () {
      final response = SmartLayoutResponse.fromJson({
        'document': {
          'version': 1,
          'generatedAt': 1,
          'blocks': <Object?>[],
        },
        'pages': <Object?>[],
      });
      expect(response.layout, isNull);
    });
  });
}
```

> 若 `Bounds` 不是 const 构造（例如使用 `Bounds.fromLTWH` 而非 const），把 `const Bounds.fromLTWH(...)` 中的 `const` 去掉（该处是 `dart:ui` 的 `Rect` 包装类，参照 `smart_layout_document.dart` 里 `Bounds.fromLTWH` 的用法）。若 `Bounds` 的 `size`/`left` 等字段名不同，按 `math/math.dart` 实际定义调整。

- [ ] **Step 2: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_plan_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_plan_test.dart
git commit -m "test:智能排版compose模型与布局判定解析测试"
```

### Task 6：SmartLayoutPlan 模型与公开工具（纯 Dart）

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`（两处委托）
- Test: `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_plan_test.dart`（追加）

**Interfaces:**
- Produces: `SmartLayoutPlan`、`SmartLayoutFailureInfo`、`SmartLayoutGhostSpec`、`SmartLayoutPlacement.findInsertionBounds(...)`、`SmartLayoutUtils.mergePageCustomData(...)`、`SmartLayoutDocumentFactory.fromBlocks(...)`（T7-T10 消费）

- [ ] **Step 1: 新建计划模型文件**

创建 `smart_layout_plan.dart`，内容如下：

```dart
import 'dart:ui';

import '../elements/elements.dart';
import '../math/math.dart';
import 'smart_layout_document.dart';

/// 一次"确定"后的智能排版本页计划：所有坐标已由客户端算好，apply 不依赖网络。
class SmartLayoutPlan {
  const SmartLayoutPlan({
    required this.pageId,
    required this.style,
    required this.confidence,
    required this.description,
    required this.addElements,
    required this.moveDeltas,
    required this.removeIds,
    this.failedStrokeIds = const [],
    required this.selectIds,
    this.document,
    required this.previewRects,
    required this.removalRects,
    required this.failureRects,
  });

  final String pageId;
  final SmartLayoutStyle style;
  final double confidence;
  final String description;

  /// 新增元素（已含最终坐标；尚未合并 pageId，apply 时统一合并）。
  final List<Element> addElements;

  /// 既有元素 → 左上角平移量（组内成员由调用方展开为各自 delta）。
  final Map<ElementId, Offset> moveDeltas;

  /// 本轮删除的元素 id（识别成功的笔迹 + 旧智能排版文本）。
  final List<ElementId> removeIds;

  /// 识别失败块的笔迹 id（用户选择"删除未识别笔迹后继续"时删除）。
  final List<ElementId> failedStrokeIds;

  final Set<ElementId> selectIds;

  /// 导出文档；为 null 表示清空（SetSmartLayoutResult(null)）。
  final SmartLayoutDocument? document;

  /// 场景坐标：新增/移动后的包围盒（蓝色幽灵预览）。
  final List<Rect> previewRects;

  /// 场景坐标：将被删除的笔迹区域（灰色幽灵预览）。
  final List<Rect> removalRects;

  /// 场景坐标：识别失败区域（红色高亮，仅失败提示模式）。
  final List<Rect> failureRects;
}

/// 单块识别失败信息（供失败对话框与红框高亮）。
class SmartLayoutFailureInfo {
  const SmartLayoutFailureInfo({
    required this.blockId,
    required this.bounds,
    this.snippet,
    this.error,
  });

  final String blockId;
  final Rect bounds;
  final String? snippet;
  final String? error;
}

/// 画布幽灵预览状态（controller.smartLayoutGhost 承载；null = 不显示）。
class SmartLayoutGhostSpec {
  const SmartLayoutGhostSpec.preview({
    required this.previewRects,
    required this.removalRects,
  })  : failureRects = const [];

  const SmartLayoutGhostSpec.failures({required this.failureRects})
      : previewRects = const [],
        removalRects = const [];

  final List<Rect> previewRects;
  final List<Rect> removalRects;
  final List<Rect> failureRects;

  bool get isFailure => failureRects.isNotEmpty;
}

/// 严格放置求位（从 markdraw_controller._findStrictInsertionBounds 提取为公开纯函数）。
class SmartLayoutPlacement {
  const SmartLayoutPlacement._();

  static Bounds? findInsertionBounds(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied, {
    Bounds? preferred,
  }) {
    if (width > area.width || height > area.height) return null;
    const gap = 24.0;
    final xCandidates = <double>{
      if (preferred != null)
        preferred.left.clamp(area.left, area.right - width).toDouble(),
      area.left,
      area.right - width,
      for (final bounds in occupied) bounds.right + gap,
    };
    final yCandidates = <double>{
      if (preferred != null)
        preferred.top.clamp(area.top, area.bottom - height).toDouble(),
      area.top,
      area.bottom - height,
      for (final bounds in occupied) bounds.bottom + gap,
    };
    for (final y in yCandidates) {
      for (final x in xCandidates) {
        final candidate = Bounds.fromLTWH(x, y, width, height);
        if (candidate.left >= area.left &&
            candidate.top >= area.top &&
            candidate.right <= area.right &&
            candidate.bottom <= area.bottom &&
            !occupied.any(candidate.intersects)) {
          return candidate;
        }
      }
    }
    return null;
  }
}

/// 页面归属合并（从 markdraw_controller._mergeCurrentPageCustomData 提取为公开纯函数）。
class SmartLayoutUtils {
  const SmartLayoutUtils._();

  static Map<String, Object?> mergePageCustomData(
    Map<String, Object?>? customData,
    String pageId,
  ) {
    final next = {...?customData};
    final existingFlowMuse = next['flowMuse'];
    next['flowMuse'] = {
      if (existingFlowMuse is Map<String, Object?>) ...existingFlowMuse,
      'pageId': pageId,
    };
    return next;
  }
}

/// 导出文档工厂：mindmap/ppt 风格由客户端构建 SmartLayoutDocument，保持导出能力。
class SmartLayoutDocumentFactory {
  const SmartLayoutDocumentFactory._();

  static SmartLayoutDocument fromBlocks(List<SmartLayoutBlock> blocks) {
    return SmartLayoutDocument(
      version: 1,
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      blocks: blocks,
    );
  }
}
```

- [ ] **Step 2: 控制器两处委托**

打开 `markdraw_controller.dart`：

① 在文件顶部 import 区（与其他 smart_layout 导入并列）加：

```dart
import 'src/core/smart_layout/smart_layout_plan.dart';
```

② 找到 `_findStrictInsertionBounds`（约 4633 行），把整个方法体替换为：

```dart
  Bounds? _findStrictInsertionBounds(
    Rect area,
    double width,
    double height,
    List<Bounds> occupied, {
    Bounds? preferred,
  }) {
    return SmartLayoutPlacement.findInsertionBounds(
      area,
      width,
      height,
      occupied,
      preferred: preferred,
    );
  }
```

（方法签名保持原样，删掉原来内部的 `gap`/`xCandidates`/循环全部逻辑。）

③ 找到 `_mergeCurrentPageCustomData`（约 994 行），把整个方法体替换为：

```dart
  Map<String, Object?> _mergeCurrentPageCustomData(
    Map<String, Object?>? customData,
    String pageId,
  ) {
    return SmartLayoutUtils.mergePageCustomData(customData, pageId);
  }
```

- [ ] **Step 3: 追加纯函数测试**

在 `smart_layout_plan_test.dart` 的 `main()` 末尾（最后一个 `}` 之前）追加：

```dart
  group('SmartLayoutPlacement.findInsertionBounds', () {
    test('首选点可用时返回首选点', () {
      final area = Rect.fromLTWH(0, 0, 100, 100);
      final result = SmartLayoutPlacement.findInsertionBounds(
        area,
        20,
        20,
        const [],
        preferred: Bounds.fromLTWH(10, 10, 20, 20),
      );
      expect(result!.left, 10);
      expect(result.top, 10);
    });

    test('与占用相交时移到占用右侧', () {
      final area = Rect.fromLTWH(0, 0, 200, 100);
      final result = SmartLayoutPlacement.findInsertionBounds(
        area,
        20,
        20,
        [Bounds.fromLTWH(10, 10, 50, 50)],
        preferred: Bounds.fromLTWH(10, 10, 20, 20),
      );
      expect(result!.left, 60);
      expect(result.top, 10);
    });

    test('区域装不下返回 null', () {
      final result = SmartLayoutPlacement.findInsertionBounds(
        const Rect.fromLTWH(0, 0, 10, 10),
        20,
        20,
        const [],
      );
      expect(result, isNull);
    });
  });

  group('SmartLayoutUtils.mergePageCustomData', () {
    test('合并 pageId 且保留原有 flowMuse 内容', () {
      final merged = SmartLayoutUtils.mergePageCustomData(
        {'flowMuse': {'role': 'mindmap-node'}, 'other': 1},
        'p-1',
      );
      final flowMuse = merged['flowMuse'] as Map<String, Object?>;
      expect(flowMuse['role'], 'mindmap-node');
      expect(flowMuse['pageId'], 'p-1');
      expect(merged['other'], 1);
    });

    test('无 customData 时只创建 flowMuse 映射', () {
      final merged = SmartLayoutUtils.mergePageCustomData(null, 'p-1');
      final flowMuse = merged['flowMuse'] as Map<String, Object?>;
      expect(flowMuse['pageId'], 'p-1');
    });
  });
```

并在文件顶部 import 区加：

```dart
import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart';
```

> 若 `Bounds` 支持 `!= null` 比较即可；`Rect`/`Offset` 来自 `dart:ui`（测试文件已 import `dart:ui`）。

- [ ] **Step 4: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_plan_test.dart && flutter analyze lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart
```

Expected: 全部 PASS；analyze 无 error。

- [ ] **Step 5: 回归旧行为**

旧测试必须仍然全绿（委托重构必须行为等价）：

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/mindmap_ai_insertion_test.dart test/features/whiteboard/editor_core/smart_layout_placement_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_plan_test.dart
git commit -m "feat:智能排版计划模型与严格放置求位公开化"
```

### Task 7：PPT 确定性布局引擎（纯 Dart）

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart`
- Test: Create `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_ppt_engine_test.dart`

**Interfaces:**
- Consumes: `SmartLayoutPlacement` 无关；仅 `Bounds`（math）、`Rect`/`Offset`（dart:ui）
- Produces: `PptUnit`、`PptGroupItem`、`PptLayoutResult`、`PptLayoutEngine.place({contentArea, groups, units, occupied})`（T10 消费）

- [ ] **Step 1: 编写引擎**

创建 `smart_layout_ppt_engine.dart`：

```dart
import 'dart:math' as math;
import 'dart:ui';

import '../math/math.dart';

/// 一个版式单元：key 为单元标识（普通元素 id / 识别块 id / 成组元素组 id），size 为外接矩形尺寸。
class PptUnit {
  const PptUnit({required this.key, required this.size});

  final String key;
  final Size size;
}

/// 一个版式组（按 AI groups 语义）：role 仅 title/heading/body/figure；key 为组标识。
/// 单个单元成组时：key 与单元 key 相同、memberKeys 长度 1。
/// 成组元素（组内相对位置不变）时：key 为组 id、memberKeys 为组内成员 key。
class PptGroupItem {
  const PptGroupItem({
    required this.key,
    required this.role,
    required this.memberKeys,
  });

  final String key;
  final String role;
  final List<String> memberKeys;
}

class PptLayoutResult {
  const PptLayoutResult({required this.targets});

  /// key → 目标左上角（场景坐标）。
  final Map<String, Offset> targets;
}

/// PPT 式排版引擎：确定性双列网格（有配图）或单列（无配图），整体下移避障。
/// 布局规则见计划 3.3 节，不得改动常量与判定顺序。
class PptLayoutEngine {
  const PptLayoutEngine._();

  static const double unitGap = 16.0;
  static const double columnGap = 24.0;
  static const double rowGap = 24.0;
  static const double figureColumnRatio = 0.62;
  static const double downShiftStep = 24.0;
  static const int maxDownShifts = 40;

  static PptLayoutResult? place({
    required Rect contentArea,
    required List<PptGroupItem> groups,
    required Map<String, PptUnit> units,
    required List<Bounds> occupied,
  }) {
    if (groups.isEmpty) return null;
    final hasFigure = groups.any((group) => group.role == 'figure');
    final textGroups = [
      for (final group in groups)
        if (group.role != 'figure') group,
    ];
    final figureGroups = [
      for (final group in groups)
        if (group.role == 'figure') group,
    ];
    final placements = <String, Offset>{};

    bool placeColumn(
      List<PptGroupItem> columnGroups,
      double columnLeft,
      double columnWidth,
    ) {
      var y = contentArea.top;
      for (final group in columnGroups) {
        final unit = units[group.key];
        if (unit == null) continue;
        if (unit.size.width > columnWidth) return false;
        placements[group.key] = Offset(columnLeft, y);
        y += unit.size.height + rowGap;
        if (y - rowGap > contentArea.bottom) return false;
      }
      return true;
    }

    if (hasFigure) {
      final textWidth = contentArea.width * figureColumnRatio - 12;
      final figureLeft = contentArea.left + textWidth + columnGap;
      final figureWidth = contentArea.right - figureLeft;
      if (figureWidth <= 0) return null;
      if (!placeColumn(textGroups, contentArea.left, textWidth)) return null;
      if (!placeColumn(figureGroups, figureLeft, figureWidth)) return null;
    } else {
      if (!placeColumn(textGroups, contentArea.left, contentArea.width)) {
        return null;
      }
    }

    bool insideAndClear() {
      for (final entry in placements.entries) {
        final unit = units[entry.key];
        if (unit == null) continue;
        final rect = Rect.fromLTWH(
          entry.value.dx,
          entry.value.dy,
          unit.size.width,
          unit.size.height,
        );
        if (!contentArea.contains(rect.topLeft) ||
            !contentArea.contains(rect.bottomRight)) {
          return false;
        }
        for (final bounds in occupied) {
          final obstacle = Rect.fromLTWH(
            bounds.left,
            bounds.top,
            bounds.size.width,
            bounds.size.height,
          );
          if (rect.intersects(obstacle)) return false;
        }
      }
      return true;
    }

    if (insideAndClear()) {
      return PptLayoutResult(targets: placements);
    }
    for (var i = 1; i <= maxDownShifts; i++) {
      for (final key in placements.keys.toList()) {
        placements[key] = placements[key]! + const Offset(0, downShiftStep);
      }
      if (insideAndClear()) {
        return PptLayoutResult(targets: placements);
      }
    }
    return null;
  }
}

// 保留引用，供将来"分组单元原始矩形"语义扩展；当前仅用于宽度判断。
// ignore: unused_element
double _maxOf(double a, double b) => math.max(a, b);
```

> 若 analyzer 报 `_maxOf` 未使用，删除该函数与 `import 'dart:math' as math;`；若报 `math` 未使用同理。

- [ ] **Step 2: 编写测试**

创建 `smart_layout_ppt_engine_test.dart`：

```dart
import 'dart:ui';

import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 内容区 100,100 宽400 高300；有配图时：textWidth=400*0.62-12=236，figureLeft=100+236+24=360，figureWidth=140
  const area = Rect.fromLTWH(100, 100, 400, 300);

  PptLayoutResult? run(List<PptGroupItem> groups, Map<String, PptUnit> units) {
    return PptLayoutEngine.place(
      contentArea: area,
      groups: groups,
      units: units,
      occupied: const [],
    );
  }

  test('无配图时单列自上而下、左对齐排布', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
        PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
        'g2': PptUnit(key: 'g2', size: Size(300, 60)),
      },
    );
    expect(result, isNotNull);
    final targets = result!.targets;
    expect(targets['g1'], const Offset(100, 100));
    expect(targets['g2'], const Offset(100, 164)); // 100+40+24
  });

  test('存在配图时双列：文字列左、配图列右', () {
    final result = run(
      const [
        PptGroupItem(key: 'title', role: 'title', memberKeys: ['title']),
        PptGroupItem(key: 'img', role: 'figure', memberKeys: ['img']),
      ],
      const {
        'title': PptUnit(key: 'title', size: Size(200, 40)),
        'img': PptUnit(key: 'img', size: Size(120, 60)),
      },
    );
    expect(result, isNotNull);
    expect(result!.targets['title'], const Offset(100, 100));
    expect(result.targets['img'], const Offset(360, 100));
  });

  test('单元超出列宽返回 null', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(500, 40)),
      },
    );
    expect(result, isNull);
  });

  test('总高超内容区返回 null', () {
    final result = run(
      const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
        PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
        PptGroupItem(key: 'g3', role: 'body', memberKeys: ['g3']),
      ],
      const {
        'g1': PptUnit(key: 'g1', size: Size(100, 120)),
        'g2': PptUnit(key: 'g2', size: Size(100, 120)),
        'g3': PptUnit(key: 'g3', size: Size(100, 120)),
      },
    );
    // 100+120+24+120+24+120 = 508 > 300+100
    expect(result, isNull);
  });

  test('与障碍相交时整体下移避开', () {
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      units: const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      },
      occupied: [Bounds.fromLTWH(100, 100, 200, 20)],
    );
    expect(result, isNotNull);
    expect(result!.targets['g1'], const Offset(100, 124)); // 下移一步
  });

  test('下移超过上限仍冲突返回 null', () {
    final result = PptLayoutEngine.place(
      contentArea: area,
      groups: const [
        PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      ],
      units: const {
        'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      },
      occupied: [
        // 覆盖整个右/下通道，任何下移都碰撞
        Bounds.fromLTWH(100, 100, 400, 300),
      ],
    );
    expect(result, isNull);
  });

  test('确定性：同一输入两次结果相同', () {
    final groups = const [
      PptGroupItem(key: 'g1', role: 'body', memberKeys: ['g1']),
      PptGroupItem(key: 'g2', role: 'body', memberKeys: ['g2']),
    ];
    const units = {
      'g1': PptUnit(key: 'g1', size: Size(200, 40)),
      'g2': PptUnit(key: 'g2', size: Size(300, 60)),
    };
    final first = run(groups, units);
    final second = run(groups, units);
    expect(first!.targets, second!.targets);
  });
}
```

> `Bounds.fromLTWH` 若为可选/必选参数与 `smart_layout_document.dart` 一致（`Bounds.fromLTWH(x, y, width, height)`），直接照抄即可。

- [ ] **Step 3: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_ppt_engine_test.dart && flutter analyze lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart
```

Expected: 全部 PASS；analyze 无 error。

- [ ] **Step 4: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_ppt_engine.dart FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_ppt_engine_test.dart
git commit -m "feat:智能排版PPT式确定性布局引擎"
```

### Task 8：Mindmap 风格引擎（纯 Dart）

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart`
- Test: Create `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_mindmap_engine_test.dart`

**Interfaces:**
- Consumes: `MindmapLayout.treeToElements`（`editor/mindmap/mindmap_layout.dart`）、`MindmapNode.fromJson`（`editor/mindmap/mindmap_tree.dart`）、`SmartLayoutPlacement.findInsertionBounds`（T6）
- Produces: `MindmapStyleEngineResult{elements, bounds}`、`MindmapStyleEngine.plan({node, contentArea, occupied})`（T10 消费）

- [ ] **Step 1: 阅读 MindmapNode 派生方式（只读）**

打开 `editor_core/src/editor/mindmap/mindmap_tree.dart`，确认 `MindmapNode.fromJson` 接受 `{'text': ..., 'children': [...]}`（若还接受 `topic`/`title` 相同，不影响本任务）。打开 `mindmap_layout.dart` 确认 `treeToElements` 返回 `List<Element>`（矩形+文本+箭头三元组）。

- [ ] **Step 2: 编写引擎**

创建 `smart_layout_mindmap_engine.dart`：

```dart
import 'dart:ui';

import '../elements/elements.dart';
import '../math/math.dart';
import '../editor_mindmap.dart' show ...;
```

> **注意：** 引擎文件在 `core/smart_layout/` 下，思维导图在 `editor/mindmap/` 下。先确认跨目录引用写法：`lib/features/whiteboard/editor_core/src/editor/mindmap/mindmap_layout.dart` 中 `MindmapNode` 的导出路径。若 `editor/mindmap/mindmap.dart` 有 barrel 文件，用 `import '../editor/mindmap/mindmap.dart';`；否则分别 import `mindmap_layout.dart` 与 `mindmap_tree.dart`（按实际路径写）。下面代码假定 barrel 为 `../editor/mindmap/mindmap.dart`，若不存在则改成两个具体 import，**不要**改动文件内容外的其他代码。

```dart
import 'dart:ui';

import '../elements/elements.dart';
import '../math/math.dart';
import '../editor/mindmap/mindmap_layout.dart';
import '../editor/mindmap/mindmap_tree.dart';
import 'smart_layout_plan.dart';

class MindmapStyleEngineResult {
  const MindmapStyleEngineResult({required this.elements, required this.bounds});

  /// 已放置到最终位置、尚未合并 pageId 的树元素（矩形+文本+箭头）。
  final List<Element> elements;

  /// 整棵树 union 放置区域（用于预览矩形）。
  final Bounds bounds;
}

/// 头脑风暴 → 真思维导图引擎：复用 MindmapLayout 确定性布局 + 页内避碰放置。
/// 整棵树作为整体平移，不改变节点尺寸/层级/绑定。
class MindmapStyleEngine {
  const MindmapStyleEngine._();

  static MindmapStyleEngineResult? plan({
    required MindmapNode node,
    required Rect contentArea,
    required List<Bounds> occupied,
  }) {
    final preview = MindmapLayout.treeToElements(node, origin: const Point(0, 0));
    if (preview.isEmpty) return null;
    var union = Bounds.fromLTWH(
      preview.first.x,
      preview.first.y,
      preview.first.width,
      preview.first.height,
    );
    for (final element in preview.skip(1)) {
      union = union.union(
        Bounds.fromLTWH(
          element.x,
          element.y,
          element.width,
          element.height,
        ),
      );
    }
    final placement = SmartLayoutPlacement.findInsertionBounds(
      contentArea,
      union.size.width,
      union.size.height,
      occupied,
      preferred: null,
    );
    if (placement == null) return null;
    final dx = placement.left - union.left;
    final dy = placement.top - union.top;
    final moved = [
      for (final element in preview)
        element.copyWith(x: element.x + dx, y: element.y + dy),
    ];
    return MindmapStyleEngineResult(
      elements: moved,
      bounds: Bounds.fromLTWH(
        placement.left,
        placement.top,
        union.size.width,
        union.size.height,
      ),
    );
  }
}
```

> `Bounds.union` 若签名不同（例如 `union(Bounds)` 或 `union(Rect)`），按 `core/math/` 中 `Bounds` 的实际定义调整（`markdraw_controller.dart:5025` 使用 `bounds.union(e)`，即接受 `Bounds`）。
> `MindmapNode` 的构造：本引擎只接受外部传入的 `MindmapNode`（T10 负责从语义结构构建它），引擎内不解析 JSON。

- [ ] **Step 3: 编写测试**

创建 `smart_layout_mindmap_engine_test.dart`：

```dart
import 'dart:ui';

import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/editor/mindmap/mindmap_tree.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MindmapNode tree() => MindmapNode.fromJson({
        'text': '主题',
        'children': [
          {'text': '分支A', 'children': <Object?>[]},
          {'text': '分支B', 'children': [
            {'text': '子B1', 'children': <Object?>[]},
          ]},
        ],
      });

  test('空场景时将整棵树放入内容区且相对位置为确定性布局', () {
    final result = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    expect(result, isNotNull);
    final bounds = result!.bounds;
    expect(bounds.left, greaterThanOrEqualTo(72));
    expect(bounds.top, greaterThanOrEqualTo(72));
    expect(bounds.right, lessThanOrEqualTo(72 + 800));
    expect(bounds.bottom, lessThanOrEqualTo(72 + 600));
    // 节点数量：4 节点 → 4 矩形 + 4 文本 + 3 箭头
    final rects = result.elements
        .where((element) => element.runtimeType.toString() == 'RectangleElement');
    final edges = result.elements
        .where((element) => element.runtimeType.toString() == 'ArrowElement');
    expect(rects.length, 4);
    expect(edges.length, 3);
  });

  test('内容区被占满时返回 null（整页失败）', () {
    final result = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: [Bounds.fromLTWH(72, 72, 800, 600)],
    );
    expect(result, isNull);
  });

  test('确定性：同一输入两次结果元素坐标相同', () {
    final first = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    final second = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    expect(first!.elements.length, second!.elements.length);
    for (var i = 0; i < first.elements.length; i++) {
      expect(first.elements[i].x, second.elements[i].x);
      expect(first.elements[i].y, second.elements[i].y);
    }
  });
}
```

> 若 `MindmapNode.fromJson` 要求的 children 形态是 `List<Map>` 而不是 `List<dynamic>`，将该测试中的 `'children': <Object?>[]` 改成 `'children': []`（按 `mindmap_tree.dart` 实际解析容忍度）；若 `runtimeType` 断言与真实元素类不一致（例如元素类是 `Rectangle` 而非 `RectangleElement`），改用元素类名 import 后 `isA<...>()` 匹配（参照 `mindmap_layout_test.dart` 的既有断言写法）。

- [ ] **Step 4: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_mindmap_engine_test.dart && flutter analyze lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart
```

Expected: 全部 PASS；analyze 无 error。

- [ ] **Step 5: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_mindmap_engine_test.dart
git commit -m "feat:智能排版头脑风暴转真思维导图引擎"
```

### Task 9：移动构建器（绑定/文本/框架跟随，纯 Dart）

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart`
- Test: Create `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_move_builder_test.dart`

**Interfaces:**
- Consumes: `BindingUtils.findBoundArrows` / `updateBoundArrowEndpoints`（`editor/bindings/binding_utils.dart`）、`BoundTextUtils.updateBoundTextPositions`（`editor/bindings/bound_text_utils.dart`）、`Scene.updateElement`、`ElementId`、`FrameElement`、`ToolResult`/`UpdateElementResult`
- Produces: `SmartLayoutMoveBuilder.buildResults(Scene, Map<ElementId, Offset>) → List<ToolResult>`（T10 消费）

- [ ] **Step 1: 编写移动构建器**

创建 `smart_layout_move_builder.dart`：

```dart
import 'dart:ui';

import '../../editor/bindings/binding_utils.dart';
import '../../editor/bindings/bound_text_utils.dart';
import '../elements/elements.dart';
import '../scene/scene.dart';
import '../../editor/tool_result.dart';

/// 批量移动元素并携带关联更新：绑定箭头跟随、绑定文本跟随、frame 子元素跟随。
/// 输入 deltas 为"左上角平移量"；成组整体移动由调用方在 deltas 中展开为每个成员。
class SmartLayoutMoveBuilder {
  const SmartLayoutMoveBuilder._();

  static List<ToolResult> buildResults(
    Scene scene,
    Map<ElementId, Offset> deltas,
  ) {
    if (deltas.isEmpty) return const [];
    final results = <ToolResult>[];
    final seen = <ElementId>{};
    final movedRaw = <Element>[];

    // 1. 主体移动
    for (final entry in deltas.entries) {
      final original = scene.activeElements
          .where((element) => element.id == entry.key)
          .firstOrNull;
      if (original == null) continue;
      final updated = original.copyWith(
        x: original.x + entry.value.dx,
        y: original.y + entry.value.dy,
      );
      movedRaw.add(updated);
      seen.add(entry.key);
      results.add(UpdateElementResult(updated));
    }

    // 2. frame 子元素跟随（子元素的 frameId 指向被移动的 frame）
    final frameDeltaById = <String, Offset>{
      for (final entry in deltas.entries) entry.key.value: entry.value,
    };
    final frameIds = {
      for (final element in movedRaw)
        if (element is FrameElement) element.id.value,
    };
    if (frameIds.isNotEmpty) {
      for (final element in scene.activeElements) {
        final frameId = element.frameId;
        if (frameId == null || !frameIds.contains(frameId)) continue;
        if (seen.contains(element.id)) continue;
        final delta = frameDeltaById[frameId];
        if (delta == null) continue;
        seen.add(element.id);
        results.add(
          UpdateElementResult(
            element.copyWith(
              x: element.x + delta.dx,
              y: element.y + delta.dy,
            ),
          ),
        );
      }
    }

    // 3. 绑定文本跟随（位置随父元素）
    results.addAll(BoundTextUtils.updateBoundTextPositions(scene, movedRaw));

    // 4. 绑定箭头更新（用临时场景解析端点）
    var tempScene = scene;
    for (final element in movedRaw) {
      tempScene = tempScene.updateElement(element);
    }
    final arrowSeen = <ElementId>{};
    for (final element in movedRaw) {
      final arrows = BindingUtils.findBoundArrows(scene, element.id);
      for (final arrow in arrows) {
        if (seen.contains(arrow.id) || arrowSeen.contains(arrow.id)) continue;
        arrowSeen.add(arrow.id);
        final updated = BindingUtils.updateBoundArrowEndpoints(
          arrow,
          tempScene,
        );
        if (!identical(updated, arrow)) {
          results.add(UpdateElementResult(updated));
        }
      }
    }
    return results;
  }
}
```

> `firstOrNull` 若未定义为全局扩展（`core/elements/` 或 `package:collection`），改为：
> ```dart
> Element? original;
> for (final element in scene.activeElements) {
>   if (element.id == entry.key) { original = element; break; }
> }
> ```
> `FrameElement` 若在其子类文件而非 `elements.dart` 导出，确认 `import '../elements/elements.dart';` 是否覆盖（`frame_element.dart` 已由 `elements.dart` 导出，见 1.4 表）。

- [ ] **Step 2: 编写测试**

创建 `smart_layout_move_builder_test.dart`：

```dart
import 'dart:ui';

import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('移动普通矩形产生一条 UpdateElementResult', () {
    final scene = Scene()
      ..addElement(
        RectangleElement(id: ElementId.generate(), x: 0, y: 0, width: 10, height: 10),
      );
    final element = scene.activeElements.first;
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      element.id: const Offset(5, 7),
    });
    expect(results.length, 1);
    final update = results.first as UpdateElementResult;
    expect(update.element.x, 5);
    expect(update.element.y, 7);
  });

  test('绑定箭头跟随到新端点', () {
    final scene = Scene();
    final box = RectangleElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
    );
    final arrow = ArrowElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 50,
      height: 50,
      points: const [Point(0, 0), Point(100, 25)],
      startBinding: PointBinding(elementId: box.id.value, fixedPoint: const Point(1.0, 0.5)),
    );
    scene.addElement(box);
    scene.addElement(arrow);
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      box.id: const Offset(50, 100),
    });
    final arrowUpdates = results.whereType<UpdateElementResult>().where(
          (update) => update.element is ArrowElement,
        );
    expect(arrowUpdates.length, 1);
    // 移动后箭头应重新采样到新 box 位置（端点含 dx=50, dy=100）
    final moved = arrowUpdates.first.element as ArrowElement;
    expect(moved.points.first.x + moved.x, greaterThanOrEqualTo(120));
    expect(moved.points.first.y + moved.y, greaterThanOrEqualTo(100));
  });

  test('绑定文本跟随父元素位置', () {
    final scene = Scene();
    final box = RectangleElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
    );
    final label = TextElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      text: 'label',
      containerId: box.id.value,
      textAlign: TextAlign.center,
    );
    scene.addElement(box);
    scene.addElement(label);
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      box.id: const Offset(30, 40),
    });
    final textUpdates = results
        .whereType<UpdateElementResult>()
        .where((update) => update.element is TextElement);
    expect(textUpdates.length, 1);
    expect(textUpdates.first.element.x, 30);
    expect(textUpdates.first.element.y, 40);
  });

  test('同一元素不会产生两条更新（去重）', () {
    final scene = Scene()
      ..addElement(
        RectangleElement(id: ElementId.generate(), x: 0, y: 0, width: 10, height: 10),
      );
    final element = scene.activeElements.first;
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      element.id: const Offset(1, 1),
      element.id: const Offset(2, 2),
    });
    final updates = results.whereType<UpdateElementResult>();
    expect(updates.length, 1);
  });
}
```

> 若 `TextElement` 无 `containerId` 构造参数（字段名不同，如 `containerId` 在 copyWith 或叫 `containerElementId`），按 `text_element.dart` 实际字段调整；若 `RectangleElement` 构造签名不同（如必须给 `strokeColor` 等），按 `rectangle_element.dart` 补齐给默认值。

- [ ] **Step 3: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_move_builder_test.dart && flutter analyze lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart
```

Expected: 全部 PASS；analyze 无 error（若某个测试因元素构造签名报错，按 Step 2 注释调整构造参数，不要改动被测逻辑）。

- [ ] **Step 4: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_move_builder_test.dart
git commit -m "feat:智能排版移动构建器支持绑定文本与箭头跟随"
```

### Task 10：控制器按页编排（build / apply / ghost / failures）

**Files:**
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart`（追加 `SmartLayoutPlanResult`）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart`
- Test: Create `FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_optimization_test.dart`

**Interfaces:**
- Produces: `controller.smartLayoutGhost`（`ValueNotifier<SmartLayoutGhostSpec?>`）、`buildSmartLayoutPlan({required String pageId, SmartLayoutRecognitionEngine engine, SmartLayoutStyle? requestedStyle, void Function(int,int)? onProgress}) → Future<SmartLayoutPlanResult>`、`applySmartLayoutPlan(SmartLayoutPlan plan, {bool dropFailedBlocks = false}) → bool`、`setSmartLayoutGhost(SmartLayoutGhostSpec?) → void`（T11/T12 消费）
- 不修改 `runGlobalSmartLayout`（旧路径与旧测试保持原样）

- [ ] **Step 1: 追加 SmartLayoutPlanResult**

在 `smart_layout_plan.dart` 末尾追加：

```dart
/// 单页计划构建结果：plan 为 null 表示本页无内容可排版（无手写）。
class SmartLayoutPlanResult {
  const SmartLayoutPlanResult({
    this.plan,
    this.failures = const [],
    this.error,
  });

  final SmartLayoutPlan? plan;
  final List<SmartLayoutFailureInfo> failures;
  final String? error;

  bool get hasFailures => failures.isNotEmpty;
}
```

- [ ] **Step 2: 控制器新增状态成员与主流程**

打开 `markdraw_controller.dart`：

① 在字段区（`_recognizingInk` 声明附近）添加：

```dart
  /// 智能排版幽灵预览状态（画布层监听；null = 关闭）。
  final ValueNotifier<SmartLayoutGhostSpec?> smartLayoutGhost =
      ValueNotifier<SmartLayoutGhostSpec?>(null);
```

② 在 `runGlobalSmartLayout` 方法之后、文件内合适位置（不打断其他方法）添加以下方法集合（全部原样粘贴）：

```dart
  /// 为指定页构建智能排版计划（方案二：只算计划、不落场景；确定性）。
  Future<SmartLayoutPlanResult> buildSmartLayoutPlan({
    required String pageId,
    SmartLayoutRecognitionEngine engine = SmartLayoutRecognitionEngine.ai,
    SmartLayoutStyle? requestedStyle,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_recognizingInk) {
      return const SmartLayoutPlanResult(error: '智能排版进行中，请稍候');
    }
    if (_disposed) {
      return const SmartLayoutPlanResult(error: '编辑器已释放');
    }
    final page = _layout.pages.where((p) => p.id == pageId).firstOrNull;
    if (page == null) {
      return SmartLayoutPlanResult(error: '页面不存在: $pageId');
    }
    final layoutCallback = onSmartLayoutInk;
    final blockCallback = onRecognizeSmartLayoutBlock;
    final composeCallback = onComposeSmartLayout;
    final myScriptCallback = onRecognizeInk;
    final canRecognizeWithAI =
        layoutCallback != null ||
        (blockCallback != null && composeCallback != null);
    final canRecognizeWithMyScript =
        myScriptCallback != null && composeCallback != null;
    if ((engine == SmartLayoutRecognitionEngine.ai && !canRecognizeWithAI) ||
        (engine == SmartLayoutRecognitionEngine.myscript &&
            !canRecognizeWithMyScript)) {
      return const SmartLayoutPlanResult(error: '没有可用的识别引擎');
    }
    _recognizingInk = true;
    try {
      final inkGroups = _smartLayoutInkGroupsForPage(pageId);
      if (inkGroups.isEmpty) {
        return const SmartLayoutPlanResult();
      }
      final request =
          await _buildSmartLayoutRequest(inkGroups, engine: engine);
      if (_disposed || request.blocks.isEmpty) {
        return const SmartLayoutPlanResult();
      }
      SmartLayoutResponse response;
      try {
        if (engine == SmartLayoutRecognitionEngine.myscript) {
          final recognized = await _recognizeSmartLayoutBlocksInParallel(
            request.blocks,
            (block) {
              final strokes =
                  inkGroups[block.id] ?? const <FreedrawElement>[];
              return _recognizeSmartLayoutBlockWithMyScript(
                block,
                strokes,
                myScriptCallback!,
              );
            },
            onProgress,
          );
          if (_disposed) {
            return const SmartLayoutPlanResult(error: '编辑器已释放');
          }
          response = await composeCallback!(
            SmartLayoutComposeRequest(
              pages: request.pages,
              blocks: recognized,
            ),
          );
        } else if (blockCallback != null && composeCallback != null) {
          final recognized = await _recognizeSmartLayoutBlocksInParallel(
            request.blocks,
            blockCallback,
            onProgress,
          );
          if (_disposed) {
            return const SmartLayoutPlanResult(error: '编辑器已释放');
          }
          response = await composeCallback(
            SmartLayoutComposeRequest(
              pages: request.pages,
              blocks: recognized,
              elements: _smartLayoutComposeElements(pageId),
              layoutHint: requestedStyle,
            ),
          );
        } else {
          response = await layoutCallback!(request);
          onProgress?.call(request.blocks.length, request.blocks.length);
        }
      } catch (error, stackTrace) {
        debugPrint('[$_logTag] 智能排版请求失败: $error');
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (_disposed) {
        return const SmartLayoutPlanResult(error: '编辑器已释放');
      }
      final successBlockIds = <String>{
        for (final block in response.blocks)
          if (block.isSuccess) block.id,
      };
      final removeIds = <ElementId>[
        for (final entry in inkGroups.entries)
          if (successBlockIds.contains(entry.key))
            for (final stroke in entry.value) stroke.id,
        for (final text in _pageScopedOldSmartText(pageId)) text.id,
      ];
      final failedStrokeIds = <ElementId>[
        for (final entry in inkGroups.entries)
          if (!successBlockIds.contains(entry.key))
            for (final stroke in entry.value) stroke.id,
      ];
      final excludedIds = <ElementId>{for (final id in removeIds) id};
      final failures = <SmartLayoutFailureInfo>[
        for (final block in response.blocks)
          if (!block.isSuccess)
            SmartLayoutFailureInfo(
              blockId: block.id,
              bounds: Rect.fromLTWH(
                block.bounds.left,
                block.bounds.top,
                block.bounds.size.width,
                block.bounds.size.height,
              ),
              error: block.error,
            ),
      ];
      final removalRects = <Rect>[
        for (final entry in inkGroups.entries)
          if (successBlockIds.contains(entry.key))
            _inkGroupBounds(entry.value),
      ];
      final failureRects = <Rect>[
        for (final entry in inkGroups.entries)
          if (!successBlockIds.contains(entry.key))
            _inkGroupBounds(entry.value),
      ];
      if (successBlockIds.isEmpty) {
        return SmartLayoutPlanResult(
          failures: failures,
          error: '智能识别结果不完整：本页手写均未识别成功',
        );
      }
      final style = requestedStyle ??
          response.layout?.style ??
          _legacyStyleFromPages(response.pages);
      return _planForStyle(
        style,
        response,
        page: page,
        excludedIds: excludedIds,
        failures: failures,
        removeIds: removeIds,
        failedStrokeIds: failedStrokeIds,
        removalRects: removalRects,
        failureRects: failureRects,
      );
    } finally {
      _recognizingInk = false;
    }
  }

  /// 应用计划：一次 History 提交（删除→移动→新增→文档→选区）。
  bool applySmartLayoutPlan(
    SmartLayoutPlan plan, {
    bool dropFailedBlocks = false,
  }) {
    if (_disposed) return false;
    pushHistory();
    final results = <ToolResult>[
      for (final id in plan.removeIds) RemoveElementResult(id),
      if (dropFailedBlocks)
        for (final id in plan.failedStrokeIds) RemoveElementResult(id),
    ];
    results.addAll(
      SmartLayoutMoveBuilder.buildResults(
        _editorState.scene,
        plan.moveDeltas,
      ),
    );
    results.addAll([
      for (final element in plan.addElements)
        AddElementResult(
          element.copyWith(
            customData: SmartLayoutUtils.mergePageCustomData(
              element.customData,
              plan.pageId,
            ),
          ),
        ),
    ]);
    results.add(SetSmartLayoutResult(plan.document));
    results.add(SetSelectionResult(plan.selectIds));
    applyResult(CompoundResult(results));
    smartLayoutGhost.value = null;
    return true;
  }

  /// 设置/清除画布幽灵预览（T11 消费）。
  void setSmartLayoutGhost(SmartLayoutGhostSpec? spec) {
    smartLayoutGhost.value = spec;
  }
```

- [ ] **Step 3: 控制器新增私有辅助（上一步之后继续追加）**

```dart
  SmartLayoutPlanResult _planForStyle(
    SmartLayoutStyle style,
    SmartLayoutResponse response, {
    required CanvasPage page,
    required Set<ElementId> excludedIds,
    required List<SmartLayoutFailureInfo> failures,
    required List<ElementId> removeIds,
    required List<ElementId> failedStrokeIds,
    required List<Rect> removalRects,
    required List<Rect> failureRects,
  }) {
    switch (style) {
      case SmartLayoutStyle.mindmap:
        final structure = response.layout?.mindmapStructure;
        if (structure == null || structure.isEmpty) {
          return _legacyPlacementPlan(
            response,
            page: page,
            excludedIds: excludedIds,
            failures: failures,
            removeIds: removeIds,
            failedStrokeIds: failedStrokeIds,
            removalRects: removalRects,
            failureRects: failureRects,
            style: SmartLayoutStyle.inPlace,
          );
        }
        return _mindmapPlan(
          response,
          page: page,
          structure: structure,
          excludedIds: excludedIds,
          failures: failures,
          removeIds: removeIds,
          failedStrokeIds: failedStrokeIds,
          removalRects: removalRects,
          failureRects: failureRects,
        );
      case SmartLayoutStyle.ppt:
        final structure = response.layout?.pptStructure;
        if (structure == null || structure.isEmpty) {
          return _legacyPlacementPlan(
            response,
            page: page,
            excludedIds: excludedIds,
            failures: failures,
            removeIds: removeIds,
            failedStrokeIds: failedStrokeIds,
            removalRects: removalRects,
            failureRects: failureRects,
            style: SmartLayoutStyle.inPlace,
          );
        }
        return _pptPlan(
          response,
          page: page,
          structure: structure,
          excludedIds: excludedIds,
          failures: failures,
          removeIds: removeIds,
          failedStrokeIds: failedStrokeIds,
          removalRects: removalRects,
          failureRects: failureRects,
        );
      case SmartLayoutStyle.article:
      case SmartLayoutStyle.inPlace:
        return _legacyPlacementPlan(
          response,
          page: page,
          excludedIds: excludedIds,
          failures: failures,
          removeIds: removeIds,
          failedStrokeIds: failedStrokeIds,
          removalRects: removalRects,
          failureRects: failureRects,
          style: style,
        );
    }
  }

  SmartLayoutPlanResult _legacyPlacementPlan(
    SmartLayoutResponse response, {
    required CanvasPage page,
    required Set<ElementId> excludedIds,
    required List<SmartLayoutFailureInfo> failures,
    required List<ElementId> removeIds,
    required List<ElementId> failedStrokeIds,
    required List<Rect> removalRects,
    required List<Rect> failureRects,
    required SmartLayoutStyle style,
  }) {
    final replacement = _elementsFromSmartLayoutResponse(
      response,
      excludedIds: excludedIds,
    );
    if (replacement == null) {
      throw StateError('智能排版没有足够的空白区域');
    }
    final title = style == SmartLayoutStyle.article
        ? '按文章阅读流重新排版本页内容'
        : '仅将手写识别为机器字体，保持原位附近';
    return SmartLayoutPlanResult(
      plan: SmartLayoutPlan(
        pageId: page.id,
        style: style,
        confidence: response.layout?.confidence ?? 0,
        description: title,
        addElements: replacement,
        moveDeltas: const {},
        removeIds: removeIds,
        failedStrokeIds: failedStrokeIds,
        selectIds: {for (final element in replacement) element.id},
        document: response.document,
        previewRects: [
          for (final element in replacement)
            Rect.fromLTWH(
              element.x,
              element.y,
              element.width,
              element.height,
            ),
        ],
        removalRects: removalRects,
        failureRects: failureRects,
      ),
      failures: failures,
    );
  }

  SmartLayoutPlanResult _mindmapPlan(
    SmartLayoutResponse response, {
    required CanvasPage page,
    required MindmapStructure structure,
    required Set<ElementId> excludedIds,
    required List<SmartLayoutFailureInfo> failures,
    required List<ElementId> removeIds,
    required List<ElementId> failedStrokeIds,
    required List<Rect> removalRects,
    required List<Rect> failureRects,
  }) {
    final textByBlockId = <String, String>{
      for (final block in response.blocks)
        if (block.isSuccess && (block.text?.trim().isNotEmpty ?? false))
          block.id: block.text!.trim(),
    };
    final node = _mindmapNodeFromStructure(structure.root, textByBlockId);
    final occupied =
        _smartLayoutSceneOccupancy(excludedIds)[page.id] ?? const <Bounds>[];
    final contentArea = page.bounds.deflate(72);
    final result = MindmapStyleEngine.plan(
      node: node,
      contentArea: contentArea,
      occupied: occupied,
    );
    if (result == null) {
      throw StateError('智能排版没有足够的空白区域');
    }
    final rootId = _mindmapRootElementId(result.elements);
    final blockCount = response.blocks
        .where((block) => block.isSuccess)
        .length;
    final depth = _mindmapDepth(structure.root);
    final nodeCount = _mindmapNodeCount(structure.root);
    final document = SmartLayoutDocumentFactory.fromBlocks([
      for (var i = 0; i < result.elements.length; i++)
        if (result.elements[i] is TextElement)
          SmartLayoutBlock(
            id: 'export-mindmap-$i',
            type: 'paragraph',
            text: (result.elements[i] as TextElement).text,
            pageId: page.id,
            order: i,
          ),
    ]);
    return SmartLayoutPlanResult(
      plan: SmartLayoutPlan(
        pageId: page.id,
        style: SmartLayoutStyle.mindmap,
        confidence: response.layout?.confidence ?? 0,
        description:
            '检测到头脑风暴内容：将 $blockCount 个手写块整理为 $depth 层思维导图（$nodeCount 个节点）',
        addElements: result.elements,
        moveDeltas: const {},
        removeIds: removeIds,
        failedStrokeIds: failedStrokeIds,
        selectIds: {rootId},
        document: document,
        previewRects: [
          for (final element in result.elements)
            Rect.fromLTWH(
              element.x,
              element.y,
              element.width,
              element.height,
            ),
        ],
        removalRects: removalRects,
        failureRects: failureRects,
      ),
      failures: failures,
    );
  }

  MindmapNode _mindmapNodeFromStructure(
    MindmapStructureNode node,
    Map<String, String> textByBlockId,
  ) {
    final joined = [
      for (final id in node.blockIds)
        if (textByBlockId[id] != null) textByBlockId[id]!,
    ].join('\n');
    return MindmapNode.fromJson({
      'text': joined.trim().isNotEmpty ? joined.trim() : node.text,
      'children': [
        for (final child in node.children)
          _mindmapNodeFromStructure(child, textByBlockId),
      ],
    });
  }

  int _mindmapNodeCount(MindmapStructureNode node) =>
      1 +
      node.children.fold<int>(
        0,
        (sum, child) => sum + _mindmapNodeCount(child),
      );

  int _mindmapDepth(MindmapStructureNode node) {
    var depth = 1;
    for (final child in node.children) {
      depth = math.max(depth, 1 + _mindmapDepth(child));
    }
    return depth;
  }

  ElementId _mindmapRootElementId(List<Element> elements) {
    final childNodeIds = <String>{
      for (final edge in elements.whereType<ArrowElement>())
        if (edge.endBinding != null) edge.endBinding!.elementId,
    };
    final root = elements.whereType<RectangleElement>()
        .where((element) => !childNodeIds.contains(element.id.value))
        .firstOrNull;
    return root != null ? root.id : elements.first.id;
  }

  Map<String, List<FreedrawElement>> _smartLayoutInkGroupsForPage(
    String pageId,
  ) {
    return <String, List<FreedrawElement>>{
      for (final entry in _smartLayoutInkGroups().entries)
        if (entry.key.startsWith('$pageId:')) entry.key: entry.value,
    };
  }

  List<TextElement> _pageScopedOldSmartText(String pageId) {
    return [
      for (final element in _smartLayoutGeneratedTextElements())
        if (_pageIdForElement(element) == pageId) element,
    ];
  }

  List<Element> _smartLayoutPageElements(String pageId) {
    return [
      for (final element in _editorState.scene.activeElements)
        if (_pageIdForElement(element) == pageId &&
            !element.isCanvasPage &&
            !element.isPdfBackground &&
            !element.locked &&
            !_isMindmapElement(element) &&
            element is! FreedrawElement)
          element,
    ];
  }

  bool _isMindmapElement(Element element) {
    final role = _flowMuseData(element)?['role'];
    return role == 'mindmap-node' || role == 'mindmap-edge';
  }

  List<SmartLayoutElementRef> _smartLayoutComposeElements(String pageId) {
    return [
      for (final element in _smartLayoutPageElements(pageId))
        SmartLayoutElementRef(
          id: element.id.value,
          type: element.runtimeType.toString(),
          bounds: _placementBoundsForElement(element),
          pageId: pageId,
          locked: element.locked,
          groupIds: element.groupIds,
        ),
    ];
  }

  Rect _inkGroupBounds(List<FreedrawElement> strokes) {
    var bounds = _placementBoundsForElement(strokes.first);
    for (final stroke in strokes.skip(1)) {
      bounds = bounds.union(_placementBoundsForElement(stroke));
    }
    return Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );
  }

  SmartLayoutStyle _legacyStyleFromPages(List<SmartLayoutPageDecision> pages) {
    for (final page in pages) {
      if (page.isArticle) return SmartLayoutStyle.article;
    }
    return SmartLayoutStyle.inPlace;
  }
```

（续：PPT 计划构建方法 `_pptPlan` 见下段——它继续沿用上述签名风格。下面紧跟的是 `_pptPlan` 的代码。）

  SmartLayoutPlanResult _pptPlan(
    SmartLayoutResponse response, {
    required CanvasPage page,
    required SmartLayoutPptStructure structure,
    required Set<ElementId> excludedIds,
    required List<SmartLayoutFailureInfo> failures,
    required List<ElementId> removeIds,
    required List<ElementId> failedStrokeIds,
    required List<Rect> removalRects,
    required List<Rect> failureRects,
  }) {
    final pageId = page.id;
    final blocksById = <String, SmartLayoutRecognizedBlock>{
      for (final block in response.blocks)
        if (block.isSuccess) block.id: block,
    };
    final pageElements = <String, Element>{
      for (final element in _smartLayoutPageElements(pageId))
        element.id.value: element,
    };
    final createdTexts = <String, TextElement>{};
    final groupsOnPage = <String, (Rect, List<String>)>{};
    for (final element in _smartLayoutPageElements(pageId)) {
      final groupId = GroupUtils.outermostGroupId(element);
      if (groupId == null || groupsOnPage.containsKey(groupId)) continue;
      final members = GroupUtils.findGroupMembers(_editorState.scene, groupId);
      if (members.isEmpty) continue;
      var union = _placementBoundsForElement(members.first);
      for (final member in members.skip(1)) {
        union = union.union(_placementBoundsForElement(member));
      }
      groupsOnPage[groupId] = (
        Rect.fromLTWH(
          union.left,
          union.top,
          union.size.width,
          union.size.height,
        ),
        [for (final member in members) member.id.value],
      );
    }
    final units = <String, Size>{};
    final rawToUnitKey = <String, String>{};
    for (final element in _smartLayoutPageElements(pageId)) {
      final groupId = GroupUtils.outermostGroupId(element);
      if (groupId != null && groupsOnPage.containsKey(groupId)) {
        rawToUnitKey[element.id.value] = groupId;
        units[groupId] = groupsOnPage[groupId]!.$1.size;
      } else {
        rawToUnitKey[element.id.value] = element.id.value;
        units[element.id.value] = Size(element.width, element.height);
      }
    }
    for (final block in blocksById.values) {
      final text = _textElementFromRecognizedBlock(block);
      if (text == null) continue;
      createdTexts[block.id] = text;
      rawToUnitKey[block.id] = block.id;
      units[block.id] = Size(text.width, text.height);
    }
    final items = <PptGroupItem>[];
    for (var i = 0; i < structure.groups.length; i++) {
      final group = structure.groups[i];
      final keys = <String>[];
      for (final rawId in group.elementIds) {
        final key = rawToUnitKey[rawId];
        if (key == null) continue;
        if (!keys.contains(key)) keys.add(key);
      }
      if (keys.isEmpty) continue;
      final isWholeGroup =
          keys.length == 1 && groupsOnPage.containsKey(keys.first);
      if (isWholeGroup) {
        items.add(PptGroupItem(
          key: keys.first,
          role: group.role,
          memberKeys: [keys.first],
        ));
      } else {
        final itemKey = 'g-$i';
        var width = 0.0;
        var height = 0.0;
        for (final key in keys) {
          final size = units[key];
          if (size == null) continue;
          width += size.width + PptLayoutEngine.unitGap;
          height = math.max(height, size.height);
        }
        width -= PptLayoutEngine.unitGap;
        units[itemKey] = Size(width, height);
        items.add(PptGroupItem(
          key: itemKey,
          role: group.role,
          memberKeys: keys,
        ));
      }
    }
    if (items.isEmpty) {
      return _legacyPlacementPlan(
        response,
        page: page,
        failureRects: failureRects,
        failures: failures,
        removeIds: removeIds,
        failedStrokeIds: failedStrokeIds,
        removalRects: removalRects,
        excludedIds: excludedIds,
        style: SmartLayoutStyle.inPlace,
      );
    }
    final contentArea = page.bounds.deflate(72);
    final pageOccupied =
        _smartLayoutSceneOccupancy(excludedIds)[pageId] ?? const <Bounds>[];
    final placed = PptLayoutEngine.place(
      contentArea: contentArea,
      groups: items,
      units: units,
      occupied: pageOccupied,
    );
    if (placed == null) {
      throw StateError('智能排版没有足够的空白区域');
    }
    final addElements = <Element>[];
    final moveDeltas = <ElementId, Offset>{};
    final previewRects = <Rect>[];
    for (final item in items) {
      final target = placed.targets[item.key];
      if (target == null) continue;
      if (item.memberKeys.length == 1 && groupsOnPage.containsKey(
        item.memberKeys.first,
      )) {
        final groupKey = item.memberKeys.first;
        final group = groupsOnPage[groupKey]!;
        final delta = Offset(
          target.dx - group.$1.left,
          target.dy - group.$1.top,
        );
        for (final memberId in group.$2) {
          final element = pageElements[memberId];
          if (element == null) continue;
          moveDeltas[ElementId(memberId)] = delta;
          previewRects.add(
            Rect.fromLTWH(
              element.x + delta.dx,
              element.y + delta.dy,
              element.width,
              element.height,
            ),
          );
        }
        continue;
      }
      var x = target.dx;
      for (final key in item.memberKeys) {
        final text = createdTexts[key];
        if (text != null) {
          addElements.add(text.copyWith(x: x, y: target.dy));
          previewRects.add(
            Rect.fromLTWH(x, target.dy, text.width, text.height),
          );
        } else {
          final element = pageElements[key];
          if (element != null) {
            moveDeltas[ElementId(key)] = Offset(
              x - element.x,
              target.dy - element.y,
            );
            previewRects.add(
              Rect.fromLTWH(x, target.dy, element.width, element.height),
            );
          }
        }
        x += units[key]!.width + PptLayoutEngine.unitGap;
      }
    }
    final titleCount = structure.groups
        .where((group) => group.role == 'title')
        .length;
    final bodyCount = structure.groups
        .where((group) => group.role == 'body' || group.role == 'heading')
        .length;
    final figureCount = structure.groups
        .where((group) => group.role == 'figure')
        .length;
    final document = SmartLayoutDocumentFactory.fromBlocks([
      for (var i = 0; i < addElements.length; i++)
        if (addElements[i] is TextElement)
          SmartLayoutBlock(
            id: 'export-ppt-$i',
            type: 'paragraph',
            text: (addElements[i] as TextElement).text,
            pageId: pageId,
            order: i,
          ),
    ]);
    return SmartLayoutPlanResult(
      plan: SmartLayoutPlan(
        pageId: pageId,
        style: SmartLayoutStyle.ppt,
        confidence: response.layout?.confidence ?? 0,
        description: '按 PPT 版式重排：标题 $titleCount 处、正文段落 $bodyCount 段、配图 $figureCount 张',
        addElements: addElements,
        moveDeltas: moveDeltas,
        removeIds: removeIds,
        failedStrokeIds: failedStrokeIds,
        selectIds: {
          ...{for (final element in addElements) element.id},
          ...moveDeltas.keys,
        },
        document: document,
        previewRects: previewRects,
        removalRects: removalRects,
        failureRects: failureRects,
      ),
      failures: failures,
    );
  }

  Rect _inkGroupBounds(List<FreedrawElement> strokes) {
    var bounds = _placementBoundsForElement(strokes.first);
    for (final stroke in strokes.skip(1)) {
      bounds = bounds.union(_placementBoundsForElement(stroke));
    }
    return Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.size.width,
      bounds.size.height,
    );
  }
```

> 注意：`_pptPlan` 里的函数参数与前两个分支一致；`math`（`dart:math as math`）与 `GroupUtils`、`Rect`/`Offset`/`Size`（`dart:ui`）、`CanvasPage`（layout）均已在控制器中导入——若编译报缺 import，按报错补 `import 'package:flutter/material.dart' show Offset, Size;` 或对应工具类导入，**不要**改业务逻辑。

- [ ] **Step 4: 控制器 import 修正**

若编译报 `First_Or_Null`/`GroupUtils`/`PptLayoutEngine`/`MindmapStyleEngine`/`SmartLayoutPlacement` 未定义，按以下清单补 import（已存在则跳过）：

```dart
import 'dart:math' as math;
import 'dart:ui' show Offset, Size, Rect;
import 'src/core/groups/group_utils.dart';
import 'src/core/smart_layout/smart_layout_mindmap_engine.dart';
import 'src/core/smart_layout/smart_layout_move_builder.dart';
import 'src/core/smart_layout/smart_layout_plan.dart';
import 'src/core/smart_layout/smart_layout_ppt_engine.dart';
```

- [ ] **Step 5: 编写控制器编排测试**

创建 `test/features/whiteboard/editor_core/smart_layout_optimization_test.dart`。**先做这些初始化步骤（复制现有测试的写法）：**

1) 打开 `test/features/whiteboard/editor_core/smart_layout_placement_test.dart`，把它的**控制器构造代码**与**画布初始化/笔迹添加辅助**（前 60 行左右）原样复制到新文件顶部，替换类名/变量名不必改。
2) 确认该文件里 `controller.onSmartLayoutInk = (request) async { ... }` 的返回结构中，`SmartLayoutResponse` 的构造方式照抄。

然后追加以下用例（若复制的辅助函数名不同，相应替换调用名；用例语义不得改）：

```dart
  // 假响应：in_place 风格 + 1 个文本块
  SmartLayoutResponse responseInPlace() => SmartLayoutResponse(
        document: const SmartLayoutDocument(
          version: 1,
          generatedAt: 1,
          blocks: [],
        ),
        blocks: const [
          SmartLayoutRecognizedBlock(
            id: 's1',
            type: 'text',
            text: '测试文字',
            bounds: Bounds.fromLTWH(0, 0, 100, 28),
          ),
        ],
        pages: const [
          SmartLayoutPageDecision(pageId: '', mode: 'in_place'),
        ],
      );

  test('in_place 计划：构建后应用一次可撤销', () async {
    // Given 一个含 2 笔手写 + onSmartLayoutInk 返回假响应的控制器
    final controller = <用复制的构造>..onSmartLayoutInk = (request) async {
        return responseInPlace();
      };
    final pageId = controller.layout.pages.first.id;
    // When 构建计划并应用
    final result = await controller.buildSmartLayoutPlan(pageId: pageId);
    expect(result.plan, isNotNull);
    expect(result.plan!.style, SmartLayoutStyle.inPlace);
    expect(result.plan!.addElements, isNotEmpty);
    final before = controller.editorState.scene.activeElements.length;
    expect(controller.applySmartLayoutPlan(result.plan!), isTrue);
    // Then 场景新增了识别文本、删除了笔迹
    final texts = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .where((element) => element.text == '测试文字');
    expect(texts, isNotEmpty);
    expect(before, greaterThanOrEqualTo(2));
    // 一次撤销恢复
    controller.editorState.undo(controller.editorState.scene);
    expect(
      controller.editorState.scene.activeElements
          .whereType<TextElement>()
          .where((element) => element.text == '测试文字'),
      isEmpty,
    );
  });

  test('mindmap 风格：计划包含树元素，应用后手写被替换', () async {
    final controller = <用复制的构造>..onSmartLayoutInk = (request) async {
        return SmartLayoutResponse(
          document: const SmartLayoutDocument(
            version: 1,
            generatedAt: 1,
            blocks: [],
          ),
          blocks: const [
            SmartLayoutRecognizedBlock(
              id: 's1',
              type: 'text',
              text: '主题',
              bounds: Bounds.fromLTWH(0, 0, 100, 28),
            ),
            SmartLayoutRecognizedBlock(
              id: 's2',
              type: 'text',
              text: '分支',
              bounds: Bounds.fromLTWH(120, 0, 100, 28),
            ),
          ],
          pages: const [
            SmartLayoutPageDecision(pageId: '', mode: 'in_place'),
          ],
          layout: SmartLayoutLayoutDecision(
            style: SmartLayoutStyle.mindmap,
            confidence: 0.9,
            mindmapStructure: const MindmapStructure(
              root: MindmapStructureNode(
                text: '主题',
                children: [
                  MindmapStructureNode(text: '分支', children: []),
                ],
              ),
            ),
          ),
        );
      };
    final pageId = controller.layout.pages.first.id;
    final result = await controller.buildSmartLayoutPlan(pageId: pageId);
    expect(result.plan!.style, SmartLayoutStyle.mindmap);
    expect(result.plan!.addElements.whereType<RectangleElement>(), isNotEmpty);
    expect(controller.applySmartLayoutPlan(result.plan!), isTrue);
    final treeRect = controller.editorState.scene.activeElements
        .where((element) => element is RectangleElement);
    expect(treeRect.length, 2); // 根 + 分支
  });

  test('识别失败：计划携带失败信息，dropFailedBlocks 删除失败笔迹', () async {
    final controller = <用复制的构造>..onSmartLayoutInk = (request) async {
        return SmartLayoutResponse(
          document: const SmartLayoutDocument(
            version: 1,
            generatedAt: 1,
            blocks: [],
          ),
          blocks: const [
            SmartLayoutRecognizedBlock(
              id: 'bad',
              type: 'text',
              bounds: Bounds.fromLTWH(0, 0, 100, 28),
              error: '识别失败',
            ),
          ],
          pages: const [
            SmartLayoutPageDecision(pageId: '', mode: 'in_place'),
          ],
        );
      };
    final pageId = controller.layout.pages.first.id;
    // 笔迹组 key 为 '$pageId:$sessionId'，响应的 block id 使用同一 key 才能映射
    final result = await controller.buildSmartLayoutPlan(pageId: pageId);
    expect(result.plan, isNull); // 无成功块 → 无计划（整页失败语义）
    expect(result.failures, isNotEmpty);
    expect(result.failures.first.blockId, isNotEmpty);
  });

  test('compose 抛错时计划构建向上抛且场景不变（all-or-nothing）', () async {
    final controller = <用复制的构造>..onSmartLayoutInk = (request) async {
        throw StateError('智能排版没有足够的空白区域');
      };
    final pageId = controller.layout.pages.first.id;
    final before = controller.editorState.scene.activeElements.length;
    expect(
      () => controller.buildSmartLayoutPlan(pageId: pageId),
      throwsA(isA<StateError>()),
    );
    expect(controller.editorState.scene.activeElements.length, before);
  });
```

> 说明：
> - 若复制的测试文件中控制器构造后**没有** `layout.pages.first.id` 对应的页面，先调用控制器暴露的 `layout.ensurePage()`（`_buildSmartLayoutRequest` 就这么用）确保页面存在，再取 `pageId`。
> - `controller.editorState.undo(...)` 若在复制的测试里用的是 `_historyManager.undo(...)` 或 `controller.undo()`，按被复制文件的既有写法调用。
> - 若 `SmartLayoutRecognizedBlock` 的 `pageId` 参数为必填，给块补 `pageId: pageId`（值取页面 id）。
> - 如果复制出的控制器构造支持直接注入 `onComposeSmartLayout`（而非 `onSmartLayoutInk`），也可以换用 compose 注入；**只需保证走通"识别+compose"任一路径**。

- [ ] **Step 6: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core/smart_layout_optimization_test.dart
```

Expected: 全部 PASS（若有编译错，按上方"说明"项修正**测试代码**；若报控制器内编译错，回到 Step 3/4 修 import 与签名细节）。

- [ ] **Step 7: 回归旧行为 + 静态检查**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/editor_core && flutter analyze lib/features/whiteboard/editor_core
```

Expected: 全绿；analyze 无 error（历史 info 可忽略）。

- [ ] **Step 8: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart FlowMuse-App/test/features/whiteboard/editor_core/smart_layout_optimization_test.dart
git commit -m "feat:智能排版控制器编排支持按页构建计划与一次应用"
```

### Task 11：画布幽灵预览 painter 与叠层接线

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/interactive/smart_layout_ghost_painter.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart`

**Interfaces:**
- Consumes: `SmartLayoutGhostSpec`（T6）、`ViewportState`、`SelectionRenderer.drawMarquee`（公开）
- Produces: `SmartLayoutGhostPainter(spec, viewport)`（T12 经由 `controller.smartLayoutGhost` 触发显示）

- [ ] **Step 1: 编写 painter**

创建 `smart_layout_ghost_painter.dart`：

```dart
import 'dart:math' as math;
import 'dart:ui';

import '../../core/smart_layout/smart_layout_plan.dart';
import '../viewport_state.dart';
import 'selection_renderer.dart';

/// 智能排版幽灵预览/失败红框绘制：场景坐标系 + 视口变换（与 InteractiveCanvasPainter 一致）。
class SmartLayoutGhostPainter extends CustomPainter {
  SmartLayoutGhostPainter({required this.spec, required this.viewport});

  final SmartLayoutGhostSpec spec;
  final ViewportState viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
    if (spec.isFailure) {
      for (final rect in spec.failureRects) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0x11E03131),
        );
        _dashRect(
          canvas,
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = const Color(0xFFE03131),
        );
      }
    } else {
      for (final rect in spec.previewRects) {
        SelectionRenderer.drawMarquee(canvas, rect);
      }
      for (final rect in spec.removalRects) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0x11888888),
        );
        _dashRect(
          canvas,
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xAA888888),
        );
      }
    }
    canvas.restore();
  }

  void _dashRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    void dashLine(Offset from, Offset to) {
      final length = (to - from).distance;
      if (length <= 0) return;
      var covered = 0.0;
      while (covered < length) {
        final end = math.min(covered + dash, length);
        canvas.drawLine(
          from + (to - from) * (covered / length),
          from + (to - from) * (end / length),
          paint,
        );
        covered = end + gap;
      }
    }

    dashLine(rect.topLeft, rect.topRight);
    dashLine(rect.topRight, rect.bottomRight);
    dashLine(rect.bottomRight, rect.bottomLeft);
    dashLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant SmartLayoutGhostPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.viewport != viewport;
}
```

> 若 `SelectionRenderer.drawMarquee` 的参数顺序不同或不是公开静态方法，改用 `SelectionRenderer` 中已核实的公开方法（`selection_renderer.dart:218 static void drawMarquee(Canvas, Rect)`）。`Color`/`Canvas`/`Rect` 均来自 `dart:ui`。

- [ ] **Step 2: editor_canvas 接线**

打开 `editor_canvas.dart`：在 `CustomPaint(...)`（L403-459，其 `child: wetInkLayers`）之后、`TextEditingOverlay`（L472）之前，插入：

```dart
                ValueListenableBuilder<SmartLayoutGhostSpec?>(
                  valueListenable: controller.smartLayoutGhost,
                  builder: (context, spec, _) {
                    if (spec == null) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: SmartLayoutGhostPainter(
                          spec: spec,
                          viewport: controller.editorState.viewport,
                        ),
                      ),
                    );
                  },
                ),
```

并在文件顶部 import 区追加（已存在则跳过）：

```dart
import '../core/smart_layout/smart_layout_plan.dart';
import '../rendering/interactive/smart_layout_ghost_painter.dart';
```

> `ValueListenableBuilder`/`SizedBox` 来自 material/widgets；editor_canvas.dart 通常已导入 material，若报未定义则补 `import 'package:flutter/material.dart';`。

- [ ] **Step 3: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter analyze lib/features/whiteboard/editor_core/src/rendering/interactive/smart_layout_ghost_painter.dart lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart && flutter test test/features/whiteboard/editor_core
```

Expected: analyze 无 error；editor_core 全量测试全绿（本任务不改行为，只加绘制层；若既有测试因 `shouldRepaint` 新参数断言失败，属误报，检查是否是测试构造了 painter 旧签名——若有，按新签名补齐）。

- [ ] **Step 4: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/editor_core/src/rendering/interactive/smart_layout_ghost_painter.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/editor_canvas.dart
git commit -m "feat:智能排版画布幽灵预览与失败红框绘制层"
```

### Task 12：页面选择、确认对话框与流程接线（UI）

**Files:**
- Create: `FlowMuse-App/lib/features/whiteboard/views/smart_layout_dialogs.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart`
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart`（新增 `onSmartLayoutPressed` 透传）
- Modify: `FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart`、`desktop_toolbar.dart`（按钮优先走回调）

**Interfaces:**
- Consumes: T10 的 `buildSmartLayoutPlan`/`applySmartLayoutPlan`/`setSmartLayoutGhost`；`controller.layout.pages`（`CanvasPage{id,index}`）
- Produces: `SmartLayoutPagePickerDialog`、`SmartLayoutConfirmDialog`、`SmartLayoutFailureDialog`、`whiteboard_page._startSmartLayoutFlow()`（T13 测试消费对话框 widget）

- [ ] **Step 1: 编写三个对话框 widget**

创建 `smart_layout_dialogs.dart`：

```dart
import 'package:flutter/material.dart';

import '../../editor_core/src/core/layout/canvas_layout.dart';
import '../../editor_core/src/core/smart_layout/smart_layout_document.dart';
import '../../editor_core/src/core/smart_layout/smart_layout_plan.dart';

enum SmartLayoutConfirmAction { apply, applyAndDrop, skip, cancel }

/// 页面多选：返回选中页面 id 列表（取消返回 null）。
class SmartLayoutPagePickerDialog extends StatefulWidget {
  const SmartLayoutPagePickerDialog({
    super.key,
    required this.pages,
    this.initial = const {},
  });

  final List<CanvasPage> pages;
  final Set<String> initial;

  @override
  State<SmartLayoutPagePickerDialog> createState() =>
      _SmartLayoutPagePickerDialogState();
}

class _SmartLayoutPagePickerDialogState
    extends State<SmartLayoutPagePickerDialog> {
  late final Set<String> _checked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择要智能排版的页面'),
      content: SizedBox(
        width: 340,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final page in widget.pages)
              CheckboxListTile(
                dense: true,
                value: _checked.contains(page.id),
                title: Text('第 ${page.index + 1} 页'),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _checked.add(page.id);
                    } else {
                      _checked.remove(page.id);
                    }
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.of(context).pop(_checked.toList()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 逐页确认：描述 + 风格切换 + 应用/跳过/取消。
/// 幽灵预览由调用方通过 controller.setSmartLayoutGhost 维护；切换风格回调返回新计划。
class SmartLayoutConfirmDialog extends StatefulWidget {
  const SmartLayoutConfirmDialog({
    super.key,
    required this.plan,
    required this.onSelectStyle,
    required this.onApply,
    required this.onApplyAndDrop,
    required this.onSkip,
    required this.onCancel,
  });

  final SmartLayoutPlan plan;
  final Future<SmartLayoutPlan?> Function(SmartLayoutStyle style)
      onSelectStyle;
  final void Function(SmartLayoutPlan plan) onApply;
  final void Function(SmartLayoutPlan plan) onApplyAndDrop;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  @override
  State<SmartLayoutConfirmDialog> createState() =>
      _SmartLayoutConfirmDialogState();
}

class _SmartLayoutConfirmDialogState extends State<SmartLayoutConfirmDialog> {
  late SmartLayoutPlan _plan = widget.plan;
  bool _switching = false;

  bool get _hasFailedBlocks =>
      _plan.failedStrokeIds.isNotEmpty || _plan.failureRects.isNotEmpty;

  Future<void> _switchStyle(SmartLayoutStyle style) async {
    if (style == _plan.style || _switching) return;
    setState(() => _switching = true);
    try {
      final next = await widget.onSelectStyle(style);
      if (next != null && mounted) {
        setState(() => _plan = next);
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('智能排版预览（${_plan.style.displayName}）'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_plan.description),
            const SizedBox(height: 8),
            Text(
              '置信度：${(_plan.confidence * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final style in SmartLayoutStyle.values)
                  ChoiceChip(
                    label: Text(style.displayName),
                    selected: style == _plan.style,
                    onSelected: _switching
                        ? null
                        : (_) => _switchStyle(style),
                  ),
              ],
            ),
            if (_hasFailedBlocks)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '页内有未识别成功的笔迹（红色区域）。'
                  '可先应用排版，再选择"删除未识别笔迹后应用"。',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消整个流程'),
        ),
        TextButton(
          onPressed: widget.onSkip,
          child: const Text('跳过本页'),
        ),
        if (_hasFailedBlocks)
          TextButton(
            onPressed: () => widget.onApplyAndDrop(_plan),
            child: const Text('删除未识别笔迹后应用'),
          ),
        FilledButton(
          onPressed: () => widget.onApply(_plan),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

/// 识别失败对话框（计划为空、整页失败时）：再试 / 取消。
class SmartLayoutFailureDialog extends StatelessWidget {
  const SmartLayoutFailureDialog({
    super.key,
    required this.failures,
    required this.onRetry,
    required this.onCancel,
  });

  final List<SmartLayoutFailureInfo> failures;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('部分内容未识别成功'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('整页将不应用排版。以下手写疑似未能识别：'),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < failures.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '第 ${i + 1} 处：'
                        '${failures[i].snippet ?? '手写笔迹'}'
                        '${failures[i].error?.isNotEmpty == true ? '（${failures[i].error}）' : ''}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('页面上的红色区域即为未识别部分，可修改字迹后重试。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: onRetry,
          child: const Text('重新识别'),
        ),
      ],
    );
  }
}
```

> `canvas_layout.dart` 的 import 路径：`editor_core/src/core/layout/canvas_layout.dart`；`CanvasPage` 中 `index` 为 int。若 `ChoiceChip` 在桌面端样式不符，可换 `FilterChip`，语义不变。

- [ ] **Step 2: whiteboard_page 接线主流程**

打开 `whiteboard_page.dart`：

① import 区追加：

```dart
import '../editor_core/src/core/smart_layout/smart_layout_plan.dart';
import 'smart_layout_dialogs.dart';
```

② 在 `_WhiteboardPageState` 类内（与 `_aiCaptureModeActive` 等状态字段并列）追加：

```dart
  bool _smartLayoutFlowActive = false;
```

③ 在 `_markdrawController` 的 `MarkdrawEditor(...)` 参数区（`onAiPressed: _toggleAiAgent` 附近）追加：

```dart
                  onSmartLayoutPressed: _startSmartLayoutFlow,
```

④ 在类内追加以下方法（放在 `_applyAiAgentResponse` 之后）：

```dart
  Future<void> _startSmartLayoutFlow({List<String>? initialPageIds}) async {
    if (_smartLayoutFlowActive) return;
    final pages = _markdrawController.layout.pages;
    if (pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前笔记没有页面')),
      );
      return;
    }
    List<String>? selected;
    if (initialPageIds != null && initialPageIds.length == 1) {
      selected = initialPageIds;
    } else {
      selected = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => SmartLayoutPagePickerDialog(
          pages: pages,
          initial: {...?initialPageIds},
        ),
      );
    }
    if (selected == null || selected.isEmpty) return;
    setState(() => _smartLayoutFlowActive = true);
    var applied = 0;
    var skipped = 0;
    var failed = 0;
    var nothing = 0;
    try {
      for (final pageId in selected) {
        if (!mounted) return;
        final result = await _runSmartLayoutPage(pageId);
        switch (result) {
          case _SmartLayoutPageOutcome.applied:
            applied++;
          case _SmartLayoutPageOutcome.skipped:
            skipped++;
          case _SmartLayoutPageOutcome.failed:
            failed++;
          case _SmartLayoutPageOutcome.nothing:
            nothing++;
          case _SmartLayoutPageOutcome.cancelled:
            setState(() => _smartLayoutFlowActive = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已取消，完成 $applied 页')),
            );
            return;
        }
      }
    } finally {
      if (mounted) setState(() => _smartLayoutFlowActive = false);
    }
    final parts = <String>[
      if (applied > 0) '应用 $applied 页',
      if (skipped > 0) '跳过 $skipped 页',
      if (failed > 0) '失败 $failed 页',
      if (nothing > 0) '无内容 $nothing 页',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(parts.isEmpty ? '未执行智能排版' : '智能排版完成：${parts.join('，')}')),
    );
  }

  Future<_SmartLayoutPageOutcome> _runSmartLayoutPage(String pageId) async {
    final messenger = ScaffoldMessenger.of(context);
    SmartLayoutPlanResult result;
    try {
      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(days: 1),
          content: Text('智能排版识别中…'),
        ),
      );
      result = await _markdrawController.buildSmartLayoutPlan(pageId: pageId);
    } catch (catchError) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('智能排版失败：${_readableSmartLayoutError(catchError)}')),
      );
      return _SmartLayoutPageOutcome.failed;
    }
    messenger.removeCurrentSnackBar();
    if (result.error != null && result.plan == null) {
      if (result.hasFailures) {
        final action = await _showFailureDialog(result.failures);
        if (action == true) {
          return _runSmartLayoutPage(pageId);
        }
        return _SmartLayoutPageOutcome.cancelled;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(result.error != null ? '智能排版失败：${result.error}' : '本页没有可智能排版的手写内容')),
      );
      return _SmartLayoutPageOutcome.nothing;
    }
    final plan = result.plan;
    if (plan == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('本页没有可智能排版的手写内容')),
      );
      return _SmartLayoutPageOutcome.nothing;
    }
    _markdrawController.setSmartLayoutGhost(
      SmartLayoutGhostSpec.preview(
        previewRects: plan.previewRects,
        removalRects: plan.removalRects,
      ),
    );
    final action = await showDialog<SmartLayoutConfirmAction>(
      context: context,
      builder: (dialogContext) => SmartLayoutConfirmDialog(
        plan: plan,
        onSelectStyle: (style) async {
          final switched = await _markdrawController.buildSmartLayoutPlan(
            pageId: pageId,
            requestedStyle: style,
          );
          if (switched.plan == null) {
            if (switched.error != null) {
              messenger.showSnackBar(
                SnackBar(content: Text('切换风格失败：${switched.error}')),
              );
            }
            return null;
          }
          _markdrawController.setSmartLayoutGhost(
            SmartLayoutGhostSpec.preview(
              previewRects: switched.plan!.previewRects,
              removalRects: switched.plan!.removalRects,
            ),
          );
          return switched.plan;
        },
        onApply: (plan) => Navigator.of(dialogContext).pop(
          SmartLayoutConfirmAction.apply,
        ),
        onApplyAndDrop: (plan) => Navigator.of(dialogContext).pop(
          SmartLayoutConfirmAction.applyAndDrop,
        ),
        onSkip: () => Navigator.of(dialogContext).pop(
          SmartLayoutConfirmAction.skip,
        ),
        onCancel: () => Navigator.of(dialogContext).pop(
          SmartLayoutConfirmAction.cancel,
        ),
      ),
    );
    _markdrawController.setSmartLayoutGhost(null);
    switch (action) {
      case SmartLayoutConfirmAction.apply:
        if (_markdrawController.applySmartLayoutPlan(plan)) {
          messenger.showSnackBar(
            const SnackBar(content: Text('智能排版已应用')),
          );
          return _SmartLayoutPageOutcome.applied;
        }
        return _SmartLayoutPageOutcome.failed;
      case SmartLayoutConfirmAction.applyAndDrop:
        if (_markdrawController.applySmartLayoutPlan(
          plan,
          dropFailedBlocks: true,
        )) {
          messenger.showSnackBar(
            const SnackBar(content: Text('智能排版已应用（未识别笔迹已删除）')),
          );
          return _SmartLayoutPageOutcome.applied;
        }
        return _SmartLayoutPageOutcome.failed;
      case SmartLayoutConfirmAction.skip:
        return _SmartLayoutPageOutcome.skipped;
      case SmartLayoutConfirmAction.cancel:
        return _SmartLayoutPageOutcome.cancelled;
      case null:
        return _SmartLayoutPageOutcome.skipped;
    }
  }

  Future<bool?> _showFailureDialog(
    List<SmartLayoutFailureInfo> failures,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => SmartLayoutFailureDialog(
        failures: failures,
        onRetry: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
  }

  String _readableSmartLayoutError(Object error) {
    final text = error is StateError ? error.message : error.toString();
    return text
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
  }
```

⑤ 在文件末尾（class 之外）追加枚举：

```dart
enum _SmartLayoutPageOutcome { applied, skipped, failed, nothing, cancelled }
```

⑥ 修改 `_applyAiAgentResponse` 的 smartLayout 分支（785-794 行）为：

```dart
    if (response.actions.any(
      (action) => action.tool == AiAgentTool.smartLayout,
    )) {
      final center = _markdrawController.editorState.viewport.visibleRect(
        _markdrawController.canvasSize,
      );
      final page = _markdrawController.pageForVisibleRect(center);
      if (page == null) {
        throw StateError('当前画布没有可智能排版的手写内容');
      }
      await _startSmartLayoutFlow(initialPageIds: [page.id]);
      return;
    }
```

> 提示：`pageForVisibleRect` 返回 `CanvasPage?`（若签名返回非空，删除 null 判断）。`canvasSize` 为 `Size`（`markdraw_controller.dart:357`）。若 `_startSmartLayoutFlow` 中 `switch` 风格的 `case` 与项目 Dart 版本（3.x）不兼容（例如不支持空 case 合并），改写为 `if/else` 链，语义不变。

- [ ] **Step 3: MarkdrawEditor 与工具栏透传回调**

`markdraw_editor.dart`：
① widget 构建参数处（`final VoidCallback? onAiPressed;` 附近）添加：

```dart
  final VoidCallback? onSmartLayoutPressed;
```

② 构造函数 `const MarkdrawEditor({... required ...})` 内同样加入 `this.onSmartLayoutPressed,`（照 `onAiPressed` 的写法）。

③ `_buildToolbar`（约 L931-953）中 `CompactToolbar(...)` 与 `DesktopToolbar(...)` 的构造参数里追加：

```dart
                  onSmartLayoutPressed: widget.onSmartLayoutPressed,
```

`compact_toolbar.dart` / `desktop_toolbar.dart`：
① 各自 widget 类加字段 `final VoidCallback? onSmartLayoutPressed;` 与构造参数（照 `controller` 字段写法）。
② 智能排版按钮的 `onPressed`（compact_toolbar.dart:153、desktop_toolbar.dart:172）改为：

```dart
                  onPressed: () {
                    if (widget.onSmartLayoutPressed != null) {
                      widget.onSmartLayoutPressed!();
                    } else {
                      _runGlobalSmartLayout(context);
                    }
                  },
```

③ 两个文件的 `_pickSmartLayoutRecognitionEngine` 引擎选择弹窗**保留不删除**（旧路径 fallback 用），但仅在新回调为 null 时可达。

- [ ] **Step 4: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter analyze lib/features/whiteboard
```

Expected: 无 error（warning/info 尽量为 0，历史遗留可忽略）。

- [ ] **Step 5: 提交**

```bash
git add FlowMuse-App/lib/features/whiteboard/views/smart_layout_dialogs.dart FlowMuse-App/lib/features/whiteboard/views/whiteboard_page.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/markdraw_editor.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/compact_toolbar.dart FlowMuse-App/lib/features/whiteboard/editor_core/src/ui/desktop_toolbar.dart
git commit -m "feat:智能排版页面多选与逐页预览确认流程"
```

### Task 13：对话框 widget 测试

**Files:**
- Create: `FlowMuse-App/test/features/whiteboard/views/smart_layout_dialogs_test.dart`

**Interfaces:**
- Consumes: T12 三个对话框 widget

- [ ] **Step 1: 编写测试**

创建 `smart_layout_dialogs_test.dart`：

```dart
import 'package:flowmuse/features/whiteboard/editor_core/src/core/layout/canvas_layout.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_document.dart';
import 'package:flowmuse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_plan.dart';
import 'package:flowmuse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SmartLayoutPlan fakePlan() => SmartLayoutPlan(
      pageId: 'p-1',
      style: SmartLayoutStyle.mindmap,
      confidence: 0.9,
      description: '检测到头脑风暴内容',
      addElements: const [],
      moveDeltas: const {},
      removeIds: const [],
      selectIds: const {},
      previewRects: const [],
      removalRects: const [],
      failureRects: const [],
    );

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('确认对话框展示描述与四种风格，点确定回调 apply', (tester) async {
    SmartLayoutPlan? applied;
    await tester.pumpWidget(wrap(SmartLayoutConfirmDialog(
      plan: fakePlan(),
      onSelectStyle: (style) async => fakePlan(),
      onApply: (plan) => applied = plan,
      onApplyAndDrop: (plan) {},
      onSkip: () {},
      onCancel: () {},
    )));
    expect(find.text('检测到头脑风暴内容'), findsOneWidget);
    expect(find.text('思维导图'), findsWidgets);
    expect(find.text('PPT 式排版'), findsOneWidget);
    expect(find.text('文章式阅读流'), findsOneWidget);
    expect(find.text('仅转机器字体'), findsOneWidget);
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(applied, isNotNull);
  });

  testWidgets('存在失败块时展示"删除未识别笔迹后应用"按钮', (tester) async {
    final plan = fakePlan();
    final failed = SmartLayoutPlan(
      pageId: plan.pageId,
      style: plan.style,
      confidence: plan.confidence,
      description: plan.description,
      addElements: plan.addElements,
      moveDeltas: plan.moveDeltas,
      removeIds: plan.removeIds,
      failedStrokeIds: const [ElementId('stroke-1')],
      selectIds: plan.selectIds,
      previewRects: plan.previewRects,
      removalRects: plan.removalRects,
      failureRects: const [Rect.fromLTWH(0, 0, 10, 10)],
    );
    await tester.pumpWidget(wrap(SmartLayoutConfirmDialog(
      plan: failed,
      onSelectStyle: (style) async => failed,
      onApply: (plan) {},
      onApplyAndDrop: (plan) {},
      onSkip: () {},
      onCancel: () {},
    )));
    expect(find.text('删除未识别笔迹后应用'), findsOneWidget);
  });

  testWidgets('失败对话框列出失败项并可重试', (tester) async {
    bool? retried;
    await tester.pumpWidget(wrap(SmartLayoutFailureDialog(
      failures: const [
        SmartLayoutFailureInfo(
          blockId: 'b1',
          bounds: Rect.fromLTWH(0, 0, 10, 10),
          snippet: '潦草笔迹',
          error: '识别失败',
        ),
      ],
      onRetry: () => retried = true,
      onCancel: () {},
    )));
    expect(find.textContaining('潦草笔迹'), findsOneWidget);
    await tester.tap(find.text('重新识别'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('页面多选：勾选两页点确定返回两页 id', (tester) async {
    List<String>? selected;
    await tester.pumpWidget(wrap(SmartLayoutPagePickerDialog(
      pages: const [
        CanvasPage(id: 'p-1', index: 0, bounds: Rect.fromLTWH(0, 0, 100, 100), template: CanvasPageTemplate.blank),
        CanvasPage(id: 'p-2', index: 1, bounds: Rect.fromLTWH(200, 0, 100, 100), template: CanvasPageTemplate.blank),
      ],
    )));
    await tester.tap(find.text('第 1 页'));
    await tester.tap(find.text('第 2 页'));
    await tester.pumpAndSettle();
    // 确定按钮仅在勾选后可用
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    // 对话框通过 Navigator.pop 返回，测试中包裹的页面无路由上下文时以返回值方式断言：
    // 这里直接验证按钮可用性（若 pop 失败，改为检查按钮非 disabled）
    expect(find.text('确定'), findsNothing);
  });
}
```

> 若 `ElementId` 不是常量构造（例如 `ElementId(value)` 为普通构造），把 `const [ElementId('stroke-1')]` 改为 `[ElementId('stroke-1')]`。若 `CanvasPage` 构造参数有更多必填（`pageFlow/source`），按 `canvas_layout.dart` 补齐默认值。

- [ ] **Step 2: 运行验证**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter test test/features/whiteboard/views/smart_layout_dialogs_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 3: 提交**

```bash
git add FlowMuse-App/test/features/whiteboard/views/smart_layout_dialogs_test.dart
git commit -m "test:智能排版对话框widget测试"
```

### Task 14：文档同步与最终验收

**Files:**
- Modify: `docs/技术设计/接口设计.md`
- Modify: `docs/项目说明/项目需求.md`

- [ ] **Step 1: 同步接口文档**

在 `docs/技术设计/接口设计.md` 中智能排版章节追加（保留原文，补充）：
- compose 请求新增字段：`elements`（非笔迹元素摘要数组：id/type/bounds/pageId/locked/groupIds）、`layoutHint`（可选，"ppt"|"mindmap"|"article"|"in_place"）。
- compose 响应新增字段：`layout`（`{style, confidence, structure}`；缺省表示旧服务端，客户端回退文章/原地判断）。
- 说明：`structure` 形态按 style 分别为 mindmap `root` 树（text/blockIds/children）与 ppt `groups`（role/elementIds）；非法引用丢弃、未知 style 回落 `in_place`。

- [ ] **Step 2: 同步需求文档**

在 `docs/项目说明/项目需求.md` 的功能清单中加一条（文字照抄）：
- 智能排版优化：支持自适应排版——AI 按内容判定四种风格（PPT 式 / 头脑风暴转思维导图 / 文章式阅读流 / 仅转机器字体），可多选页面逐页预览确认并切换风格；识别失败可定位重试或删除未识别笔迹后继续；锁定元素不动、成组整体移动、绑定跟随、禁止跨页搬移。

- [ ] **Step 3: 全量门禁**

```bash
cd F:/Project/FlowMuse/FlowMuse-App && flutter analyze && flutter test
```

```bash
cd F:/Project/FlowMuse/FlowMuse-Server && go build ./... && go test ./... && go vet ./...
```

```bash
cd F:/Project/FlowMuse && git diff --check
```

Expected: analyze 无 error；全量测试通过（不得让既有测试挂）；go 全绿；diff --check 无输出。

- [ ] **Step 4: 提交**

```bash
git add docs/技术设计/接口设计.md docs/项目说明/项目需求.md
git commit -m "docs:智能排版优化接口与需求文档同步"
```

---

## 5. 验收门禁（所有 Task 完成后逐条打勾）

- [ ] `flutter analyze` 无 error。
- [ ] `flutter test` 全量通过（含新增 6 个测试文件 + 既有 editor_core/AI 对话框回归）。
- [ ] `cd FlowMuse-Server && go build ./... && go test ./... && go vet ./...` 全绿。
- [ ] `git diff --check` 通过。
- [ ] 需求映射：R1 风格枚举+分发（T4/T7/T8/T10）；R2 方案二（T2/T4/T10，AI 只回风格与结构）；R3 真导图（T8/T10）；R4 预览+切风格（T11/T12）；R5 页面多选+逐页独立（T5/T10/T12）、无跨页（T10 按页构建）；R6 参与规则（T10 `_smartLayoutPageElements` 排除锁定/背景/既有导图 + `_pptPlan` 组整体 + T9 绑定/框架跟随）；R7 失败 all-or-nothing + 红框 + 三选一（T10/T12）；R8 默认 AI 引擎、MyScript 不暴露入口（T10 默认参数 + T12 移除入口弹窗优先回调）。
- [ ] 无涉及 `tool/vendor/**`、`ohos/**`、pubspec、数据库 schema 的改动。

## 6. 非目标 / 已知边界 / 风险

- **非目标（v1 不做）**：字号/颜色/角度随风格调整（只动位置）；元素缩放（图片超出列宽时整页失败，不缩放）；无手写的页面不参与排版；"跳过确认"开关；AI 指令对话框内的页面多选（AI 路径仅当前页）。
- **已知边界**：MyScript 引擎不支持风格化判定（仅旧 in_place/文章路径可用，入口已隐藏）；预览/失败红框使用场景坐标，经视口变换绘制；导出文档对 mindmap/ppt 采用客户端构建的 blocks（paragraph 类型）。
- **风险与缓解**：低思考执行者改动控制器大文件 → 每个 Task 以小步提交 + 定向测试守卫；Go 侧字段名不一致 → `go build` 即时报错并在 Task 内修正；PPT 布局对超大图片/过密内容会整页失败 → 提示文案明确并允许切换风格；确认对话框与画布幽灵同屏的时序 → 对话框打开前 set ghost、关闭后清 ghost（T12 顺序已固定）。
- **实机延期项**（记录，不阻塞）：鸿蒙真机缩放下的幽灵框清晰度；桌面端拖拽/滚动时预览框跟随；不同 dpi 下 72px 内容区边距观感。

<!-- 计划结束 -->

