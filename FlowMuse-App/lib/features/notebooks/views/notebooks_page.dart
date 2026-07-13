import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../library/widgets/create_collection_dialog.dart';
import '../../library/widgets/create_note_card.dart';
import '../../library/widgets/edit_collection_page.dart';
import '../../library/widgets/note_actions.dart';
import '../../library/widgets/note_card.dart';
import '../view_models/notebooks_view_model.dart';

enum _NoteAction { rename, moveToNotebook, selectTags, delete }

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
      onCreate: () {
        _createNotebook(context, viewModel);
      },
      onViewModeChanged: viewModel.changeViewMode,
      onSortDirectionChanged: viewModel.toggleSortDirection,
      onSelectionModeChanged: viewModel.toggleSelectionMode,
      bulkBar: state.selectionMode
          ? _CollectionBulkActionBar(
              selectedCount: state.selectedNotebookIds.length,
              onClearSelection: viewModel.clearSelection,
              onDeleteSelected: viewModel.deleteSelectedNotebooks,
            )
          : null,
      child: _NotebookCollectionItems(
        state: state,
        onCreate: () {
          _createNotebook(context, viewModel);
        },
        onSelectionChanged: viewModel.toggleNotebookSelection,
        onRename: viewModel.renameNotebook,
        onEdit: (notebookId) => _editNotebook(context, state, viewModel.editNotebook, notebookId),
        onDelete: viewModel.deleteNotebook,
      ),
    );
  }
}

Future<void> _createNotebook(
  BuildContext context,
  NotebooksViewModel viewModel,
) async {
  final result = await context.push<CreateCollectionResult>(
    AppRoutes.createCollection,
    extra: const CreateCollectionParams(
      title: '新建笔记本',
      hintText: '请输入标题',
      icon: LucideIcons.bookOpen,
      coverColors: libraryNotebookColors,
      coverCategory: 'notebooks',
    ),
  );
  if (result == null || !context.mounted) {
    return;
  }
  try {
    await viewModel.createNotebook(
      name: result.name,
      coverColor: result.coverColor,
      coverImage: result.coverImage,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('\u521b\u5efa\u5931\u8d25\uff1a$error')),
    );
  }
}

Future<void> _editNotebook(
  BuildContext context,
  NotebooksState state,
  Future<void> Function({required String notebookId, String? name, Color? coverColor, String? coverImage}) onEdit,
  String notebookId,
) async {
  final notebook = _findNotebook(state.notebooks, notebookId);
  if (notebook == null) return;

  final result = await context.push<EditCollectionResult>(
    AppRoutes.editCollection,
    extra: EditCollectionParams(
      id: notebook.id,
      name: notebook.name,
      coverColor: notebook.coverColor,
      coverImage: notebook.coverImage,
      title: '\u7f16\u8f91\u7b14\u8bb0\u672c',
      icon: LucideIcons.bookOpen,
      coverColors: libraryNotebookColors,
      coverCategory: 'notebooks',
    ),
  );
  if (result == null || !context.mounted) {
    return;
  }
  try {
    await onEdit(
      notebookId: notebookId,
      name: result.name,
      coverColor: result.coverColor,
      coverImage: result.coverImage,
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('\u7f16\u8f91\u5931\u8d25\uff1a$error')),
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
        libraryIndex?.notesForQuery(LibraryQuery(notebookId: notebookId)) ??
        const <NoteItem>[];

    return _CollectionPage(
      title: notebook?.name ?? '笔记本',
      onBack: () => _popOrGo(context, AppRoutes.notebooks),
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
        onRenameNote: (noteId, newName) =>
            ref.read(libraryIndexProvider.notifier).renameNote(noteId, newName),
        onMoveNoteToNotebook: (noteId, notebookId) =>
            ref.read(libraryIndexProvider.notifier).moveNotesToNotebook([noteId], notebookId),
        onSetNoteTags: (noteId, tagIds) =>
            ref.read(libraryIndexProvider.notifier).setNoteTags(noteId, tagIds),
        onDeleteNote: (noteId) =>
            ref.read(libraryIndexProvider.notifier).deleteNotes([noteId]),
      ),
    );
  }
}

class _NotebookCollectionItems extends StatelessWidget {
  const _NotebookCollectionItems({
    required this.state,
    required this.onCreate,
    required this.onSelectionChanged,
    required this.onRename,
    required this.onEdit,
    required this.onDelete,
  });

