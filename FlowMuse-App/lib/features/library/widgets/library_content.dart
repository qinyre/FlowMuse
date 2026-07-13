import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../models/library_special_view.dart';
import '../models/note_item.dart';
import '../repositories/library_repository.dart';
import '../view_models/library_home_view_model.dart';
import 'create_note_card.dart';
import 'note_actions.dart';
import 'note_card.dart';

enum _NoteAction { rename, moveToNotebook, selectTags, delete }

class LibraryContent extends StatefulWidget {
  const LibraryContent({
    super.key,
    required this.compact,
    required this.state,
    required this.title,
    required this.notes,
    required this.libraryIndex,
    required this.specialView,
    required this.onFilterChanged,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
    required this.onSelectionChanged,
    required this.onClearSelection,
    required this.onDeleteSelected,
    required this.onRestoreSelected,
    required this.onDeleteSelectedForever,
    required this.onMoveSelectedToNotebook,
    required this.onAddTagsToSelected,
    required this.onCreate,
    required this.onJoinRoom,
    required this.onOpenNote,
    this.onRenameNote,
    this.onMoveNoteToNotebook,
    this.onSetNoteTags,
    this.onDeleteNote,
  });

  final bool compact;
  final LibraryHomeState state;
  final String title;
  final List<NoteItem> notes;
  final LibraryIndex libraryIndex;
  final LibrarySpecialView specialView;
  final ValueChanged<LibraryFilter> onFilterChanged;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final VoidCallback onSortDirectionChanged;
  final VoidCallback onSelectionModeChanged;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onClearSelection;
  final Future<void> Function() onDeleteSelected;
  final Future<void> Function() onRestoreSelected;
  final Future<void> Function() onDeleteSelectedForever;
  final Future<void> Function(String? notebookId) onMoveSelectedToNotebook;
  final Future<void> Function(List<String> tagIds) onAddTagsToSelected;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;
  final ValueChanged<NoteItem> onOpenNote;
  final Future<void> Function(String noteId, String newName)? onRenameNote;
  final Future<void> Function(String noteId, String? notebookId)? onMoveNoteToNotebook;
  final Future<void> Function(String noteId, List<String> tagIds)? onSetNoteTags;
  final Future<void> Function(String noteId)? onDeleteNote;

  @override
  State<LibraryContent> createState() => _LibraryContentState();
}

