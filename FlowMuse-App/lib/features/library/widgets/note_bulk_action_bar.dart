import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/utils/ui_lifecycle.dart';
import '../../../shared/widgets/app_spacing.dart';
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
  }) : _trash = false,
       onRestoreSelected = null,
       onDeleteSelectedForever = null;

  const NoteBulkActionBar.trash({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    required this.onRestoreSelected,
    required this.onDeleteSelectedForever,
  }) : _trash = true,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final destructive = TextButton.styleFrom(
      foregroundColor: colorScheme.error,
      minimumSize: const Size(48, 48),
    );
    final count = Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(
            selectedCount == 0 ? LucideIcons.square : LucideIcons.squareCheck,
            size: 20,
            color: selectedCount == 0
                ? colorScheme.onSurfaceVariant
                : colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.controlGap),
          Flexible(
            child: Text(
              selectedCount == 0 ? '选择笔记' : '已选 $selectedCount 项',
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
    final cancel = TextButton(
      onPressed: onClearSelection,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: colorScheme.onSurfaceVariant,
      ),
      child: const Text('取消'),
    );
    final actions = Wrap(
      spacing: AppSpacing.controlGap,
      runSpacing: AppSpacing.controlGap,
      children: [
        if (_trash) ...[
          TextButton.icon(
            onPressed: selectedCount == 0 ? null : onRestoreSelected,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: const Icon(LucideIcons.rotateCcw, size: 16),
            label: const Text('恢复'),
          ),
          TextButton.icon(
            onPressed: selectedCount == 0 ? null : onDeleteSelectedForever,
            style: destructive,
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('永久删除'),
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
          TextButton.icon(
            onPressed: selectedCount == 0 ? null : onDeleteSelected,
            style: destructive,
            icon: const Icon(LucideIcons.trash2, size: 16),
            label: const Text('删除'),
          ),
        ],
      ],
    );
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Card.outlined(
          margin: EdgeInsets.zero,
          color: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.03),
            colorScheme.surface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.listGap,
              vertical: AppSpacing.controlGap,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 640 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(child: count),
                          cancel,
                        ],
                      ),
                      const SizedBox(height: AppSpacing.controlGap),
                      actions,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: count),
                    actions,
                    const SizedBox(width: AppSpacing.controlGap),
                    cancel,
                  ],
                );
              },
            ),
          ),
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
      icon: LucideIcons.folderInput,
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
      icon: LucideIcons.tag,
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
    required this.icon,
    required this.items,
    required this.onSelected,
  });

  final bool enabled;
  final String label;
  final IconData icon;
  final List<PopupMenuEntry<T>> items;
  final Future<void> Function(T value) onSelected;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
        onPressed: !enabled || items.isEmpty
            ? null
            : () async {
                final selected = await showAnchoredPopupMenu<T>(
                  context: context,
                  placement: AnchoredPopupPlacement.below,
                  items: items,
                );
                if (selected == null || !context.mounted) {
                  return;
                }
                runAfterUiTeardown(() => onSelected(selected));
              },
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }
}
