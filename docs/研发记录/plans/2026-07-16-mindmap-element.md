# 思维导图元素/工具实施计划

- **日期**：2026-07-16
- **分支**：`markdraw-mindmap`（从 `main` `e1fdc2e` 拉取）
- **状态**：已批准，待实施

## 背景与目标

为 FlowMuse 白板新增思维导图功能。用户可以在白板中创建思维导图：根节点在左，子节点横向向右展开，父子之间用平滑曲线连线。

设计必须同时满足：
1. **双端可用**——移动端（触屏无键盘）和桌面端（鼠标+键盘）都有完整的创建/编辑入口。
2. **AI 友好**——布局函数设计成"树输入 → 元素输出"，为未来 AI 一键生成思维导图留好入口（LLM 只输出简单树 JSON，绝不生成坐标/binding/id）。

## 核心架构决策

### 1. 不新建元素类型
节点 = `RectangleElement`（圆角）+ `TextElement`（`containerId` 绑定到矩形）；连线 = `ArrowElement`（`arrowType: ArrowType.round` 曲线 + `startBinding`/`endBinding`）。思维导图身份靠 `customData['flowMuse']['role'] == 'mindmap-node'` 标记。

**依据**：项目已有同构先例 `editor/flowchart/`，它完全靠组合现有元素实现了流程图，零新类型。新建元素类型要改 10+ 处硬编码分派点（序列化/渲染/SVG/binding 白名单/textContainer 白名单/shapeConverter/sketch_parser...），风险高收益低。

### 2. 曲线连线零新增渲染
复用现有 `ArrowType.round`——它调用的 `RoughCanvasAdapter.drawCurvedArrow`（`rough_canvas_adapter.dart:452-507`）已是"过所有点的平滑贝塞尔曲线 + 精准箭头"。只需在 `points` 数组中插入控制点（水平偏移的中点）产生 S 形弯曲。

**依据**：探索确认 `ArrowType.round` 在渲染、SVG 导出、Excalidraw 序列化、`.sketch` 序列化、属性面板中均已完整支持，零新增序列化成本。

### 3. 布局函数设计成"树输入 → 元素输出"
```
MindmapTree（简单树）  →  MindmapLayout.treeToElements()  →  List<Element>
（AI / 手动都可产出）       （确定性布局，纯本地几何计算）        （节点+文本+曲线连线）
```
- **手动交互**：用户点 + 按钮 → `appendChild(parent, text, scene)` → 增量加一个子节点
- **AI 生成**：LLM 返回树 JSON → `MindmapTree.fromJson()` → `treeToElements(tree)` → 整棵树一次性生成
- 两条路径共用同一套布局算法，AI 只负责"内容结构"，坐标/binding/id 全由代码保证正确

### 4. 双端交互统一（移动端优先）
移动端的核心痛点：默认开启"单指平移画布"，选中创建工具后单指 touch 被拦截用于平移，无法创建元素。且无键盘，flowchart 的 Ctrl+方向键模式不可用。

解法：**节点旁浮动 + 按钮 + 属性面板操作按钮**，绕开单指平移拦截，双端通用。

## 横向树形布局算法

根节点在左，子节点向右展开。布局规则（递归）：

```
layoutSubtree(node, x, y):
  if node.children.isEmpty:
    node.bounds = (x, y, nodeWidth, nodeHeight)
    return nodeHeight + vGap
  totalHeight = 0
  childX = x + nodeWidth + hGap          // 水平间距 80
  for child in node.children:
    subHeight = layoutSubtree(child, childX, y + totalHeight)
    totalHeight += subHeight
  // 父节点垂直居中于子节点群
  node.bounds = (x, y + (totalHeight - nodeHeight) / 2, nodeWidth, nodeHeight)
  return max(totalHeight, nodeHeight + vGap)
```

连线生成（每个父子对）：
- 起点 = 父节点右边缘中点
- 终点 = 子节点左边缘中点
- 控制点 = 起终点的水平中点（`ArrowType.round` 的 Catmull-Rom 贝塞尔自动平滑）
- `points = [起点(相对), 控制点(相对), 终点(相对)]`
- `startBinding`/`endBinding` 指向父子节点（拖动时自动跟随）