class _LibraryContentState extends State<LibraryContent> {
  late final PageController _pageController;
  int? _animatingFilterIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedFilterIndex);
  }

  @override
  void didUpdateWidget(covariant LibraryContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.specialView != LibrarySpecialView.none ||
        oldWidget.state.selectedFilter == widget.state.selectedFilter ||
        !_pageController.hasClients) {
      return;
    }
    if (_animatingFilterIndex == _selectedFilterIndex) {
      return;
    }
    final page = _pageController.page?.round();
    if (page != _selectedFilterIndex) {
      _pageController.jumpToPage(_selectedFilterIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _selectedFilterIndex {
    return LibraryFilter.values.indexOf(widget.state.selectedFilter);
  }

  void _onFilterChanged(LibraryFilter filter) {
    final filterIndex = LibraryFilter.values.indexOf(filter);
    if (widget.specialView == LibrarySpecialView.none &&
        _pageController.hasClients) {
      _animatingFilterIndex = filterIndex;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pageController.jumpToPage(filterIndex);
        _animatingFilterIndex = null;
        widget.onFilterChanged(filter);
        return;
      }
      _pageController
          .animateToPage(
            filterIndex,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && _animatingFilterIndex == filterIndex) {
              _animatingFilterIndex = null;
            }
          });
    }
    widget.onFilterChanged(filter);
  }

  void _onPageChanged(int index) {
    if (_animatingFilterIndex == index) {
      _animatingFilterIndex = null;
    }
    widget.onFilterChanged(LibraryFilter.values[index]);
  }

  @override
  Widget build(BuildContext context) {
    return RightPageScaffold(
      title: widget.title,
      actions: [
        Builder(
          builder: (context) => IconButton(
            tooltip: widget.state.viewMode == LibraryViewMode.grid
                ? '网格视图'
                : '列表视图',
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
              runAfterUiTeardown(() => widget.onViewModeChanged(selected));
            },
            icon: Icon(
              widget.state.viewMode == LibraryViewMode.grid
                  ? LucideIcons.layoutGrid
                  : LucideIcons.list,
            ),
          ),
        ),
        IconButton(
          tooltip: widget.state.sortAscending ? '按日期升序' : '按日期降序',
          onPressed: widget.onSortDirectionChanged,
          icon: Icon(
            widget.state.sortAscending
                ? LucideIcons.arrowUpNarrowWide
                : LucideIcons.arrowDownWideNarrow,
          ),
        ),
        IconButton(
          tooltip: widget.state.selectionMode ? '退出多选' : '多选',
          isSelected: widget.state.selectionMode,
          onPressed: widget.onSelectionModeChanged,
          icon: const Icon(LucideIcons.squareCheck),
          selectedIcon: const Icon(LucideIcons.checkSquare),
        ),
      ],
      topContent: [
        if (widget.specialView == LibrarySpecialView.none) ...[
          _FilterTabs(
            selected: widget.state.selectedFilter,
            onFilterChanged: _onFilterChanged,
            pageController: _pageController,
          ),
          const SizedBox(height: AppSpacing.controlGap),
        ],
        if (widget.state.selectionMode) ...[
          _BulkActionBar(
            trash: widget.specialView == LibrarySpecialView.trash,
            selectedCount: widget.state.selectedNoteIds.length,
            libraryIndex: widget.libraryIndex,
            onClearSelection: widget.onClearSelection,
            onDeleteSelected: widget.onDeleteSelected,
            onRestoreSelected: widget.onRestoreSelected,
            onDeleteSelectedForever: widget.onDeleteSelectedForever,
            onMoveSelectedToNotebook: widget.onMoveSelectedToNotebook,
            onAddTagsToSelected: widget.onAddTagsToSelected,
          ),
          const SizedBox(height: AppSpacing.controlGap),
        ],
      ],
      body: _LibraryItems(
        state: widget.state,
        notes: widget.notes,
        specialView: widget.specialView,
        compact: widget.compact,
        pageController: _pageController,
        onPageChanged: _onPageChanged,
        onSelectionChanged: widget.onSelectionChanged,
        onCreate: widget.onCreate,
        onJoinRoom: widget.onJoinRoom,
        onOpenNote: widget.onOpenNote,
        onRenameNote: widget.onRenameNote,
        onMoveNoteToNotebook: widget.onMoveNoteToNotebook,
        onSetNoteTags: widget.onSetNoteTags,
        onDeleteNote: widget.onDeleteNote,
      ),
    );
  }
}

class _FilterTabs extends StatefulWidget {
  const _FilterTabs({
    required this.selected,
    required this.onFilterChanged,
    required this.pageController,
  });

  final LibraryFilter selected;
  final ValueChanged<LibraryFilter> onFilterChanged;
  final PageController pageController;

  static const _labels = {
    LibraryFilter.all: '全部',
    LibraryFilter.notes: '笔记',
    LibraryFilter.pdf: 'PDF',
  };
  static const _indicatorWidth = 58.0;
  static const _buttonWidth = 86.0;

  @override
  State<_FilterTabs> createState() => _FilterTabsState();
}

class _FilterTabsState extends State<_FilterTabs> {
  double _indicatorPosition = 0;

