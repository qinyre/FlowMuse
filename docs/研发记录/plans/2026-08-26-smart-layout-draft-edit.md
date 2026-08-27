# 智能排版草稿编辑态实施计划（预览即编辑：选中框 + 拖动 + 确认落地）

> 需求方逐条确认（2026-08-26）：点击智能排版后先展示**排版好的内容 + 各元素选取框**，用户可**拖动微调**，再**确认落地**。
> 逐问确认结论：Q1=A 仅拖动位置（不旋转/缩放/删除）；Q2=A 仅方案参与者可选可拖、默认全选可整组平移、点选单个；Q3 确认=一次历史提交（一次撤销），取消/跳过=场景完全还原零残留；Q4=A 红区标出不可选不可拖、保留"确认/删除未识别笔迹后确认"双入口；Q5=A 进入草稿自动整页适配视图、仅滚轮缩放、无自由平移。

## 背景与已知事实（已核实）

- `MarkdrawController extends ChangeNotifier`；`EditorState` 不可变，`applyResult(ToolResult)` → 新状态 + `notifyListeners()`；场景变更时 `onSceneChanged?.call(scene, userEdit)` 并调度笔迹识别（`applyResult` 内，markdraw_controller.dart:1061-1068）。
- 指针抬起提交：`applyResult(finalResult)` 后 `if (_sceneBeforeDrag != null && !identical(...)) _historyManager.push(_sceneBeforeDrag!)`（http://~2222-2246）。
- 工具结果不自行推历史；`pushHistory()` 由调用方在 apply 前调用。
- `Scene.softDeleteElement(ElementId)`、`Scene.getElementAtPoint(Point)`（跳过画布页/PDF 背景）、`Scene.updateElement/addElement` 均可用。
- `ViewportState.fitToBounds(Bounds?, Size, {padding})`（viewport_state.dart）、`controller.canvasSize`、`controller.layout.pages`。
- 选中渲染：`SelectionOverlay`/`InteractiveCanvasPainter` 按 `EditorState.selectedIds` 画框，天然支持"每参与者一个选取框 + 整组移动"。
- 拖动设施：`SelectTool` 多选移动（含网格吸附、对象吸附、绑定箭头/文本/frame 跟随），`SmartLayoutMoveBuilder.buildResults(scene, deltas)`。
- `smartLayoutGhost`（画布红框层）与底部条（`SmartLayoutConfirmBar`/`FailureBar`）已存在。

## 方案

### 1. 草稿态状态机（控制器）

新字段：

```dart
bool _smartLayoutDraftActive = false;
Scene? _draftBaseScene;                 // 进入前真实场景（还原基准）
Set<ElementId> _draftParticipants = {}; // 方案参与者（可选中可拖动）
ViewportState? _draftPreviousViewport;  // 取消时还原视口
```

新方法：

- `enterSmartLayoutDraft(SmartLayoutPlan plan)`
  1. `_draftBaseScene = _editorState.scene; _draftPreviousViewport = viewport;`
  2. `_draftParticipants = {...plan.moveDeltas.keys, ...plan.addElements.map((e) => e.id)}`
  3. 构建临时场景 `_buildDraftScene(plan)`（见下）。
  4. `_smartLayoutDraftActive = true`；
     `_editorState = _editorState.copyWith(scene: temp, selectedIds: _draftParticipants, activeToolType: ToolType.select, viewport: fitToBounds(页面 bounds))`；
     `_activeTool = createTool(ToolType.select)`；`notifyListeners()`。
     不调 `onSceneChanged`（草稿不得触发保存/协作广播）。

- `Scene _buildDraftScene(SmartLayoutPlan plan)`：按序折叠到副本：
  `RemoveElementResult(plan.removeIds)` → `SmartLayoutMoveBuilder.buildResults(base, plan.moveDeltas)` → `AddElementResult(合并 pageId 的 plan.addElements)`（用 `_applyResultToScene` 逐条 `softDeleteElement/updateElement/addElement`）。

- `bool commitSmartLayoutDraft(SmartLayoutPlan plan, {bool dropFailedBlocks = false})`
  1. 若未处于草稿态返回 false。
  2. 从草稿场景取每个参与者的**最终位置**：
     - 既有元素（plan.moveDeltas 键，且在 base 中存在且仍在草稿中）→ `finalDeltas[id] = 草稿位置 - base 位置`（仅记录有变化的）；
     - 新增元素（plan.addElements）→ `finalAdds` = 草稿中的该元素（id 一致，直接取）。
  3. `_smartLayoutDraftActive = false; _editorState = _editorState.copyWith(scene: _draftBaseScene);`
  4. `pushHistory(); applyResult(CompoundResult([ RemoveElementResult(removeIds + dropFailedBlocks 的 failedStrokeIds), ...SmartLayoutMoveBuilder.buildResults(base, finalDeltas), ...AddElementResult(finalAdds 元素，其 customData 已合并), SetSmartLayoutResult(plan.document), SetSelectionResult({...})]))`（一次历史、一次广播）。
  5. `smartLayoutGhost.value = null;` 返回 true。