常量：`nodeWidth = 140`、`nodeHeight = 48`、`hGap = 80`、`vGap = 20`。

## 任务拆分

### 任务 1：思维导图数据模型与布局算法
**新建** `lib/features/whiteboard/editor_core/src/editor/mindmap/`：

- `mindmap_tree.dart`：
  - `class MindmapNode { String id; String text; List<MindmapNode> children; }`
  - `MindmapNode.fromJson(Map)` / `toJson()`（为 AI 生成预留）
- `mindmap_layout.dart`：
  - `class MindmapLayout`
  - `static List<Element> treeToElements(MindmapNode root, {Point? origin})` — 整棵树 → 元素
  - `static List<Element> appendChild(Element parentNode, String text, Scene scene)` — 增量加子节点（用于手动 + 按钮）
  - `static List<Element> addSibling(Element node, String text, Scene scene)` — 增量加同级
  - 内部：`_createNode(id, x, y, text)` 生成 RectangleElement(圆角) + TextElement(containerId)；`_createCurveArrow(parent, child)` 生成 ArrowElement(round + binding)，参考 `FlowchartUtils.createBindingArrow`（`flowchart_utils.dart:179-241`）
  - customData 标记：`{'flowMuse': {'role': 'mindmap-node'}}`（节点）/ `{'flowMuse': {'role': 'mindmap-edge'}}`（连线）
- `mindmap_utils.dart`：
  - `static bool isMindmapNode(Element e)` — 读 customData role
  - `static Element? findParent(Element node, Scene scene)` — 通过 binding 的 arrow 反查父节点
  - `static List<Element> findChildren(Element node, Scene scene)` — 通过 binding 的 arrow 查子节点
  - `static MindmapNode? rebuildTree(Element root, Scene scene)` — 从场景重建树结构
- `mindmap.dart`：barrel export

### 任务 2：MindmapCreator 状态机
**新建** `mindmap_creator.dart`，仿 `FlowchartCreator`（`flowchart_creator.dart`）：

```dart
class MindmapCreator {
  List<Element> _pendingElements = [];
  bool get isCreating => _pendingElements.isNotEmpty;
  List<Element> get pendingElements => _pendingElements;

  void createRoot(Point point);                    // 生成根节点预览
  void createChild(Element parentNode, Scene scene); // 生成子节点预览
  void createSibling(Element node, Scene scene);    // 生成同级预览
  ToolResult commit();   // → CompoundResult([AddElementResult...每个, SetSelectionResult])
  void clear();
}
```

### 任务 3：Controller 接入
**改** `src/ui/markdraw_controller.dart`（仿 flowchart 4288-4340 行）：

- 字段：`final _mindmapCreator = MindmapCreator();`
- getter：`mindmapCreator`、`pendingPreviewElements`（路由到当前活跃 creator）
- 方法：
  - `mindmapCreateRoot()` — 在视口中心创建根节点 → commit → 切回 select → 进入文字编辑
  - `mindmapAddChild()` — 给选中节点加子节点 → commit → 选中子节点 → 进入文字编辑
  - `mindmapAddSibling()` — 给选中节点加同级 → commit → 选中新节点 → 进入文字编辑
  - `mindmapCommit()` / `mindmapCancel()`
  - `_enterMindmapNodeEditing(Element node)` — 复用 `startBoundTextEditing` 模式
- 改 `isCreationTool`（549 行）和 `cursorForTool`（580 行）加 `mindmap` 分支

### 任务 4：MindmapTool 工具 + 枚举接入
**新建** `src/editor/tools/mindmap_tool.dart`（implements Tool）：
- 选中思维导图工具后点击画布空白 → `controller.mindmapCreateRoot()` → 自动切回 select
- 选中节点时点击空白不创建（避免误触）
- 单指 touch 不做平移拦截（思维导图工具豁免 `_usesTemporaryTouchPan`）

**改接入点**（穷举 switch，编译器强制覆盖）：
- `tool_type.dart`：加 `mindmap` 枚举值
- `tool_factory.dart`（18 行）：加 `ToolType.mindmap => MindmapTool()`
- `tools.dart` barrel：加 `export 'mindmap_tool.dart';`
- `tool_shortcuts.dart`：三个 switch 各加 case（`'m'` / `'M'` / `'思维导图'`）

