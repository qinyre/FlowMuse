# 网格封面圆形多选控件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将笔记、笔记本和标签网格卡片的多选框统一为封面右上角的圆形控件。

**Architecture:** 新建一个仅负责视觉与点击回调的共享控件。笔记卡片通过可选的封面叠层参数使用它；笔记本和标签卡片在已有封面 `Stack` 内使用它，沿用原有 ViewModel 选择状态和回调。

**Tech Stack:** Flutter、Material 3、flutter_test。

## Global Constraints

- 仅影响资料库、笔记本、标签的网格封面卡片；列表视图与弹窗复选框保持现状。
- 控件必须使用圆形外观、主题色选中态，并保留 `Checkbox` 的语义和触控能力。
- 共享代码不得加入任何平台判断或新依赖。
- 按用户要求，测试与分析命令由用户本地执行，实施者不运行这些命令。

---

### Task 1: 封面圆形多选控件

**Files:**
- Create: `FlowMuse-App/lib/shared/widgets/cover_selection_checkbox.dart`
- Test: `FlowMuse-App/test/shared/widgets/cover_selection_checkbox_test.dart`

**Interfaces:**
- Produces: `CoverSelectionCheckbox({required bool selected, required VoidCallback onChanged})`，供三类网格卡片的封面层使用。

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('封面多选控件为圆形并响应点击', (tester) async {
  var changed = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CoverSelectionCheckbox(
          selected: false,
          onChanged: () => changed = true,
        ),
      ),
    ),
  );

  final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
  expect(checkbox.shape, isA<CircleBorder>());

  await tester.tap(find.byType(Checkbox));
  expect(changed, isTrue);
});
```

- [ ] **Step 2: Verify the test is red**

Run: `cd FlowMuse-App; flutter test test/shared/widgets/cover_selection_checkbox_test.dart`

Expected: FAIL because `cover_selection_checkbox.dart` and `CoverSelectionCheckbox` do not exist.

- [ ] **Step 3: Implement the shared control**

```dart
class CoverSelectionCheckbox extends StatelessWidget {
  const CoverSelectionCheckbox({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.92),
        shape: BoxShape.circle,
      ),
      child: Checkbox(
        value: selected,
        onChanged: (_) => onChanged(),
        shape: const CircleBorder(),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify the test is green**

Run: `cd FlowMuse-App; flutter test test/shared/widgets/cover_selection_checkbox_test.dart`

Expected: PASS.

### Task 2: 将控件锚定到三类网格封面

**Files:**
- Modify: `FlowMuse-App/lib/features/library/widgets/note_card.dart`
- Modify: `FlowMuse-App/lib/features/library/widgets/library_content.dart`
- Modify: `FlowMuse-App/lib/features/notebooks/views/notebooks_page.dart`
- Modify: `FlowMuse-App/lib/features/tags/views/tags_page.dart`

**Interfaces:**
- Consumes: `CoverSelectionCheckbox.selected` 和 `CoverSelectionCheckbox.onChanged`。
- Produces: 三类网格卡片在 `selectionMode` 下均于封面 `Stack` 的右上角显示共享控件。

- [ ] **Step 1: Update `NoteCard` with an optional cover overlay**

```dart
const NoteCard({
  super.key,
  required this.item,
  required this.onTap,
  this.onActionsTap,
  this.selectionControl,
});

final Widget? selectionControl;
```

在封面 `Card` 的 `Stack` 中，将 `selectionControl` 放在最后：

```dart
if (selectionControl != null)
  Positioned(top: -8, right: -8, child: selectionControl!),
```

- [ ] **Step 2: Replace the library grid's outer checkbox**

删除 `library_content.dart` 网格项包裹整格的 `Stack` 和 `Positioned(top: 10, right: 10, child: Checkbox(...))`，改为：

```dart
NoteCard(
  item: item,
  onTap: state.selectionMode
      ? () => onSelectionChanged(item.id)
      : () => onOpenNote(item),
  selectionControl: state.selectionMode
      ? CoverSelectionCheckbox(
          selected: state.selectedNoteIds.contains(item.id),
          onChanged: () => onSelectionChanged(item.id),
        )
      : null,
)
```

- [ ] **Step 3: Move notebook selection into its cover stack**

在 `_NotebookCollectionCoverCard` 已有封面 `Stack` 中、`InkWell` 之后加入：

```dart
if (selectionMode)
  Positioned(
    top: -8,
    right: -8,
    child: CoverSelectionCheckbox(
      selected: selected,
      onChanged: onSelectionChanged,
    ),
  ),
```

同时删除 `_NotebookCollectionItems` 外层网格 `Stack` 中的旧 `Positioned` 原生 `Checkbox`。

- [ ] **Step 4: Move tag selection into its cover stack**

为 `_TagCoverCard` 增加 `selectionMode`、`selected`、`onSelectionChanged` 构造参数和字段；按笔记本封面相同的 `Positioned(top: -8, right: -8)` 方式插入 `CoverSelectionCheckbox`，并从 `_TagItems` 传入现有状态和回调。删除外层网格 `Stack` 中的旧原生 `Checkbox`。

- [ ] **Step 5: Run user-owned verification commands**

由用户在仓库根目录执行：

```powershell
cd FlowMuse-App
flutter test test/shared/widgets/cover_selection_checkbox_test.dart
flutter analyze
flutter test
```

Expected: 新控件测试通过；静态分析不新增 error；全量测试通过。

### Task 3: 手动回归检查

**Files:**
- No file changes.

**Interfaces:**
- Consumes: Task 2 的三类网格封面选择控件。
- Produces: 跨端一致的手动验收记录。

- [ ] **Step 1: Verify grid selection**

在笔记、笔记本和标签页面切换到网格视图，进入多选模式。确认每张已有封面的卡片右上角显示圆形勾选控件，点击控件和点击卡片都能切换选中状态。

- [ ] **Step 2: Verify unaffected paths**

切换到列表视图，确认列表末端仍为原有复选框；打开笔记标签选择弹窗，确认其 `CheckboxListTile` 外观不变。

- [ ] **Step 3: Verify cross-platform boundary**

确认本次仅使用 Flutter Material 组件和共享 Dart 代码，未引入 `dart:io`、`Platform.is*` 或平台 Channel 调用；Android、iOS、macOS、Windows、Web、鸿蒙将走同一渲染路径。
