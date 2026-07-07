import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../library/models/notebook_item.dart';
import '../../library/view_models/library_home_view_model.dart';
import '../../library/widgets/create_notebook_card.dart';
import '../../library/widgets/notebook_card.dart';
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
      child: _TagItems(state: state, onCreate: viewModel.createTag),
    );
  }
}

class TagDetailPage extends ConsumerWidget {
  const TagDetailPage({super.key, required this.tagId});

  final String tagId;

  void _openWhiteboard(
    BuildContext context, {
    String notebookId = 'whiteboard-new',
  }) {
    context.push(AppRoutes.whiteboardPath(notebookId: notebookId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagsViewModelProvider);
    final tag = _findTag(state.tags, tagId);
    final notebooks = tag == null
        ? const <NotebookItem>[]
        : sampleNotebooks
              .where((item) => tag.notebookIds.contains(item.id))
              .toList();

    return _TagPageFrame(
      title: tag?.name ?? '标签',
      viewMode: LibraryViewMode.grid,
      sortAscending: false,
      selectionMode: false,
      onCreate: () => _openWhiteboard(context),
      onViewModeChanged: null,
      onSortDirectionChanged: null,
      onSelectionModeChanged: null,
      child: _NotebookItems(
        notebooks: notebooks,
        onCreate: () => _openWhiteboard(context),
        onOpenNotebook: (item) {
          _openWhiteboard(context, notebookId: item.id);
        },
      ),
    );
  }
}

class _TagItems extends StatelessWidget {
  const _TagItems({required this.state, required this.onCreate});

  final TagsState state;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount: state.visibleTags.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateTagTile(onTap: onCreate);
          }
          final tag = state.visibleTags[index - 1];
          return _TagTile(
            tag: tag,
            selectionMode: state.selectionMode,
            onTap: () => context.go(AppRoutes.tagPath(tag.id)),
          );
        },
      );
    }

    return GridView.builder(
      itemCount: state.visibleTags.length + 1,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 218,
        mainAxisExtent: 276,
        crossAxisSpacing: 34,
        mainAxisSpacing: 46,
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
                onTap: () => context.go(AppRoutes.tagPath(tag.id)),
              ),
            ),
            if (state.selectionMode)
              const Positioned(
                top: 10,
                right: 10,
                child: Checkbox(value: false, onChanged: null),
              ),
          ],
        );
      },
    );
  }
}

class _NotebookItems extends StatelessWidget {
  const _NotebookItems({
    required this.notebooks,
    required this.onCreate,
    required this.onOpenNotebook,
  });

  final List<NotebookItem> notebooks;
  final VoidCallback onCreate;
  final ValueChanged<NotebookItem> onOpenNotebook;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: notebooks.length + 1,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 218,
        mainAxisExtent: 276,
        crossAxisSpacing: 34,
        mainAxisSpacing: 46,
      ),
      itemBuilder: (context, index) {
        if (index == 0) {
          return CreateNotebookCard(onTap: onCreate);
        }
        final item = notebooks[index - 1];
        return NotebookCard(item: item, onTap: () => onOpenNotebook(item));
      },
    );
  }
}

class _TagCoverCard extends StatelessWidget {
  const _TagCoverCard({required this.tag, required this.onTap});

  final TagItem tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: NotebookCard.coverWidth,
          height: NotebookCard.coverHeight,
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
        _CoverTitle(title: tag.name),
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
    required this.onTap,
  });

  final TagItem tag;
  final bool selectionMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(LucideIcons.hash),
        title: Text(tag.name),
        subtitle: Text('${tag.count} 个笔记'),
        trailing: selectionMode
            ? const Checkbox(value: false, onChanged: null)
            : const Icon(LucideIcons.chevronRight),
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
          width: NotebookCard.coverWidth,
          height: NotebookCard.coverHeight,
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
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 0),
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
          const SizedBox(height: 46),
          Expanded(child: child),
        ],
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
          const SizedBox(width: 8),
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
                onPressed: () => onViewModeChanged!(LibraryViewMode.grid),
                child: const Text('网格视图'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(LucideIcons.list),
                onPressed: () => onViewModeChanged!(LibraryViewMode.list),
                child: const Text('列表视图'),
              ),
            ],
          ),
        ],
        if (onSortDirectionChanged != null) ...[
          const SizedBox(width: 8),
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
          const SizedBox(width: 8),
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
  const _CoverTitle({required this.title});

  final String title;

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
        const Icon(LucideIcons.chevronDown, color: Color(0xFF555C59), size: 18),
      ],
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
