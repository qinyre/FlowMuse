import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/utils/ui_lifecycle.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/cover_selection_checkbox.dart';
import '../../../shared/widgets/right_page.dart';
import '../models/library_index.dart';
import '../models/note_item.dart';
import 'create_note_card.dart';
import 'note_actions.dart';
import 'note_bulk_action_bar.dart';
import 'note_card.dart';

enum _CollectionNoteAction { rename, moveToNotebook, selectTags, delete }

class CollectionNoteContent extends StatefulWidget {
  const CollectionNoteContent({
    super.key,
    required this.title,
    required this.libraryIndex,
    required this.notes,
    required this.onBack,
    required this.onCreate,
    required this.onOpenNote,
    required this.onRenameNote,
    required this.onMoveNotesToNotebook,
    required this.onSetNoteTags,
    required this.onAddTagsToNotes,
    required this.onDeleteNotes,
  });

  final String title;
  final LibraryIndex libraryIndex;
  final List<NoteItem> notes;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final ValueChanged<NoteItem> onOpenNote;
  final Future<void> Function(String noteId, String newName) onRenameNote;
  final Future<void> Function(List<String> noteIds, String? notebookId)
  onMoveNotesToNotebook;
  final Future<void> Function(String noteId, List<String> tagIds) onSetNoteTags;
  final Future<void> Function(List<String> noteIds, List<String> tagIds)
  onAddTagsToNotes;
  final Future<void> Function(List<String> noteIds) onDeleteNotes;

  @override
  State<CollectionNoteContent> createState() => _CollectionNoteContentState();
}

