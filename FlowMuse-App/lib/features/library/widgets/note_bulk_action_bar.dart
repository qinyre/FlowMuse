import 'package:flutter/material.dart';

import '../../../shared/utils/ui_lifecycle.dart';
import '../models/library_index.dart';

class NoteBulkActionBar extends StatelessWidget {
  const NoteBulkActionBar.active({
    super.key,
    required this.selectedCount,
    required this.libraryIndex,
    required this.onClearSelection,
    required this.onDeleteSelected,
    required this.onMoveSelectedToNotebook,
    required this.onAddTagsToSelected,
  })  : _trash = false,
        onRestoreSelected = null,
        onDeleteSelectedForever = null;

  const NoteBulkActionBar.trash({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    required this.onRestoreSelected,
    required this.onDeleteSelectedForever,
  })  : _trash = true,
        libraryIndex = null,
        onDeleteSelected = null,
        onMoveSelectedToNotebook = null,
        onAddTagsToSelected = null;

  final bool _trash;
  final int selectedCount;
  final LibraryIndex? libraryIndex;
  final VoidCallback onClearSelection;
  final Future<void> Function()? onDeleteSelected;
  final Future<void> Function()? onRestoreSelected;
  final Future<void> Function()? onDeleteSelectedForever;
  final Future<void> Function(String? notebookId)? onMoveSelectedToNotebook;
  final Future<void> Function(List<String> tagIds)? onAddTagsToSelected;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text('已选 $selectedCount 项'),
            const Spacer(),
            TextButton(onPressed: onClearSelection, child: const Text('取消')),
            if (_trash) ...[
              TextButton(
                onPressed: selectedCount == 0 ? null : onRestoreSelected,
                child: const Text('恢复'),
              ),
              TextButton(
                onPressed: selectedCount == 0
                    ? null
                    : onDeleteSelectedForever,
                child: const Text('永久删除'),
              ),
            ] else ...[
              _NotebookMoveMenu(
                enabled: selectedCount > 0,
                libraryIndex: libraryIndex!,
                onSelected: onMoveSelectedToNotebook!,
              ),
              _TagAddMenu(
                enabled: selectedCount > 0,
                libraryIndex: libraryIndex!,
                onSelected: onAddTagsToSelected!,
              ),
              TextButton(
                onPressed: selectedCount == 0 ? null : onDeleteSelected,
                child: const Text('删除'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotebookMoveMenu extends StatelessWidget {
  const _NotebookMoveMenu({
    required this.enabled,
    required this.libraryIndex,
    required this.onSelected,
  });

  static const _unfiledNotebookId = '__flow_muse_unfiled_notebook__';

  final bool enabled;
  final LibraryIndex libraryIndex;
  final Future<void> Function(String? notebookId) onSelected;

  @override
  Widget build(BuildContext context) {
    return _LibraryPopupMenuButton<String>(
      enabled: enabled,
      label: '移动到',
      items: [
        const PopupMenuItem<String>(
          value: _unfiledNotebookId,
          child: Text('未归入笔记本'),
        ),
        for (final notebook in libraryIndex.notebooks)
          PopupMenuItem<String>(value: notebook.id, child: Text(notebook.name)),
      ],
      onSelected: (notebookId) =>
          onSelected(notebookId == _unfiledNotebookId ? null : notebookId),
    );
  }
}

class _TagAddMenu extends StatelessWidget {
  const _TagAddMenu({
    required this.enabled,
    required this.libraryIndex,
    required this.onSelected,
  });

  final bool enabled;
  final LibraryIndex libraryIndex;
  final Future<void> Function(List<String> tagIds) onSelected;

  @override
  Widget build(BuildContext context) {
    return _LibraryPopupMenuButton<String>(
      enabled: enabled && libraryIndex.tags.isNotEmpty,
      label: '添加标签',
      items: [
        for (final tag in libraryIndex.tags)
          PopupMenuItem<String>(value: tag.id, child: Text(tag.name)),
      ],
      onSelected: (tagId) => onSelected([tagId]),
    );
  }
}

class _LibraryPopupMenuButton<T extends Object> extends StatelessWidget {
  const _LibraryPopupMenuButton({
    required this.enabled,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final bool enabled;
  final String label;
  final List<PopupMenuEntry<T>> items;
  final Future<void> Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => TextButton(
        onPressed: !enabled || items.isEmpty
            ? null
            : () async {
                final selected = await showAnchoredPopupMenu<T>(
                  context: context,
                  items: items,
                );
                if (selected == null || !context.mounted) {
                  return;
                }
                runAfterUiTeardown(() => onSelected(selected));
              },
        child: Text(label),
      ),
    );
  }
}
