# 笔记本与标签详情笔记控件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让笔记本和标签详情页支持笔记列表/网格切换及完整批量操作。

**Architecture:** 抽取资料库主页正在使用的笔记批量操作栏，新增一个本地维护视图和选择状态的详情内容组件。笔记本/标签详情仅提供过滤后的笔记和现有资料库操作回调，不共享主页的选择状态。

**Tech Stack:** Flutter、Riverpod、flutter_test。

## Global Constraints

- 仅影响笔记本和标签详情页中的笔记内容区；资料库主页、集合列表页及平台适配不改变。
- 使用现有 `LibraryIndexNotifier` 笔记操作，不新增 Repository、Provider、依赖或平台判断。
- 批量操作包含移动到、添加标签和删除；选择状态在每个详情组件实例内独立。
- 按用户要求，Flutter 测试和静态分析命令由用户本地执行。

---

### Task 1: 提取笔记批量操作栏

**Files:**
- Create: `FlowMuse-App/lib/features/library/widgets/note_bulk_action_bar.dart`
- Modify: `FlowMuse-App/lib/features/library/widgets/library_content.dart`

**Interfaces:**
- Produces: `NoteBulkActionBar.active(...)`（移动、添加标签、删除）和 `NoteBulkActionBar.trash(...)`（恢复、永久删除）两个构造器。
- Consumes: `showAnchoredPopupMenu`、`LibraryIndex.notebooks`、`LibraryIndex.tags`。

- [ ] **Step 1: Move the existing action-bar implementation**

将 `library_content.dart` 中的 `_BulkActionBar`、`_NotebookMoveMenu`、`_TagAddMenu`、`_LibraryPopupMenuButton` 移至新文件。公开类提供两个命名构造器：`NoteBulkActionBar.active` 必填移动、添加标签、删除回调；`NoteBulkActionBar.trash` 必填恢复、永久删除回调。保留现有文案、禁用条件和锚点菜单行为。

- [ ] **Step 2: Update the library home caller**

将资料库主页中的 `_BulkActionBar(` 按 `trash` 条件替换为 `NoteBulkActionBar.active(` 或 `NoteBulkActionBar.trash(`，删除已迁移的私有类，确保回调参数完全不变。

### Task 2: 新建集合详情笔记内容组件

**Files:**
- Create: `FlowMuse-App/lib/features/library/widgets/collection_note_content.dart`
- Test: `FlowMuse-App/test/features/library/widgets/collection_note_content_test.dart`

**Interfaces:**
- Produces: `CollectionNoteContent`，构造参数包括标题、返回回调、`LibraryIndex`、笔记列表、创建/打开/单项编辑回调与批量移动、添加标签、删除回调。
- Consumes: `NoteCard`、`CreateNoteCard`、`CoverSelectionCheckbox`、`NoteBulkActionBar`、`MoveToNotebookDialog`、`SelectTagsDialog`。

- [ ] **Step 1: Write the failing Widget test**

用一个 `NoteItem` 和空的 `LibraryIndex` pump `CollectionNoteContent`，断言初始显示网格卡片；点击“列表视图”菜单后显示 `ListTile`；点击“多选”后显示“已选 0 项”，再点击卡片后显示“已选 1 项”。

- [ ] **Step 2: Verify the test is red**

Run: `cd FlowMuse-App; flutter test test/features/library/widgets/collection_note_content_test.dart`

Expected: FAIL because `CollectionNoteContent` does not exist.

- [ ] **Step 3: Implement local UI state and toolbar**

在 `StatefulWidget` 内维护以下字段，不使用 Provider：

```dart
var _viewMode = LibraryViewMode.grid;
var _selectionMode = false;
final _selectedNoteIds = <String>{};
```

在 `RightPageScaffold.actions` 中加入资料库同款视图菜单和多选 `IconButton`；多选模式时在 `topContent` 放入：

```dart
NoteBulkActionBar.active(
  selectedCount: _selectedNoteIds.length,
  libraryIndex: widget.libraryIndex,
  onClearSelection: _clearSelection,
  onDeleteSelected: _deleteSelected,
  onMoveSelectedToNotebook: _moveSelected,
  onAddTagsToSelected: _addTagsToSelected,
)
```

`_deleteSelected`、`_moveSelected` 和 `_addTagsToSelected` 分别调用父级的批量回调，并在 Future 完成后清空选择。

- [ ] **Step 4: Implement list/grid cards and single-note menu**

网格使用 `NoteCard(selectionControl: CoverSelectionCheckbox(...))`；列表使用封面缩略图、标题、日期和末端原生 `Checkbox`。在非多选点击时调用 `onOpenNote`，多选时切换当前笔记 id。沿用现有重命名、移动、选择标签、删除单项菜单与对话框回调。

- [ ] **Step 5: Verify the test is green**

Run: `cd FlowMuse-App; flutter test test/features/library/widgets/collection_note_content_test.dart`

Expected: PASS.

### Task 3: 接入笔记本与标签详情页

**Files:**
- Modify: `FlowMuse-App/lib/features/notebooks/views/notebooks_page.dart`
- Modify: `FlowMuse-App/lib/features/tags/views/tags_page.dart`

**Interfaces:**
- Consumes: `CollectionNoteContent` 和 `libraryIndexProvider.notifier` 已有的 `renameNote`、`moveNotesToNotebook`、`setNoteTags`、`deleteNotes`。
- Produces: 两个详情页具有相同的笔记视图切换、多选和批量操作能力。

- [ ] **Step 1: Replace `NotebookDetailPage` content**

删除详情页中固定 `LibraryViewMode.grid`、`selectionMode: false` 的 `_CollectionPage` 调用，改为 `CollectionNoteContent`。传入 `LibraryQuery(notebookId: notebookId)` 得到的笔记、返回到 `AppRoutes.notebooks` 的回调、创建笔记路由及既有单项/批量资料库操作回调。

- [ ] **Step 2: Replace `TagDetailPage` content**

按 Task 3 Step 1 替换 `_TagPageFrame` 调用，笔记查询和创建路由使用 `tagIds: [tagId]`，返回位置为 `AppRoutes.tags`。

- [ ] **Step 3: Remove duplicated private note-item implementations**

删除两个页面中只被详情页使用的 `_NoteItems` 和其私有单项菜单实现；保留集合/标签总览所需的卡片、列表、框架和集合批量操作类。

### Task 4: 用户验证

**Files:**
- No file changes.

- [ ] **Step 1: Run automated checks**

```powershell
cd FlowMuse-App
flutter test test/features/library/widgets/collection_note_content_test.dart
flutter analyze
flutter test
```

- [ ] **Step 2: Manually verify each detail page**

打开一个笔记本和一个标签：切换列表/网格；进入和取消多选；选择多篇笔记；执行移动到、添加标签和删除。返回资料库主页后确认其视图模式和选择状态未改变。
