import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../library/widgets/create_note_card.dart';
import '../../library/widgets/note_card.dart';
import '../view_models/tags_view_model.dart';

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagsViewModelProvider);
    final viewModel = ref.read(tagsViewModelProvider.notifier);

    return _TagPageFrame(
      title: '标签',
      viewMode: state.viewMode,
      sortAscending: state.sortAscending,
      selectionMode: state.selectionMode,
      onCreate: viewModel.createTag,
      onViewModeChanged: viewModel.changeViewMode,
      onSortDirectionChanged: viewModel.toggleSortDirection,
      onSelectionModeChanged: viewModel.toggleSelectionMode,
      bulkBar: state.selectionMode
          ? _TagBulkActionBar(
              selectedCount: state.selectedTagIds.length,
              onClearSelection: viewModel.clearSelection,
              onDeleteSelected: viewModel.deleteSelectedTags,
            )
          : null,
      child: _TagItems(
        state: state,
        onCreate: viewModel.createTag,
        onSelectionChanged: viewModel.toggleTagSelection,
        onRename: viewModel.renameTag,
        onDelete: viewModel.deleteTag,
      ),
    );
  }
}

class TagDetailPage extends ConsumerWidget {
  const TagDetailPage({super.key, required this.tagId});

  final String tagId;

  void _openWhiteboard(BuildContext context, {required String noteId}) {
    context.push(AppRoutes.whiteboardPath(noteId: noteId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagsViewModelProvider);
    final tag = _findTag(state.tags, tagId);
    final libraryIndex = ref.watch(libraryIndexProvider).asData?.value;
    final notes =
        libraryIndex?.notes
            .where((item) => item.tagIds.contains(tagId))
            .toList() ??
        const <NoteItem>[];

    return _TagPageFrame(
      title: tag?.name ?? '标签',
      viewMode: LibraryViewMode.grid,
      sortAscending: false,
      selectionMode: false,
      onCreate: () async {
        final note = await ref
            .read(libraryIndexProvider.notifier)
            .createNote(tagIds: [tagId]);
        if (context.mounted) {
          _openWhiteboard(context, noteId: note.id);
        }
      },
      onViewModeChanged: null,
      onSortDirectionChanged: null,
      onSelectionModeChanged: null,
      child: _NoteItems(
        notes: notes,
        onCreate: () async {
          final note = await ref
              .read(libraryIndexProvider.notifier)
              .createNote(tagIds: [tagId]);
          if (context.mounted) {
            _openWhiteboard(context, noteId: note.id);
          }
        },
        onOpenNote: (item) {
          _openWhiteboard(context, noteId: item.id);
        },
      ),
    );
  }
}

class _TagItems extends StatelessWidget {
  const _TagItems({
    required this.state,
    required this.onCreate,
    required this.onSelectionChanged,
    required this.onRename,
    required this.onDelete,
  });

  final TagsState state;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelectionChanged;
  final Future<void> Function(String tagId, String name) onRename;
  final Future<void> Function(String tagId) onDelete;

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount: state.visibleTags.length + 1,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.listGap),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateTagTile(onTap: onCreate);
          }
          final tag = state.visibleTags[index - 1];
          return _TagTile(
            tag: tag,
            selectionMode: state.selectionMode,
            selected: state.selectedTagIds.contains(tag.id),
            onSelectionChanged: () => onSelectionChanged(tag.id),
            onRename: () => _showNameDialog(
              context: context,
              title: '重命名标签',
              initialValue: tag.name,
              onSubmitted: (name) => onRename(tag.id, name),
            ),
            onDelete: () => onDelete(tag.id),
            onTap: () => context.go(AppRoutes.tagPath(tag.id)),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return GridView.builder(
          itemCount: state.visibleTags.length + 1,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 218,
            mainAxisExtent: 276,
            crossAxisSpacing: compact
                ? AppSpacing.compactGridCrossGap
                : AppSpacing.gridCrossGap,
            mainAxisSpacing: compact
                ? AppSpacing.compactGridMainGap
                : AppSpacing.gridMainGap,
          ),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _CreateTagCard(onTap: onCreate);
            }
            final tag = state.visibleTags[index - 1];
            return Stack(
              children: [
                Positioned.fill(
                  child: _TagCoverCard(
                    tag: tag,
                    onRename: () => _showNameDialog(
                      context: context,
                      title: '重命名标签',
                      initialValue: tag.name,
                      onSubmitted: (name) => onRename(tag.id, name),
                    ),
                    onDelete: () => onDelete(tag.id),
                    onTap: () => context.go(AppRoutes.tagPath(tag.id)),
                  ),
                ),
                if (state.selectionMode)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Checkbox(
                      value: state.selectedTagIds.contains(tag.id),
                      onChanged: (_) => onSelectionChanged(tag.id),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NoteItems extends StatelessWidget {
  const _NoteItems({
    required this.notes,
    required this.onCreate,
    required this.onOpenNote,
  });

  final List<NoteItem> notes;
  final VoidCallback onCreate;
  final ValueChanged<NoteItem> onOpenNote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return GridView.builder(
          itemCount: notes.length + 1,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 218,
            mainAxisExtent: 276,
            crossAxisSpacing: compact
                ? AppSpacing.compactGridCrossGap
                : AppSpacing.gridCrossGap,
            mainAxisSpacing: compact
                ? AppSpacing.compactGridMainGap
                : AppSpacing.gridMainGap,
          ),
          itemBuilder: (context, index) {
            if (index == 0) {
              return CreateNoteCard(onTap: onCreate);
            }
            final item = notes[index - 1];
            return NoteCard(item: item, onTap: () => onOpenNote(item));
          },
        );
      },
    );
  }
}

