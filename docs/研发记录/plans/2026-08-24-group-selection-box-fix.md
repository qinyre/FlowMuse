# 修复：选中组合元素时只显示最外层虚线框

> 分支建议：`feature/fix-group-select-box`（从 `main` 拉出，不基于 `feature/ai-visual-attachment`；当前工作区有无关未提交文件，勿混入）
> 定位：选中一个组合（群组）元素时，画布冒出每个成员元素的选中框；需求是**只保留最外层虚线框 + 手柄**，隐藏内部成员框。
> 原则：仅改选中 overlay 的「构图」环节（哪层画框、画几个框），不动数据模型、Excalidraw JSON、协作协议、数据库；不改成员轮廓画法本身（真多选场景仍保留 Excalidraw 风格的逐元素轮廓）。

## 0. 事实基线（撰写当日逐行核实）

| 主题 | 事实 | 位置 |
|---|---|---|
| 点击带群组元素的选择逻辑 | `_handleClick` 经 `GroupUtils.resolveGroupForClick` 求出最外层 groupId，随后 `SetSelectionResult(全部成员 id)`——多成员同时进入选中态 | `select_tool.dart:287-323` |
| 组合单元的唯一性 | 群组是隐式的（成员共享 `groupIds`，外层靠后 `[inner..., outer]`），无独立 group 对象；可用 `findGroupMembers` 从场景反查成员全集 | `group_utils.dart:6-30` |
| 选择 overlay 建造 | `buildSelectionOverlay()`：selectedIds → 元素列表 → `SelectionOverlay.fromElements` | `markdraw_controller.dart:2781-2789` |
| 多选触发内部框 | `fromElements` 中 `elements.length > 1` → 填充 `elementBounds`（逐元素包围盒，供内层框绘制） | `selection_overlay.dart:128-137` |
| 内部框的绘制入口 | painter 以 `elementBounds.isNotEmpty` 判定 `isMultiSelect` → 先画逐元素轮廓（solid 内层框），再画 union 虚线框 + 手柄 | `interactive_canvas_painter.dart:110-145` |
| 虚线外框/实心内框 | union 框用 `drawDashedSelectionBox`（虚线）；逐元素轮廓用 `drawElementOutlines`（实线细框）。截图缩放下内层框观感亦为细线 | `selection_renderer.dart:137-194` |
| 手柄命中测试 | `_hitTestHandle` 只用 overlay 的 bounds/handles/angle，与 `elementBounds` 无关 | `select_tool.dart:608-630` |
| 现有测试 | editor_core 目录下**无** `SelectionOverlay` / group 选择渲染相关测试 | `test/features/whiteboard/editor_core/` |
| 陈旧选中 | 撤销等场景可能出现 selectedIds 中元素已被删除的情况；`buildSelectionOverlay` 会 `.whereType<Element>()` 静默剔除 | `markdraw_controller.dart:2783-2787` |

**根因**：点击组合元素 → 全部成员 id 进入选中态 → `fromElements` 按「元素数 > 1」判定为纯多选 → 填充 `elementBounds` → painter 逐个成员画轮廓框。当前实现无法区分「组合单元选中」与「多个独立元素多选」。

## 1. 需求

1. 选中一个组合（任意层级的完整群组）时：只显示最外层 union 虚线框 + 手柄，**不显示**成员元素各自的内层框。
2. 仅选中单个成员（逐级钻入到个体）时维持现状（单框 + 手柄，无 member 框）。
3. 多个**独立**元素多选（框选/Shift 多选，非同一组合）维持现状：逐元素轮廓 + union 虚线框（Excalidraw 风格，不动）。
4. 拖拽/缩放/旋转/layer 顺序/属性面板等交互全部不受影响；本改动纯视觉构成层。

## 2. 实现方案

### 2.1 判定函数（纯函数，可单测）

新新增 `GroupUtils.isCompleteGroupSelection(Scene scene, List<Element> selected)`：