class _CollectionNoteContentState extends State<CollectionNoteContent> {
  var _viewMode = LibraryViewMode.grid;
  var _selectionMode = false;
  final _selectedNoteIds = <String>{};

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedNoteIds.clear();
    });
  }

  void _toggleNoteSelection(String noteId) {
    setState(() {
      _selectedNoteIds.contains(noteId)
          ? _selectedNoteIds.remove(noteId)
          : _selectedNoteIds.add(noteId);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedNoteIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    await widget.onDeleteNotes(_selectedNoteIds.toList());
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _moveSelected(String? notebookId) async {
    await widget.onMoveNotesToNotebook(
      _selectedNoteIds.toList(),
      notebookId,
    );
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _addTagsToSelected(List<String> tagIds) async {
    await widget.onAddTagsToNotes(_selectedNoteIds.toList(), tagIds);
    if (mounted) {
      _clearSelection();
    }
  }

  Future<void> _showViewModeMenu(BuildContext context) async {
    final selected = await showAnchoredPopupMenu<LibraryViewMode>(
      context: context,
      placement: AnchoredPopupPlacement.below,
      items: const [
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.grid,
          child: ListTile(
            leading: Icon(LucideIcons.layoutGrid),
            title: Text('网格视图'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<LibraryViewMode>(
          value: LibraryViewMode.list,
          child: ListTile(
            leading: Icon(LucideIcons.list),
            title: Text('列表视图'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (selected != null && mounted) {
      setState(() => _viewMode = selected);
    }
  }

  Future<void> _showNoteActions(BuildContext context, NoteItem item) async {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final actionContext = Navigator.of(context).context;
    final RelativeRect position;
    if (button == null || overlay == null) {
      final size = MediaQuery.of(context).size;
      position = RelativeRect.fromLTRB(
        size.width / 2,
        size.height / 2,
        size.width / 2,
        size.height / 2,
      );
    } else {
      final bottomRight = button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      );
      position = RelativeRect.fromLTRB(
        bottomRight.dx - 8,
        bottomRight.dy + 4,
        bottomRight.dx - 8,
        overlay.size.height - bottomRight.dy - 4,
      );
    }
    final selected = await showMenu<_CollectionNoteAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: _CollectionNoteAction.rename,
          child: ListTile(
            leading: Icon(LucideIcons.penLine),
            title: Text('重命名'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _CollectionNoteAction.moveToNotebook,
          child: ListTile(
            leading: Icon(LucideIcons.bookOpen),
            title: Text('移动至'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _CollectionNoteAction.selectTags,
          child: ListTile(
            leading: Icon(LucideIcons.tag),
            title: Text('选择标签'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _CollectionNoteAction.delete,
          child: ListTile(
            leading: Icon(LucideIcons.trash2),
            title: Text('删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (selected == null || !actionContext.mounted) {
      return;
    }
    await runAfterContextTeardownAsync(actionContext, () async {
      switch (selected) {
        case _CollectionNoteAction.rename:
          final name = await showDialog<String>(
            context: actionContext,
            builder: (context) => _RenameNoteDialog(initialValue: item.title),
          );
          if (name != null && actionContext.mounted) {
            await widget.onRenameNote(item.id, name);
          }
        case _CollectionNoteAction.moveToNotebook:
          final result = await showDialog<MoveToNotebookResult>(
            context: actionContext,
            builder: (context) =>
                MoveToNotebookDialog(currentNotebookId: item.notebookId),
          );
          if (result != null && actionContext.mounted) {
            await widget.onMoveNotesToNotebook([item.id], result.notebookId);
          }
        case _CollectionNoteAction.selectTags:
          final tagIds = await showDialog<List<String>>(
            context: actionContext,
            builder: (context) => SelectTagsDialog(currentTagIds: item.tagIds),
          );
          if (tagIds != null && actionContext.mounted) {
            await widget.onSetNoteTags(item.id, tagIds);
          }
        case _CollectionNoteAction.delete:
          await widget.onDeleteNotes([item.id]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RightPageScaffold(
      title: widget.title,
      leadingActions: [
        IconButton(
          tooltip: '返回',
          onPressed: widget.onBack,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
      ],
      actions: [
        Builder(
          builder: (context) => IconButton(
            tooltip: _viewMode == LibraryViewMode.grid ? '网格视图' : '列表视图',
            onPressed: () => _showViewModeMenu(context),
            icon: Icon(
              _viewMode == LibraryViewMode.grid
                  ? LucideIcons.layoutGrid
                  : LucideIcons.list,
            ),
          ),
        ),
        IconButton(
          tooltip: _selectionMode ? '退出多选' : '多选',
          isSelected: _selectionMode,
          onPressed: _toggleSelectionMode,
          icon: const Icon(LucideIcons.squareCheck),
          selectedIcon: const Icon(LucideIcons.checkSquare),
        ),
        IconButton(
          tooltip: '新建笔记',
          onPressed: widget.onCreate,
          icon: const Icon(LucideIcons.plus),
        ),
      ],
      topContent: [
        if (_selectionMode) ...[
          NoteBulkActionBar.active(
            selectedCount: _selectedNoteIds.length,
            libraryIndex: widget.libraryIndex,
            onClearSelection: _clearSelection,
            onDeleteSelected: _deleteSelected,
            onMoveSelectedToNotebook: _moveSelected,
            onAddTagsToSelected: _addTagsToSelected,
          ),
          const SizedBox(height: AppSpacing.controlGap),
        ],
      ],
      body: _viewMode == LibraryViewMode.list
          ? _buildList()
          : _buildGrid(),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: widget.notes.length + 1,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.listGap),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Card.outlined(
            child: ListTile(
              leading: const Icon(LucideIcons.plus),
              title: const Text('新建笔记'),
              onTap: widget.onCreate,
            ),
          );
        }
        final item = widget.notes[index - 1];
        return Card.outlined(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 48, height: 58, child: NoteCover(item: item)),
            ),
            title: Text(item.title),
            subtitle: Text(item.date),
            trailing: _selectionMode
                ? Checkbox(
                    value: _selectedNoteIds.contains(item.id),
                    onChanged: (_) => _toggleNoteSelection(item.id),
                  )
                : Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(LucideIcons.chevronDown, size: 18),
                      onPressed: () => _showNoteActions(context, item),
                    ),
                  ),
            onTap: _selectionMode
                ? () => _toggleNoteSelection(item.id)
                : () => widget.onOpenNote(item),
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return GridView.builder(
          itemCount: widget.notes.length + 1,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: NoteCard.gridMaxCrossAxisExtent,
            mainAxisExtent: NoteCard.gridMainAxisExtent,
            crossAxisSpacing: compact
                ? NoteCard.compactGridCrossGap
                : NoteCard.gridCrossGap,
            mainAxisSpacing: compact
                ? NoteCard.compactGridMainGap
                : NoteCard.gridMainGap,
          ),
          itemBuilder: (context, index) {
            if (index == 0) {
              return CreateNoteCard(onTap: widget.onCreate);
            }
            final item = widget.notes[index - 1];
            return NoteCard(
              item: item,
              onTap: _selectionMode
                  ? () => _toggleNoteSelection(item.id)
                  : () => widget.onOpenNote(item),
              onActionsTap: _selectionMode
                  ? null
                  : (context) => _showNoteActions(context, item),
              selectionControl: _selectionMode
                  ? CoverSelectionCheckbox(
                      selected: _selectedNoteIds.contains(item.id),
                      onChanged: () => _toggleNoteSelection(item.id),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _RenameNoteDialog extends StatefulWidget {
  const _RenameNoteDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_RenameNoteDialog> createState() => _RenameNoteDialogState();
}

class _RenameNoteDialogState extends State<_RenameNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名笔记'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