class _TagCoverCard extends StatelessWidget {
  const _TagCoverCard({
    required this.tag,
    required this.onRename,
    required this.onDelete,
    required this.onTap,
  });

  final TagItem tag;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: NoteCard.coverWidth,
          height: NoteCard.coverHeight,
          child: Card(
            elevation: 5,
            shadowColor: const Color(0x165A625F),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              key: ValueKey('tag-card-${tag.id}'),
              onTap: onTap,
              child: _TagCover(tag: tag),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CoverTitle(title: tag.name, onRename: onRename, onDelete: onDelete),
        const SizedBox(height: 6),
        _CoverSubtitle(text: '${tag.count} 个笔记'),
      ],
    );
  }
}

class _TagCover extends StatelessWidget {
  const _TagCover({required this.tag});

  final TagItem tag;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(tag.coverColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF202523);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tag.coverColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.12),
              tag.coverColor,
            ),
            tag.coverColor,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.08),
              tag.coverColor,
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              LucideIcons.hash,
              color: foreground.withValues(alpha: 0.86),
              size: 28,
            ),
            const SizedBox(height: 34),
            Text(
              tag.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '#',
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.24),
                  fontSize: 64,
                  height: 1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagTile extends StatelessWidget {
  const _TagTile({
    required this.tag,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
    required this.onRename,
    required this.onDelete,
    required this.onTap,
  });

  final TagItem tag;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionChanged;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(LucideIcons.hash),
        title: Text(tag.name),
        subtitle: Text('${tag.count} 个笔记'),
        trailing: selectionMode
            ? Checkbox(value: selected, onChanged: (_) => onSelectionChanged())
            : _CollectionActions(onRename: onRename, onDelete: onDelete),
        onTap: onTap,
      ),
    );
  }
}

class _CreateTagCard extends StatelessWidget {
  const _CreateTagCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: NoteCard.coverWidth,
          height: NoteCard.coverHeight,
          child: Card.outlined(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Icon(
                  LucideIcons.tag,
                  size: 34,
                  color: colorScheme.primary.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CoverTitle(title: '新建标签'),
      ],
    );
  }
}

class _CreateTagTile extends StatelessWidget {
  const _CreateTagTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(LucideIcons.tag),
        title: const Text('新建标签'),
        subtitle: const Text('创建一个新的笔记标记'),
        onTap: onTap,
      ),
    );
  }
}

class _TagPageFrame extends StatelessWidget {
  const _TagPageFrame({
    required this.title,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.onCreate,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
    this.bulkBar,
    required this.child,
  });

