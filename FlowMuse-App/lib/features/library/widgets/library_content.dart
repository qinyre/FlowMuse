import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';
import '../models/library_special_view.dart';
import '../models/note_item.dart';
import '../repositories/library_repository.dart';
import '../view_models/library_home_view_model.dart';
import 'create_note_card.dart';
import 'note_card.dart';

class LibraryContent extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.pagePadding(compact: compact),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(
            compact: compact,
            title: title,
            viewMode: state.viewMode,
            sortAscending: state.sortAscending,
            selectionMode: state.selectionMode,
            onViewModeChanged: onViewModeChanged,
            onSortDirectionChanged: onSortDirectionChanged,
            onSelectionModeChanged: onSelectionModeChanged,
          ),
          const SizedBox(height: AppSpacing.headerToContent),
          if (specialView == LibrarySpecialView.none) ...[
            _FilterTabs(
              selected: state.selectedFilter,
              onFilterChanged: onFilterChanged,
            ),
            const SizedBox(height: AppSpacing.sectionGap),
          ],
          if (state.selectionMode)
            _BulkActionBar(
              trash: specialView == LibrarySpecialView.trash,
              selectedCount: state.selectedNoteIds.length,
              libraryIndex: libraryIndex,
              onClearSelection: onClearSelection,
              onDeleteSelected: onDeleteSelected,
              onRestoreSelected: onRestoreSelected,
              onDeleteSelectedForever: onDeleteSelectedForever,
              onMoveSelectedToNotebook: onMoveSelectedToNotebook,
              onAddTagsToSelected: onAddTagsToSelected,
            ),
          if (state.selectionMode)
            const SizedBox(height: AppSpacing.sectionGap),
          Expanded(
            child: _LibraryItems(
              state: state,
              notes: notes,
              specialView: specialView,
              compact: compact,
              onFilterChanged: onFilterChanged,
              onSelectionChanged: onSelectionChanged,
              onCreate: onCreate,
              onJoinRoom: onJoinRoom,
              onOpenNote: onOpenNote,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.selected, required this.onFilterChanged});

  final LibraryFilter selected;
  final ValueChanged<LibraryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SegmentedButton<LibraryFilter>(
      key: const ValueKey('library-filter-tabs'),
      showSelectedIcon: false,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 0),
        ),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: WidgetStatePropertyAll(
          colorScheme.primary.withValues(alpha: 0.08),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        ),
      ),
      segments: [
        ButtonSegment(
          value: LibraryFilter.all,
          label: _FilterSegmentLabel(
            label: '全部',
            selected: selected == LibraryFilter.all,
          ),
          icon: const SizedBox.shrink(),
        ),
        ButtonSegment(
          value: LibraryFilter.notes,
          label: _FilterSegmentLabel(
            label: '笔记',
            selected: selected == LibraryFilter.notes,
          ),
          icon: const SizedBox.shrink(),
        ),
        ButtonSegment(
          value: LibraryFilter.pdf,
          label: _FilterSegmentLabel(
            label: 'PDF',
            selected: selected == LibraryFilter.pdf,
          ),
          icon: const SizedBox.shrink(),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onFilterChanged(values.single),
      selectedIcon: const SizedBox.shrink(),
      emptySelectionAllowed: false,
    );
  }
}

class _LibraryItems extends StatelessWidget {
  const _LibraryItems({
    required this.state,
    required this.notes,
    required this.specialView,
    required this.compact,
    required this.onFilterChanged,
    required this.onSelectionChanged,
    required this.onCreate,
    required this.onJoinRoom,
    required this.onOpenNote,
  });

  final LibraryHomeState state;
  final List<NoteItem> notes;
  final LibrarySpecialView specialView;
  final bool compact;
  final ValueChanged<LibraryFilter> onFilterChanged;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;
  final ValueChanged<NoteItem> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final filters = LibraryFilter.values;
    final currentIndex = filters.indexOf(state.selectedFilter);