  final NotebooksState state;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelectionChanged;
  final Future<void> Function(String notebookId, String name) onRename;
  final Future<void> Function(String notebookId) onEdit;
  final Future<void> Function(String notebookId) onDelete;

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
            selected: state.selectedNotebookIds.contains(notebook.id),
            onSelectionChanged: () => onSelectionChanged(notebook.id),
            onRename: () => _showNameDialog(
              context: context,
              title: '重命名笔记本',
              initialValue: notebook.name,
              onSubmitted: (name) => onRename(notebook.id, name),
            ),
            onEdit: () => onEdit(notebook.id),
            onDelete: () => onDelete(notebook.id),
            onTap: () => context.push(AppRoutes.notebookPath(notebook.id)),
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
                    selectionMode: state.selectionMode,
                    selected: state.selectedNotebookIds.contains(notebook.id),
                    onSelectionChanged: () => onSelectionChanged(notebook.id),
                    onRename: () => _showNameDialog(
                      context: context,
                      title: '重命名笔记本',
                      initialValue: notebook.name,
                      onSubmitted: (name) => onRename(notebook.id, name),
                    ),
                    onEdit: () => onEdit(notebook.id),
                    onDelete: () => onDelete(notebook.id),
                    onTap: () =>
                        context.push(AppRoutes.notebookPath(notebook.id)),
                  ),
                ),
                if (state.selectionMode)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Checkbox(
                      value: state.selectedNotebookIds.contains(notebook.id),
                      onChanged: (_) => onSelectionChanged(notebook.id),
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
    this.onRenameNote,
    this.onMoveNoteToNotebook,
    this.onSetNoteTags,
    this.onDeleteNote,
  });

  final List<NoteItem> notes;
  final VoidCallback onCreate;
  final ValueChanged<NoteItem> onOpenNote;
  final Future<void> Function(String noteId, String newName)? onRenameNote;
  final Future<void> Function(String noteId, String? notebookId)? onMoveNoteToNotebook;
  final Future<void> Function(String noteId, List<String> tagIds)? onSetNoteTags;
  final Future<void> Function(String noteId)? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return GridView.builder(
          itemCount: notes.length + 1,
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
              return CreateNoteCard(onTap: onCreate);
            }
            final item = notes[index - 1];
            return Stack(
              children: [
                Positioned.fill(
                  child: NoteCard(
                    item: item,
                    onTap: () => onOpenNote(item),
                    onActionsTap: onRenameNote != null
                        ? (BuildContext buttonContext) => _showNoteActions(buttonContext, item)
                        : null,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showNoteActions(BuildContext context, NoteItem item) async {
    final RenderBox? button = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;

    RelativeRect position;
    if (button != null && overlay != null) {
      final bottomRight = button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      );
      final arrowY = bottomRight.dy;
      final menuLeft = bottomRight.dx - 8;
      position = RelativeRect.fromLTRB(
        menuLeft,
        arrowY + 4,
        menuLeft,
        overlay.size.height - arrowY - 4,
      );
    } else {
      final size = MediaQuery.of(context).size;
      position = RelativeRect.fromLTRB(size.width / 2, size.height / 2, size.width / 2, size.height / 2);
    }

    final selected = await showMenu<_NoteAction>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem(
          value: _NoteAction.rename,
          child: ListTile(
            leading: Icon(LucideIcons.penLine),
            title: Text('重命名'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.moveToNotebook,
          child: ListTile(
            leading: Icon(LucideIcons.bookOpen),
            title: Text('移动至'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.selectTags,
          child: ListTile(
            leading: Icon(LucideIcons.tag),
            title: Text('选择标签'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.delete,
          child: ListTile(
            leading: Icon(LucideIcons.trash2),
            title: Text('删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (selected == null || !context.mounted) return;

    switch (selected) {
      case _NoteAction.rename:
        final name = await showDialog<String>(
          context: context,
          builder: (context) => _NoteRenameDialog(initialValue: item.title),
        );
        if (name != null && context.mounted) {
          await onRenameNote!(item.id, name);
        }
      case _NoteAction.moveToNotebook:
        final result = await showDialog<MoveToNotebookResult>(
          context: context,
          builder: (context) => MoveToNotebookDialog(currentNotebookId: item.notebookId),
        );
        if (result != null && context.mounted) {
          await onMoveNoteToNotebook!(item.id, result.notebookId);
        }
      case _NoteAction.selectTags:
        final tagIds = await showDialog<List<String>>(
          context: context,
          builder: (context) => SelectTagsDialog(currentTagIds: item.tagIds),
        );
        if (tagIds != null && context.mounted) {
          await onSetNoteTags!(item.id, tagIds);
        }
      case _NoteAction.delete:
        await onDeleteNote!(item.id);
    }
  }
}

class _NotebookCollectionCoverCard extends StatelessWidget {
  _NotebookCollectionCoverCard({
    required this.notebook,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
    required this.onRename,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  final GlobalKey _arrowKey = GlobalKey();

  final NotebookCollectionItem notebook;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionChanged;
  final VoidCallback onRename;
  final VoidCallback onEdit;
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
            margin: EdgeInsets.zero,
            elevation: 1,
            shadowColor: const Color(0x0F5A625F),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _NotebookCollectionCover(notebook: notebook),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('notebook-card-${notebook.id}'),
                    onTap: onTap,
                    onLongPress: () {
                      final arrowCtx = _arrowKey.currentContext;
                      if (arrowCtx != null) {
                        _showCollectionActions(arrowCtx, onRename: onRename, onEdit: onEdit, onDelete: onDelete);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 13),
        _CoverTitle(
          title: notebook.name,
          arrowKey: _arrowKey,
          onActionsTap: (ctx) => _showCollectionActions(ctx, onRename: onRename, onEdit: onEdit, onDelete: onDelete),
        ),
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

    if (notebook.coverImage != null) {
      return Image.asset(notebook.coverImage!, fit: BoxFit.cover);
    }

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
    required this.selected,
    required this.onSelectionChanged,
    required this.onRename,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  final NotebookCollectionItem notebook;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionChanged;
  final VoidCallback onRename;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: const Icon(LucideIcons.bookOpen),
        title: Text(notebook.name),
        subtitle: Text('${notebook.count} 个笔记'),
        trailing: selectionMode
            ? Checkbox(value: selected, onChanged: (_) => onSelectionChanged())
            : _CollectionActions(onRename: onRename, onEdit: onEdit, onDelete: onDelete),
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
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
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
        const SizedBox(height: 13),
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
    this.onBack,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.createTooltip,
    required this.createIcon,
    required this.onCreate,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
    this.bulkBar,
    required this.child,
  });

  final String title;
  final VoidCallback? onBack;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final String createTooltip;
  final IconData createIcon;
  final VoidCallback onCreate;
  final ValueChanged<LibraryViewMode>? onViewModeChanged;
  final VoidCallback? onSortDirectionChanged;
  final VoidCallback? onSelectionModeChanged;
  final Widget? bulkBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RightPageScaffold(
      title: title,
      leadingActions: [
        if (onBack != null)
          IconButton(
            tooltip: '返回笔记本',
            onPressed: onBack,
            icon: const Icon(LucideIcons.chevronLeft),
          ),
      ],
      actions: [
        IconButton(
          tooltip: createTooltip,
          onPressed: onCreate,
          icon: Icon(createIcon),
        ),
        if (onViewModeChanged != null)
          Builder(
            builder: (context) => IconButton(
              tooltip: viewMode == LibraryViewMode.grid ? '网格视图' : '列表视图',
              onPressed: () async {
                final selected = await showAnchoredPopupMenu<LibraryViewMode>(
                  context: context,
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
                if (selected == null || !context.mounted) {
                  return;
                }
                runAfterUiTeardown(() => onViewModeChanged!(selected));
              },
              icon: Icon(
                viewMode == LibraryViewMode.grid
                    ? LucideIcons.layoutGrid
                    : LucideIcons.list,
              ),
            ),
          ),
        if (onSortDirectionChanged != null)
          IconButton(
            tooltip: sortAscending ? '按名称升序' : '按名称降序',
            onPressed: onSortDirectionChanged,
            icon: Icon(
              sortAscending
                  ? LucideIcons.arrowUpNarrowWide
                  : LucideIcons.arrowDownWideNarrow,
            ),
          ),
        if (onSelectionModeChanged != null)
          IconButton(
            tooltip: selectionMode ? '退出多选' : '多选',
            isSelected: selectionMode,
            onPressed: onSelectionModeChanged,
            icon: const Icon(LucideIcons.squareCheck),
            selectedIcon: const Icon(LucideIcons.checkSquare),
          ),
      ],
      topContent: [
        if (bulkBar != null) ...[
          bulkBar!,
          const SizedBox(height: AppSpacing.controlGap),
        ],
      ],
      body: child,
    );
  }
}

void _popOrGo(BuildContext context, String location) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go(location);
}

class _CollectionBulkActionBar extends StatelessWidget {
  const _CollectionBulkActionBar({
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

class _CoverTitle extends StatelessWidget {
  const _CoverTitle({required this.title, this.arrowKey, this.onActionsTap});

  final String title;
  final Key? arrowKey;
  final void Function(BuildContext context)? onActionsTap;

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
        if (onActionsTap != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: '更多操作',
            child: Builder(
              builder: (arrowCtx) => InkWell(
                key: arrowKey,
                borderRadius: BorderRadius.circular(12),
                onTap: () => onActionsTap!(arrowCtx),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(LucideIcons.chevronDown, size: 18),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CollectionActions extends StatelessWidget {
  const _CollectionActions({this.onRename, this.onEdit, this.onDelete});

  final VoidCallback? onRename;
  final VoidCallback? onEdit;
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
    return Builder(
      builder: (context) => Tooltip(
        message: '更多操作',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showCollectionActions(context, onRename: onRename!, onEdit: onEdit, onDelete: onDelete!),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: Icon(LucideIcons.chevronDown, size: 18),
          ),
        ),
      ),
    );
  }
}

enum _CollectionAction { rename, edit, delete }

Future<void> _showCollectionActions(
  BuildContext context, {
  required VoidCallback onRename,
  VoidCallback? onEdit,
  required VoidCallback onDelete,
}) async {
  final RenderBox? button = context.findRenderObject() as RenderBox?;
  final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;

  RelativeRect position;
  if (button != null && overlay != null) {
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final menuLeft = bottomRight.dx - 8;
    position = RelativeRect.fromLTRB(
      menuLeft,
      bottomRight.dy + 4,
      menuLeft,
      overlay.size.height - bottomRight.dy - 4,
    );
  } else {
    final size = MediaQuery.of(context).size;
    position = RelativeRect.fromLTRB(size.width / 2, size.height / 2, size.width / 2, size.height / 2);
  }

  final selected = await showMenu<_CollectionAction>(
    context: context,
    position: position,
    items: [
      const PopupMenuItem<_CollectionAction>(
        value: _CollectionAction.rename,
        child: ListTile(leading: Icon(LucideIcons.penLine), title: Text('重命名'), contentPadding: EdgeInsets.zero),
      ),
      if (onEdit != null)
        const PopupMenuItem<_CollectionAction>(
          value: _CollectionAction.edit,
          child: ListTile(leading: Icon(LucideIcons.settings), title: Text('编辑'), contentPadding: EdgeInsets.zero),
        ),
      const PopupMenuItem<_CollectionAction>(
        value: _CollectionAction.delete,
        child: ListTile(leading: Icon(LucideIcons.trash2), title: Text('删除'), contentPadding: EdgeInsets.zero),
      ),
    ],
  );
  if (selected == null || !context.mounted) return;
  switch (selected) {
    case _CollectionAction.rename:
      runAfterUiTeardown(onRename);
    case _CollectionAction.edit:
      if (onEdit != null) runAfterUiTeardown(onEdit);
    case _CollectionAction.delete:
      runAfterUiTeardown(onDelete);
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

Future<void> _showNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required Future<void> Function(String value) onSubmitted,
}) async {
  final value = await showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(title: title, initialValue: initialValue),
  );
  if (value != null && context.mounted) {
    await runAfterContextTeardownAsync(context, () => onSubmitted(value));
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initialValue});

  final String title;
  final String initialValue;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
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

  void _submit([String? value]) {
    Navigator.of(context).pop(value ?? _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: _submit,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 笔记重命名对话框
// ---------------------------------------------------------------------------

class _NoteRenameDialog extends StatefulWidget {
  const _NoteRenameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_NoteRenameDialog> createState() => _NoteRenameDialogState();
}

class _NoteRenameDialogState extends State<_NoteRenameDialog> {
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

  void _submit([String? value]) {
    Navigator.of(context).pop(value ?? _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名笔记'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: _submit,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