  final String title;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final VoidCallback onCreate;
  final ValueChanged<LibraryViewMode>? onViewModeChanged;
  final VoidCallback? onSortDirectionChanged;
  final VoidCallback? onSelectionModeChanged;
  final Widget? bulkBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return Padding(
          padding: AppSpacing.pagePadding(compact: compact),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TagHeader(
                title: title,
                viewMode: viewMode,
                sortAscending: sortAscending,
                selectionMode: selectionMode,
                onCreate: onCreate,
                onViewModeChanged: onViewModeChanged,
                onSortDirectionChanged: onSortDirectionChanged,
                onSelectionModeChanged: onSelectionModeChanged,
              ),
              const SizedBox(height: AppSpacing.headerToContent),
              if (bulkBar != null) ...[
                bulkBar!,
                const SizedBox(height: AppSpacing.sectionGap),
              ],
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _TagBulkActionBar extends StatelessWidget {
  const _TagBulkActionBar({
    required this.selectedCount,
    required this.onClearSelection,
    required this.onDeleteSelected,
  });

  final int selectedCount;
  final VoidCallback onClearSelection;
  final Future<void> Function() onDeleteSelected;

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
            TextButton(
              onPressed: selectedCount == 0 ? null : onDeleteSelected,
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagHeader extends StatelessWidget {
  const _TagHeader({
    required this.title,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.onCreate,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
  });

  final String title;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final VoidCallback onCreate;
  final ValueChanged<LibraryViewMode>? onViewModeChanged;
  final VoidCallback? onSortDirectionChanged;
  final VoidCallback? onSelectionModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F2624),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '新建标签',
          onPressed: onCreate,
          icon: const Icon(LucideIcons.tag),
        ),
        if (onViewModeChanged != null) ...[
          const SizedBox(width: AppSpacing.controlGap),
          MenuAnchor(
            builder: (context, controller, child) {
              return IconButton(
                tooltip: viewMode == LibraryViewMode.grid ? '网格视图' : '列表视图',
                onPressed: () {
                  controller.isOpen ? controller.close() : controller.open();
                },
                icon: Icon(
                  viewMode == LibraryViewMode.grid
                      ? LucideIcons.layoutGrid
                      : LucideIcons.list,
                ),
              );
            },
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(LucideIcons.layoutGrid),
                onPressed: () => runAfterUiFrame(
                  () => onViewModeChanged!(LibraryViewMode.grid),
                ),
                child: const Text('网格视图'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(LucideIcons.list),
                onPressed: () => runAfterUiFrame(
                  () => onViewModeChanged!(LibraryViewMode.list),
                ),
                child: const Text('列表视图'),
              ),
            ],
          ),
        ],
        if (onSortDirectionChanged != null) ...[
          const SizedBox(width: AppSpacing.controlGap),
          IconButton(
            tooltip: sortAscending ? '按名称升序' : '按名称降序',
            onPressed: onSortDirectionChanged,
            icon: Icon(
              sortAscending
                  ? LucideIcons.arrowUpNarrowWide
                  : LucideIcons.arrowDownWideNarrow,
            ),
          ),
        ],
        if (onSelectionModeChanged != null) ...[
          const SizedBox(width: AppSpacing.controlGap),
          IconButton(
            tooltip: selectionMode ? '退出多选' : '多选',
            isSelected: selectionMode,
            onPressed: onSelectionModeChanged,
            icon: const Icon(LucideIcons.squareCheck),
            selectedIcon: const Icon(LucideIcons.checkSquare),
          ),
        ],
      ],
    );
  }
}

class _CoverTitle extends StatelessWidget {
  const _CoverTitle({required this.title, this.onRename, this.onDelete});

  final String title;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF222725),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _CollectionActions(onRename: onRename, onDelete: onDelete),
      ],
    );
  }
}

class _CollectionActions extends StatelessWidget {
  const _CollectionActions({this.onRename, this.onDelete});

  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    if (onRename == null || onDelete == null) {
      return const Icon(
        LucideIcons.chevronDown,
        color: Color(0xFF555C59),
        size: 18,
      );
    }
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.penLine),
          onPressed: () => runAfterUiFrame(onRename!),
          child: const Text('重命名'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(LucideIcons.trash2),
          onPressed: () => runAfterUiFrame(onDelete!),
          child: const Text('删除'),
        ),
      ],
      builder: (context, controller, child) {
        return IconButton(
          tooltip: '更多操作',
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }
}

class _CoverSubtitle extends StatelessWidget {
  const _CoverSubtitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: const Color(0xFFA3AAA6)),
    );
  }
}

TagItem? _findTag(List<TagItem> tags, String tagId) {
  for (final tag in tags) {
    if (tag.id == tagId) {
      return tag;
    }
  }
  return null;
}

Future<void> _showNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required Future<void> Function(String value) onSubmitted,
}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && context.mounted) {
      await onSubmitted(value);
    }
  } finally {
    controller.dispose();
  }
}