### 任务 5：工具栏 UI
- `desktop_toolbar.dart`：加思维导图工具按钮
- `compact_toolbar.dart`：加思维导图工具按钮（移动端）
- `tool_icon.dart`：`iconFor` 和 `iconWidgetFor` 加 case（`Icons.account_tree`）

### 任务 6：节点旁浮动 + 按钮（移动端核心交互）
**改** `src/ui/editor_canvas.dart`：
- 在 `_CompactPropertyButton`（413 行）附近，当选中元素是思维导图节点时，在节点右边缘位置渲染一个浮动 `⊕` 按钮（Positioned + IconButton）
- 点击触发 `controller.mindmapAddChild()`（不经过画布 pointer down，绕开单指平移拦截）
- 桌面端也显示（鼠标用户也能点），但键盘用户可用 Tab 代替

### 任务 7：属性面板条件按钮
**改** `src/ui/property_panel_content.dart`（`_buildActionsRow` 781 行）：
- 当选中元素是思维导图节点时（`MindmapUtils.isMindmapNode`），在操作行增加：
  - 「+ 子节点」（`Icons.account_tree`）→ `controller.mindmapAddChild()`
  - 「+ 同级」（`Icons.low_priority`）→ `controller.mindmapAddSibling()`

### 任务 8：桌面端键盘快捷键
**改** `src/ui/keyboard_handler.dart`（仿 flowchart 130-158 行）：
- 选中思维导图节点时：`Tab` → `mindmapAddChild()`；`Enter` → `mindmapAddSibling()`；`Esc` → `mindmapCancel()`
- 思维导图采用"创建即提交"模式（无需 Ctrl-up 确认，比 flowchart 更简单）

### 任务 9：预览渲染通用化
**改** `src/ui/editor_canvas.dart`（348-350 行）：
- 把 `pendingElements` 从 flowchart 专属改为通用 `controller.pendingPreviewElements`
- getter 内部路由到当前活跃的 creator（flowchart 或 mindmap）

## 涉及文件清单

| 类型 | 文件 |
|---|---|
| **新建（6）** | `src/editor/mindmap/mindmap_tree.dart`、`mindmap_layout.dart`、`mindmap_utils.dart`、`mindmap_creator.dart`、`mindmap.dart`(barrel)、`src/editor/tools/mindmap_tool.dart` |
| **改-核心（5）** | `tool_type.dart`、`tool_factory.dart`、`tools.dart`、`tool_shortcuts.dart`、`markdraw_controller.dart` |
| **改-UI（4）** | `desktop_toolbar.dart`、`compact_toolbar.dart`、`tool_icon.dart`、`property_panel_content.dart` |
| **改-交互（2）** | `keyboard_handler.dart`、`editor_canvas.dart` |

## 不碰的部分

- Element 模型（不新增类型）
- ElementRenderer 渲染分支（复用 `ArrowType.round` 曲线）
- 序列化 codec（round 已支持）
- SVG 导出（round 已支持）
- 协作协议（元素是标准 Excalidraw，走现有 LWW）
- 数据库 schema

## AI 生成预留（未来 P1）

`MindmapLayout.treeToElements(MindmapNode)` 是 AI 生成的入口。未来 AI Agent 流程：

```
用户："根据当前笔记生成思维导图"
  → AI Agent 读取笔记文本
  → LLM 返回树 JSON：{"text":"软件工程","children":[{"text":"需求分析",...}]}
  → MindmapNode.fromJson(json)
  → MindmapLayout.treeToElements(tree)     ← 确定性布局，算坐标/binding/id
  → controller.applyResult(AddElements(elements))
  → 预览确认 → 插入画布
```

LLM 只输出内容结构（树），绝不生成坐标/binding/id——全部由布局算法保证正确。这与项目 AI Agent 方案的安全原则一致。

## 验证

- 每个任务完成后 `flutter analyze` 验证无错误
- 任务 1-2 完成后写单元测试（布局算法的坐标计算、树重建）
- 最终手动验证：双端创建思维导图、加子节点/同级、拖动连线跟随、撤销、保存重开