  @override
  void initState() {
    super.initState();
    _indicatorPosition =
        LibraryFilter.values.indexOf(widget.selected) *
        _FilterTabs._buttonWidth;
    widget.pageController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_FilterTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageController != oldWidget.pageController) {
      oldWidget.pageController.removeListener(_onScroll);
      widget.pageController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.pageController.hasClients) return;
    final offset = widget.pageController.offset;
    final screenWidth = widget.pageController.position.viewportDimension;
    final pagePosition = offset / screenWidth;
    setState(() {
      _indicatorPosition = pagePosition * _FilterTabs._buttonWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final filter in LibraryFilter.values)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onFilterChanged(filter),
                  child: SizedBox(
                    width: _FilterTabs._buttonWidth,
                    child: Center(
                      child: TweenAnimationBuilder<Color?>(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        tween: ColorTween(
                          end: widget.selected == filter
                              ? colorScheme.primary
                              : const Color(0xFF151918),
                        ),
                        builder: (context, color, child) => Text(
                          _FilterTabs._labels[filter]!,
                          style: Theme.of(context).textTheme.titleMedium!
                              .copyWith(
                                color: color,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            bottom: 0,
            left:
                _indicatorPosition +
                (_FilterTabs._buttonWidth - _FilterTabs._indicatorWidth) / 2,
            child: Container(
              width: _FilterTabs._indicatorWidth,
              height: 2,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryItems extends StatelessWidget {
  const _LibraryItems({
    required this.state,
    required this.notes,
    required this.specialView,
    required this.compact,
    required this.pageController,
    required this.onPageChanged,
    required this.onSelectionChanged,
    required this.onCreate,
    required this.onJoinRoom,
    required this.onOpenNote,
    this.onRenameNote,
    this.onMoveNoteToNotebook,
    this.onSetNoteTags,
    this.onDeleteNote,
  });

  final LibraryHomeState state;
  final List<NoteItem> notes;
  final LibrarySpecialView specialView;
  final bool compact;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;
  final ValueChanged<NoteItem> onOpenNote;
  final Future<void> Function(String noteId, String newName)? onRenameNote;
  final Future<void> Function(String noteId, String? notebookId)? onMoveNoteToNotebook;
  final Future<void> Function(String noteId, List<String> tagIds)? onSetNoteTags;
  final Future<void> Function(String noteId)? onDeleteNote;

  @override
  Widget build(BuildContext context) {
    if (specialView != LibrarySpecialView.none) {
      return _LibraryItemsContent(
        state: state,
        notes: notes,
        specialView: specialView,
        compact: compact,
        onSelectionChanged: onSelectionChanged,
        onCreate: onCreate,
        onJoinRoom: onJoinRoom,
        onOpenNote: onOpenNote,
        onRenameNote: onRenameNote,
        onMoveNoteToNotebook: onMoveNoteToNotebook,
        onSetNoteTags: onSetNoteTags,
        onDeleteNote: onDeleteNote,
      );
    }

    return PageView(
      controller: pageController,
      onPageChanged: onPageChanged,
      children: [
        for (final filter in LibraryFilter.values)
          _LibraryItemsContent(
            state: state,
            notes: _notesForFilter(filter),
            specialView: specialView,
            compact: compact,
            onSelectionChanged: onSelectionChanged,
            onCreate: onCreate,
            onJoinRoom: onJoinRoom,
            onOpenNote: onOpenNote,
            onRenameNote: onRenameNote,
            onMoveNoteToNotebook: onMoveNoteToNotebook,
            onSetNoteTags: onSetNoteTags,
            onDeleteNote: onDeleteNote,
          ),
      ],
    );
  }

  List<NoteItem> _notesForFilter(LibraryFilter filter) {
    final activeNotes = state.notes.where((item) => !item.isDeleted);
    final filtered = filter == LibraryFilter.all
        ? activeNotes
        : activeNotes.where((item) => item.kind == filter);
    return filtered.toList()..sort((a, b) {
      final result = a.updatedAt.compareTo(b.updatedAt);
      return state.sortAscending ? result : -result;
    });
  }
}

class _LibraryItemsContent extends StatelessWidget {
  const _LibraryItemsContent({
    required this.state,
    required this.notes,
    required this.specialView,
    required this.compact,
    required this.onSelectionChanged,
    required this.onCreate,
    required this.onJoinRoom,
    required this.onOpenNote,
    this.onRenameNote,
    this.onMoveNoteToNotebook,
    this.onSetNoteTags,
    this.onDeleteNote,
  });

  final LibraryHomeState state;
  final List<NoteItem> notes;
  final LibrarySpecialView specialView;
  final bool compact;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;
  final ValueChanged<NoteItem> onOpenNote;
  final Future<void> Function(String noteId, String newName)? onRenameNote;
  final Future<void> Function(String noteId, String? notebookId)? onMoveNoteToNotebook;
  final Future<void> Function(String noteId, List<String> tagIds)? onSetNoteTags;
  final Future<void> Function(String noteId)? onDeleteNote;

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
        PopupMenuItem<_NoteAction>(
          value: _NoteAction.rename,
          child: ListTile(
            leading: Icon(LucideIcons.penLine),
            title: Text('重命名'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_NoteAction>(
          value: _NoteAction.moveToNotebook,
          child: ListTile(
            leading: Icon(LucideIcons.bookOpen),
            title: Text('移动至'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_NoteAction>(
          value: _NoteAction.selectTags,
          child: ListTile(
            leading: Icon(LucideIcons.tag),
            title: Text('选择标签'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_NoteAction>(
          value: _NoteAction.delete,
          child: ListTile(
            leading: Icon(LucideIcons.trash2),
            title: Text('删除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (selected == null || !context.mounted) {
      return;
    }
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
          builder: (context) => MoveToNotebookDialog(
            currentNotebookId: item.notebookId,
          ),
        );
        if (result != null && context.mounted) {
          await onMoveNoteToNotebook!(item.id, result.notebookId);
        }
      case _NoteAction.selectTags:
        final tagIds = await showDialog<List<String>>(
          context: context,
          builder: (context) => SelectTagsDialog(
            currentTagIds: item.tagIds,
          ),
        );
        if (tagIds != null && context.mounted) {
          await onSetNoteTags!(item.id, tagIds);
        }
      case _NoteAction.delete:
        await onDeleteNote!(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount:
            notes.length + (specialView == LibrarySpecialView.none ? 2 : 0),
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.listGap),
        itemBuilder: (context, index) {
          if (specialView == LibrarySpecialView.none && index == 0) {
            return _CreateNoteTile(onTap: onCreate);
          }
          if (specialView == LibrarySpecialView.none && index == 1) {
            return _JoinRoomTile(onTap: onJoinRoom);
          }
          final noteIndex = specialView == LibrarySpecialView.none
              ? index - 2
              : index;
          final item = notes[noteIndex];
          return _NoteTile(
            item: item,
            selectionMode: state.selectionMode,
            selected: state.selectedNoteIds.contains(item.id),
            onSelectionChanged: () => onSelectionChanged(item.id),
            onTap: state.selectionMode
                ? () => onSelectionChanged(item.id)
                : () => onOpenNote(item),
            onActionsTap: onRenameNote != null
                ? (BuildContext buttonContext) => _showNoteActions(buttonContext, item)
                : null,
          );
        },
      );
    }

    if (notes.isEmpty && specialView != LibrarySpecialView.none) {
      return _EmptyLibrary(
        specialView: specialView,
        onCreate: onCreate,
        onJoinRoom: onJoinRoom,
      );
    }

    return GridView.builder(
      itemCount:
          notes.length + (specialView == LibrarySpecialView.none ? 2 : 0),
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
        if (specialView == LibrarySpecialView.none && index == 0) {
          return CreateNoteCard(onTap: onCreate);
        }
        if (specialView == LibrarySpecialView.none && index == 1) {
          return CreateNoteCard(
            onTap: onJoinRoom,
            icon: LucideIcons.logIn,
            title: '加入房间',
            subtitle: '粘贴协作链接，进入实时白板',
          );
        }
        final noteIndex = specialView == LibrarySpecialView.none
            ? index - 2
            : index;
        final item = notes[noteIndex];
        return Stack(
          children: [
            Positioned.fill(
              child: NoteCard(
                item: item,
                onTap: state.selectionMode
                    ? () => onSelectionChanged(item.id)
                    : () => onOpenNote(item),
                onActionsTap: onRenameNote != null
                    ? (BuildContext buttonContext) => _showNoteActions(buttonContext, item)
                    : null,
              ),
            ),
            if (state.selectionMode)
              Positioned(
                top: 10,
                right: 10,
                child: Checkbox(
                  value: state.selectedNoteIds.contains(item.id),
                  onChanged: (_) => onSelectionChanged(item.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CreateNoteTile extends StatelessWidget {
  const _CreateNoteTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        key: const ValueKey('create-note-list-tile'),
        leading: const Icon(LucideIcons.plus),
        title: const Text('新建笔记'),
        subtitle: const Text('创建快捷笔记'),
        onTap: onTap,
      ),
    );
  }
}

class _JoinRoomTile extends StatelessWidget {
  const _JoinRoomTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        key: const ValueKey('join-room-list-tile'),
        leading: const Icon(LucideIcons.logIn),
        title: const Text('加入房间'),
        subtitle: const Text('粘贴协作链接，进入实时白板'),
        onTap: onTap,
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionChanged,
    required this.onTap,
    this.onActionsTap,
  });

  final NoteItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionChanged;
  final VoidCallback onTap;
  final void Function(BuildContext context)? onActionsTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 48, height: 58, child: NoteCover(item: item)),
        ),
        title: Text(item.title),
        subtitle: Text(item.date),
        trailing: selectionMode
            ? Checkbox(value: selected, onChanged: (_) => onSelectionChanged())
            : onActionsTap != null
                ? Builder(
                    builder: (buttonContext) => IconButton(
                      icon: const Icon(LucideIcons.chevronDown, size: 18),
                      onPressed: () => onActionsTap!(buttonContext),
                    ),
                  )
                : Icon(
                    item.kind == LibraryFilter.pdf
                        ? LucideIcons.fileText
                        : LucideIcons.bookOpen,
                  ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.specialView,
    required this.onCreate,
    required this.onJoinRoom,
  });

  final LibrarySpecialView specialView;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.bookOpen,
              size: 42,
              color: colorScheme.primary.withValues(alpha: 0.62),
            ),
            const SizedBox(height: 18),
            Text(
              switch (specialView) {
                LibrarySpecialView.none => '还没有笔记',
                LibrarySpecialView.unnotebooked => '没有未归类笔记',
                LibrarySpecialView.untagged => '没有未标签笔记',
                LibrarySpecialView.trash => '回收站为空',
              },
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF1F2624),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              switch (specialView) {
                LibrarySpecialView.none => '新建第一块白板后，这里会显示真实保存的笔记。',
                LibrarySpecialView.unnotebooked => '所有笔记都已经归入笔记本。',
                LibrarySpecialView.untagged => '所有笔记都已经添加标签。',
                LibrarySpecialView.trash => '删除的笔记会先进入这里。',
              },
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8F9B96)),
            ),
            const SizedBox(height: 22),
            if (specialView == LibrarySpecialView.none)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('create-notebook-card'),
                    onPressed: onCreate,
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('新建笔记'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onJoinRoom,
                    icon: const Icon(LucideIcons.logIn),
                    label: const Text('加入房间'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.trash,
    required this.selectedCount,
    required this.libraryIndex,
    required this.onClearSelection,
    required this.onDeleteSelected,
    required this.onRestoreSelected,
    required this.onDeleteSelectedForever,
    required this.onMoveSelectedToNotebook,
    required this.onAddTagsToSelected,
  });

  final bool trash;
  final int selectedCount;
  final LibraryIndex libraryIndex;
  final VoidCallback onClearSelection;
  final Future<void> Function() onDeleteSelected;
  final Future<void> Function() onRestoreSelected;
  final Future<void> Function() onDeleteSelectedForever;
  final Future<void> Function(String? notebookId) onMoveSelectedToNotebook;
  final Future<void> Function(List<String> tagIds) onAddTagsToSelected;

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
            if (trash) ...[
              TextButton(
                onPressed: selectedCount == 0 ? null : onRestoreSelected,
                child: const Text('恢复'),
              ),
              TextButton(
                onPressed: selectedCount == 0 ? null : onDeleteSelectedForever,
                child: const Text('永久删除'),
              ),
            ] else ...[
              _NotebookMoveMenu(
                enabled: selectedCount > 0,
                libraryIndex: libraryIndex,
                onSelected: onMoveSelectedToNotebook,
              ),
              _TagAddMenu(
                enabled: selectedCount > 0,
                libraryIndex: libraryIndex,
                onSelected: onAddTagsToSelected,
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

  final bool enabled;
  final LibraryIndex libraryIndex;
  final Future<void> Function(String? notebookId) onSelected;
  static const _unfiledNotebookId = '__flow_muse_unfiled_notebook__';

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