```dart
/// 选中的元素是否恰好构成某个群组的完整成员集（组合选中）。
/// 规则：从外层到内层遍历所有成员共享的 groupId；
/// 若某一层的场景成员全集 == 当前选中集，则视为组合选中（true）。
static bool isCompleteGroupSelection(Scene scene, List<Element> selected) {
  if (selected.length < 2) return false;
  final first = selected.first;
  // 每个元素的 groupIds 含义一致（内层在前，外层在后），沿第一个元素由外向内检查
  for (var i = first.groupIds.length - 1; i >= 0; i--) {
    final gid = first.groupIds[i];
    if (!selected.every((e) => e.groupIds.contains(gid))) {
      continue; // 该层非全员共享，继续向内层找
    }
    final members = findGroupMembers(scene, gid).map((e) => e.id).toSet();
    final ids = selected.map((e) => e.id).toSet();
    if (members.length == ids.length && members.containsAll(ids)) {
      return true;
    }
  }
  return false;
}
```

要点：

- 嵌套组正确性：选中内层子组时外层 groupId 共享但成员全集大于选中集 → 继续向内层检查 → 内层匹配即 true。
- 陈旧/部分选中：选中集 ≠ 该层成员全集时不会误判 true（多画几个内层框本来也是现状，无回归风险）。
- 空/单元素直接 false。

### 2.2 SelectionOverlay 增加「组合单元」位

- `SelectionOverlay` 新增字段 `final bool isGroupUnit`（默认 `false`）；构造函数传入；参与 `==` / `hashCode`（与现有字段并列加 `isGroupUnit == other.isGroupUnit`）。
- `fromElements(..., {bool isGroupUnit = false})`：
  - `isGroupUnit == true` 时强制 `elementBounds = const []`（隐藏逐元素轮廓），其余（union bounds、handles、angle、showBoundingBox、isLocked）不变——外层虚线框与手柄自然保留。
  - 保持「isMultiSelect 视觉」的判定出口给 painter 用（见 2.3），避免外框从虚线悄悄变实线。

### 2.3 Painter 判定归并

`interactive_canvas_painter.dart` 中：

```dart
final isMultiSelect = selection!.elementBounds.isNotEmpty;
```
改为：
```dart
final isMultiSelect =
    selection!.elementBounds.isNotEmpty || selection!.isGroupUnit;
```

- `isGroupUnit = true` 时：`elementBounds` 为空 → 不画成员轮廓（需求 1）；`isMultiSelect = true` → union 框画虚线（需求 1 的外框不变）；手柄照画。
- 其余分支不动；`selection_overlay.dart` / `selection_renderer.dart` 的绘制函数本身不改。

### 2.4 接线

`markdraw_controller.dart buildSelectionOverlay()`：

```dart
final selected = ...;
if (selected.isEmpty) return null;
final isGroupUnit =
    GroupUtils.isCompleteGroupSelection(_editorState.scene, selected);
return SelectionOverlay.fromElements(
  selected,
  mode: interactionMode,
  isGroupUnit: isGroupUnit,
);
```

`GroupUtils` 方法，纯函数；`buildSelectionOverlay` 是唯一 overlay 构建点，`_hitTestHandle` 内部调用 `fromElements(elements, mode: mode)` 不传新参数 → 走默认 `false`，零影响。

### 2.5 不变量（本改动不触碰的边界）

- 不改 `SetSelectionResult` / `EditorState` / 历史（undo 不感知此标记，靠场景实时推导——陈旧选中自然回到旧渲染，不算回归）。
- 不改 Excalidraw JSON 编码（`groupIds` 语义不变）、不碰协作消息、不碰数据库 schema。
- 共享代码无任何平台分支、无新依赖、无 dart:io 引入，6 端零风险。
- 样式常量（颜色、线宽、padding）一律不动。