    void selectOffset(int offset) {
      final nextIndex = (currentIndex + offset).clamp(0, filters.length - 1);
      if (nextIndex != currentIndex) {
        onFilterChanged(filters[nextIndex]);
      }
    }

    final content = _LibraryItemsContent(
      state: state,
      notes: notes,
      specialView: specialView,
      compact: compact,
      onSelectionChanged: onSelectionChanged,
      onCreate: onCreate,
      onJoinRoom: onJoinRoom,
      onOpenNote: onOpenNote,
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 240) {
          return;
        }
        selectOffset(velocity < 0 ? 1 : -1);
      },
      child: content,
    );
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
  });

  final LibraryHomeState state;
  final List<NoteItem> notes;
  final LibrarySpecialView specialView;
  final bool compact;
  final ValueChanged<String> onSelectionChanged;
  final VoidCallback onCreate;
  final VoidCallback onJoinRoom;
  final ValueChanged<NoteItem> onOpenNote;

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
          );
        },
      );
    }

    if (notes.isEmpty) {
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
        title: const Text('新建'),
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
  });

  final NoteItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionChanged;
  final VoidCallback onTap;

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

class _FilterSegmentLabel extends StatelessWidget {
  const _FilterSegmentLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: selected ? colorScheme.primary : const Color(0xFF151918),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: selected ? 58 : 0,
            height: 2,
            color: colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.compact,
    required this.title,
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
  });

  final bool compact;
  final String title;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final VoidCallback onSortDirectionChanged;
  final VoidCallback onSelectionModeChanged;

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
              onPressed: () => onViewModeChanged(LibraryViewMode.grid),
              child: const Text('网格视图'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(LucideIcons.list),
              onPressed: () => onViewModeChanged(LibraryViewMode.list),
              child: const Text('列表视图'),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.controlGap),
        IconButton(
          tooltip: sortAscending ? '按日期升序' : '按日期降序',
          onPressed: onSortDirectionChanged,
          icon: Icon(
            sortAscending
                ? LucideIcons.arrowUpNarrowWide
                : LucideIcons.arrowDownWideNarrow,
          ),
        ),
        const SizedBox(width: AppSpacing.controlGap),
        IconButton(
          tooltip: selectionMode ? '退出多选' : '多选',
          isSelected: selectionMode,
          onPressed: onSelectionModeChanged,
          icon: const Icon(LucideIcons.squareCheck),
          selectedIcon: const Icon(LucideIcons.checkSquare),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return _LibraryIndexMenu(
      enabled: enabled,
      libraryIndex: libraryIndex,
      label: '移动到',
      builder: (index) => [
        MenuItemButton(
          onPressed: () => onSelected(null),
          child: const Text('未归入笔记本'),
        ),
        for (final notebook in index.notebooks)
          MenuItemButton(
            onPressed: () => onSelected(notebook.id),
            child: Text(notebook.name),
          ),
      ],
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
    return _LibraryIndexMenu(
      enabled: enabled,
      libraryIndex: libraryIndex,
      label: '添加标签',
      builder: (index) => [
        for (final tag in index.tags)
          MenuItemButton(
            onPressed: () => onSelected([tag.id]),
            child: Text(tag.name),
          ),
      ],
    );
  }
}

class _LibraryIndexMenu extends StatelessWidget {
  const _LibraryIndexMenu({
    required this.enabled,
    required this.libraryIndex,
    required this.label,
    required this.builder,
  });

  final bool enabled;
  final LibraryIndex libraryIndex;
  final String label;
  final List<Widget> Function(LibraryIndex index) builder;

  @override
  Widget build(BuildContext context) {
    final children = builder(libraryIndex);
    return MenuAnchor(
      menuChildren: children.isEmpty
          ? [const MenuItemButton(child: Text('暂无可选项'))]
          : children,
      builder: (context, controller, child) {
        return TextButton(
          onPressed: !enabled
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          child: Text(label),
        );
      },
    );
  }
}