- `void cancelSmartLayoutDraft()`
  `_smartLayoutDraftActive = false; _editorState = _editorState.copyWith(scene: _draftBaseScene, selectedIds: {}, viewport: _draftPreviousViewport ?? viewport); _activeTool = createTool(当前 activeToolType... 恢复进入前工具类型)`；`notifyListeners()`；`smartLayoutGhost.value = null;`。（零残留。）

- 草稿态守卫（防误操作）：
  - `applyResult`：草稿态下跳过 `onSceneChanged?.call(...)` 与 `_scheduleInkRecognitionFromResult` 与 `_lastChangedElements`（仍 `notifyListeners()`）。
  - 指针抬起历史提交：`if (!_smartLayoutDraftActive && _sceneBeforeDrag != null && !identical(...)) push(...)`。
  - `onPointerDown`：草稿态且点中**非参与者**（`scene.getElementAtPoint(point)` 命中且 id ∉ 参与者）或点空白 → 直接 return（不响应；禁止框选/误选/删除）。
  - `undo()/redo()`：草稿态直接 return。
  - `switchTool`（含键盘/工具栏）：草稿态忽略（保持 SelectTool）。
  - 文本双击编辑入口（`_startTextEditing` 相关 dispatch）：草稿态忽略。
  - 键盘 Delete 的删除入口：调用前检查草稿态忽略（草稿态只允许"选择+拖动"）。

### 2. 白板页流程改动（whiteboard_page.dart）

- `_runSmartLayoutPage` 的"计划存在"分支：
  1. `controller.enterSmartLayoutDraft(plan)`；
  2. `smartLayoutGhost` 设为红区 spec（`failureRects`；若有失败则红框叠加在草稿之上）；
  3. 底部条动作 → `确认落地(commit)` / `删除未识别笔迹后确认(commit + dropFailedBlocks)` / `跳过本页(cancel + skip)` / `取消整个流程(cancel + cancelled)`；
  4. commit 成功 → SnackBar（含"已调整 N 处"/"落地"文案）。
- **拦截层调整**：草案态**不显示**全屏透明 ModalBarrier（否则无法拖动）；仅"计划为空+失败"的失败条场景保留拦截层。工具栏误触由控制器的 `switchTool` 守卫兜底。
- 未识别红区笔迹在草稿中以原笔迹保留（temp scene 未删除失败笔迹）+ 红框标注（Ghost failureRects）。

### 3. 复用与确认

- 拖动=现有 SelectTool 多选移动：网格/对象吸附沿用用户设置；绑定箭头/文本/frame 跟随沿用。
- "确定后一次撤销"：commit 的 `pushHistory + applyResult(Compound)` 即为单历史。
- 多页逐页：每页 识别 → 草稿编辑 → 确认(一次历史)/跳过/取消整个流程（沿用现有循环）。

## 文件改动

| 文件 | 改动 |
| --- | --- |
| `markdraw_controller.dart` | 草稿态字段 + 4 个方法 + 6 处守卫 |
| `whiteboard_page.dart` | 计划分支进入草稿态、底部条动作映射、拦截层仅失败态显示 |
| `smart_layout_plan.dart` | 无需改动（如无 copyWith 需求） |
| 测试 | 新增 `smart_layout_draft_test.dart`（控制器级）+ 更新 `smart_layout_dialogs_test.dart`（若按钮文案变化） |

## 实施步骤

1. 控制器：字段 + 草稿场景构建 + enter/commit/cancel + 守卫。
2. 新增控制器测试：enter 后场景=计划结果（新增/移动/删除生效、selection=参与者、视图适配）；模拟拖动（直接对草稿 `applyResult(UpdateElementResult(新位置))`，等同 SelectTool）后 commit → 真实场景 = 草稿最终位置、`sceneChanges==1`、一次 undo 整体还原；cancel → 与进入前场景 `identical`/相等且无历史；守卫验证（undo/switchTool/外部点击不生效）。
3. whiteboard_page 接入 + 拦截层调整。
4. 全量 `flutter analyze` + `flutter test`（既有 527 例 + 新增）。
5. 文档同步（项目需求.md 智能排版条目 + 本计划）并提交（提交后询问是否推送）。

## 验收标准

- 选中框：参与者每人一个框；拖动整组/单个；方案外元素与空白点不响应。
- 确认落地后一次撤销恢复全部（含拖过的位置）；取消后场景零残留（与进入前完全一致）。
- 草稿期间：无 onSceneChanged 保存/广播；undo/redo/工具切换/删除被禁；失败红区可见。
- 协作单次 +diff 广播；历史一条。
