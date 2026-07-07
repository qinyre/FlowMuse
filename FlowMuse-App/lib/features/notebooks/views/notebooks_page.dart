import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../library/widgets/create_note_card.dart';
import '../../library/widgets/note_card.dart';
import '../view_models/notebooks_view_model.dart';

class NotebooksPage extends ConsumerWidget {
  const NotebooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebooksViewModelProvider);
    final viewModel = ref.read(notebooksViewModelProvider.notifier);

    return _CollectionPage(
      title: '笔记本',
      viewMode: state.viewMode,
      sortAscending: state.sortAscending,
      selectionMode: state.selectionMode,
      createTooltip: '新建笔记本',
      createIcon: LucideIcons.bookPlus,
      onCreate: viewModel.createNotebook,
      onViewModeChanged: viewModel.changeViewMode,
      onSortDirectionChanged: viewModel.toggleSortDirection,
      onSelectionModeChanged: viewModel.toggleSelectionMode,
      child: _NotebookCollectionItems(
        state: state,
        onCreate: viewModel.createNotebook,
      ),
    );
  }
}

class NotebookDetailPage extends ConsumerWidget {
  const NotebookDetailPage({super.key, required this.notebookId});

  final String notebookId;

  void _openWhiteboard(BuildContext context, {required String noteId}) {
    context.push(AppRoutes.whiteboardPath(noteId: noteId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notebooksViewModelProvider);
    final notebook = _findNotebook(state.notebooks, notebookId);
    final libraryIndex = ref.watch(libraryIndexProvider).asData?.value;
    final notes =
        libraryIndex?.notes
            .where((item) => item.notebookId == notebookId)
            .toList() ??
        const <NoteItem>[];

    return _CollectionPage(
      title: notebook?.name ?? '笔记本',
      viewMode: LibraryViewMode.grid,
      sortAscending: false,
      selectionMode: false,
      createTooltip: '新建笔记',
      createIcon: LucideIcons.plus,
      onCreate: () async {
        final note = await ref
            .read(libraryIndexProvider.notifier)
            .createNote(notebookId: notebookId);
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
              .createNote(notebookId: notebookId);
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

class _NotebookCollectionItems extends StatelessWidget {
  const _NotebookCollectionItems({required this.state, required this.onCreate});

  final NotebooksState state;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount: state.visibleNotebooks.length + 1,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.listGap),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateCollectionTile(
              label: '新建笔记本',
              subtitle: '创建一个新的笔记集合',
              icon: LucideIcons.bookPlus,
              onTap: onCreate,
            );
          }
          final notebook = state.visibleNotebooks[index - 1];
          return _NotebookCollectionTile(
            notebook: notebook,
            selectionMode: state.selectionMode,
            onTap: () => context.go(AppRoutes.notebookPath(notebook.id)),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return GridView.builder(
          itemCount: state.visibleNotebooks.length + 1,
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
              return _CreateCollectionCard(
                label: '新建笔记本',
                icon: LucideIcons.bookPlus,
                onTap: onCreate,
              );
            }
            final notebook = state.visibleNotebooks[index - 1];
            return Stack(
              children: [
                Positioned.fill(
                  child: _NotebookCollectionCoverCard(
                    notebook: notebook,
                    onTap: () =>
                        context.go(AppRoutes.notebookPath(notebook.id)),
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

class _NotebookCollectionCoverCard extends StatelessWidget {
  const _NotebookCollectionCoverCard({
    required this.notebook,
    required this.onTap,
  });

  final NotebookCollectionItem notebook;
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
              key: ValueKey('notebook-card-${notebook.id}'),
              onTap: onTap,
              child: _NotebookCollectionCover(notebook: notebook),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CoverTitle(title: notebook.name),
        const SizedBox(height: 6),
        _CoverSubtitle(text: '${notebook.count} 个笔记'),
      ],
    );
  }
}

class _NotebookCollectionCover extends StatelessWidget {
  const _NotebookCollectionCover({required this.notebook});

  final NotebookCollectionItem notebook;

  @override
  Widget build(BuildContext context) {
    final foreground =
        ThemeData.estimateBrightnessForColor(notebook.coverColor) ==
            Brightness.dark
        ? Colors.white
        : const Color(0xFF202523);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: notebook.coverColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.12),
              notebook.coverColor,
            ),
            notebook.coverColor,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.08),
              notebook.coverColor,
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
              LucideIcons.bookOpen,
              color: foreground.withValues(alpha: 0.86),
              size: 28,
            ),
            const SizedBox(height: 34),
            Text(
              notebook.name,
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
                notebook.count.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.22),
                  fontSize: 48,
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

class _NotebookCollectionTile extends StatelessWidget {
  const _NotebookCollectionTile({
    required this.notebook,
    required this.selectionMode,
    required this.onTap,
  });

  final NotebookCollectionItem notebook;
  final bool selectionMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(LucideIcons.bookOpen),
        title: Text(notebook.name),
        subtitle: Text('${notebook.count} 个笔记'),
        trailing: selectionMode
            ? const Checkbox(value: false, onChanged: null)
            : const Icon(LucideIcons.chevronRight),
        onTap: onTap,
      ),
    );
  }
}

class _CreateCollectionCard extends StatelessWidget {
  const _CreateCollectionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
                  icon,
                  size: 34,
                  color: colorScheme.primary.withValues(alpha: 0.72),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CoverTitle(title: label),
      ],
    );
  }
}

class _CreateCollectionTile extends StatelessWidget {
  const _CreateCollectionTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}

class _CollectionPage extends StatelessWidget {
  const _CollectionPage({
    required this.title,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.createTooltip,
    required this.createIcon,
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
  final String createTooltip;
  final IconData createIcon;
  final VoidCallback onCreate;
  final ValueChanged<LibraryViewMode>? onViewModeChanged;
  final VoidCallback? onSortDirectionChanged;
  final VoidCallback? onSelectionModeChanged;
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
              _CollectionHeader(
                title: title,
                viewMode: viewMode,
                sortAscending: sortAscending,
                selectionMode: selectionMode,
                createTooltip: createTooltip,
                createIcon: createIcon,
                onCreate: onCreate,
                onViewModeChanged: onViewModeChanged,
                onSortDirectionChanged: onSortDirectionChanged,
                onSelectionModeChanged: onSelectionModeChanged,
              ),
              const SizedBox(height: AppSpacing.headerToContent),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.title,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.createTooltip,
    required this.createIcon,
    required this.onCreate,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
  });

  final String title;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final String createTooltip;
  final IconData createIcon;
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
          tooltip: createTooltip,
          onPressed: onCreate,
          icon: Icon(createIcon),
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

NotebookCollectionItem? _findNotebook(
  List<NotebookCollectionItem> notebooks,
  String notebookId,
) {
  for (final notebook in notebooks) {
    if (notebook.id == notebookId) {
      return notebook;
    }
  }
  return null;
}