## 3. 关键文件

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/features/whiteboard/editor_core/src/core/groups/group_utils.dart` | 修改 | 新增 `isCompleteGroupSelection(Scene, List<Element>)` 纯函数 |
| `lib/features/whiteboard/editor_core/src/rendering/interactive/selection_overlay.dart` | 修改 | `SelectionOverlay` 新增 `isGroupUnit` 字段 + 构造参数 + `==`/`hashCode`；`fromElements` 在 `isGroupUnit` 时置空 `elementBounds` |
| `lib/features/whiteboard/editor_core/src/rendering/interactive/interactive_canvas_painter.dart` | 修改 | `isMultiSelect` 判定加入 `isGroupUnit` |
| `lib/features/whiteboard/editor_core/src/ui/markdraw_controller.dart` | 修改 | `buildSelectionOverlay()` 调用判定并传入 `isGroupUnit` |
| `test/features/whiteboard/editor_core/group_selection_overlay_test.dart` | 新建 | `isCompleteGroupSelection` + overlay 组合单元位用例 |
| `docs/研发记录/plans/2026-08-24-group-selection-box-fix.md` | 新建（即本文件） | 修复计划 |

> 本次改动属 UI 行为微调，不改架构/协议/数据模型，按 AGENTS.md §10 无需同步其他文档；如验收后确认语义变化，备忘在 `docs/研发记录/archive/` 即可。

## 4. 验证方案

1. `cd FlowMuse-App && flutter analyze`——不得新增 error。
2. 新增单测（T1，见 §5）。`flutter test test/features/whiteboard/editor_core/group_selection_overlay_test.dart` 通过。
3. `flutter test` 全量——既有用例无回归（editor_core 现有 40+ 测试全数保留）。
4. 手动验证（每条必测）：
   - 手写笔迹 + 文字 **Ctrl+G 组合** → 点击组合：只出现**最外层虚线框 + 手柄**，无成员内层框（复现截图场景）。
   - 再点一次钻入内层组合（若嵌套）：仍只有该层一个虚线框；重复点到底层个体 → 出现标准单元素实线框。
   - 框选框住**两个独立元素**：逐元素轮廓 + union 虚线框保持现状（回归点）。
   - 点击空白：清空选择无框；拖拽组合、旋转组合、缩放手柄：行为不变。
   - 撤销/重做后选中组合：边界正常（部分选中场景不误判组合单元）。
5. 跨端自检：纯共享 Dart + 条件无平台 API，Android/iOS/macOS/Windows/Web/鸿蒙 行为一致；无 `Platform.is*` 引入；无需动 `ohos/`、`tool/vendor/`（**不**需要 `flutter build hap`；如顺手跑一次以确保无构建回归更佳，非必须）。

## 5. 实施步骤（TDD）

### T1：纯函数 + 测试先行

1. 先在 `group_selection_overlay_test.dart` 写失败用例（构造小型 `Scene` / 元素桩）：
   - 单元素 → false；
   - 3 成员组合全选 → true；
   - 3 成员组合只含 2 成员（手动构造的“部分选中”）→ false；
   - 两个不同组合各取全成员 → false；
   - 嵌套：外层 2 子组，仅选内层子组 2 成员 → true；内外全选 → true；
   - 组合 + 一个独立元素混选 → false。
2. 实现 `GroupUtils.isCompleteGroupSelection`（§2.1），跑上面用例全绿。
3. `SelectionOverlay` 用例：
   - `fromElements([3 成员], isGroupUnit: true)` → `elementBounds` 为空、`isGroupUnit == true`、bounds 为 union、handles 9 个；
   - `fromElements([两个独立元素])` → `elementBounds` 非空；相等性含新字段。

### T2：Overlay 字段 + painter 接线

1. `selection_overlay.dart` 加字段与逻辑；`interactive_canvas_painter.dart` 改 `isMultiSelect` 判定。
2. 跑 `flutter analyze` + T1 全部用例。

### T3：controller 接线

1. `buildSelectionOverlay()` 调用 `GroupUtils.isCompleteGroupSelection` 并传入 `isGroupUnit`。
2. 跑 `flutter analyze` + `flutter test` 全量。
3. 手动按 §4 清单回归，确认见截图场景（组合元素只出现最外层虚线框）。

### 提交

- 中文提交信息，如：`fix:选中组合元素时只显示最外层虚线框`。
- 只提交本计划涉及文件；**排除**工作区已有无关修改（`tool/vendor/path_provider_ohos` 的 M 文件）。
