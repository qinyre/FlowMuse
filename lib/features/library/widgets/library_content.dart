import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/notebook_item.dart';
import '../view_models/library_home_view_model.dart';
import 'create_notebook_card.dart';
import 'notebook_card.dart';

class LibraryContent extends StatelessWidget {
  const LibraryContent({
    super.key,
    required this.compact,
    required this.state,
    required this.onFilterChanged,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
    required this.onCreate,
    required this.onOpenNotebook,
  });

  final bool compact;
  final LibraryHomeState state;
  final ValueChanged<LibraryFilter> onFilterChanged;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final VoidCallback onSortDirectionChanged;
  final VoidCallback onSelectionModeChanged;
  final VoidCallback onCreate;
  final ValueChanged<NotebookItem> onOpenNotebook;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 34, compact ? 20 : 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(
            compact: compact,
            viewMode: state.viewMode,
            sortAscending: state.sortAscending,
            selectionMode: state.selectionMode,
            onViewModeChanged: onViewModeChanged,
            onSortDirectionChanged: onSortDirectionChanged,
            onSelectionModeChanged: onSelectionModeChanged,
          ),
          const SizedBox(height: 46),
          _FilterTabs(
            selected: state.selectedFilter,
            onFilterChanged: onFilterChanged,
          ),
          const SizedBox(height: 34),
          Expanded(
            child: _LibraryItems(
              state: state,
              compact: compact,
              onCreate: onCreate,
              onOpenNotebook: onOpenNotebook,
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
    required this.compact,
    required this.onCreate,
    required this.onOpenNotebook,
  });

  final LibraryHomeState state;
  final bool compact;
  final VoidCallback onCreate;
  final ValueChanged<NotebookItem> onOpenNotebook;

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount: state.visibleNotebooks.length + 1,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateNotebookTile(onTap: onCreate);
          }
          final item = state.visibleNotebooks[index - 1];
          return _NotebookTile(
            item: item,
            selectionMode: state.selectionMode,
            onTap: () => onOpenNotebook(item),
          );
        },
      );
    }

    return GridView.builder(
      itemCount: state.visibleNotebooks.length + 1,
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
        final item = state.visibleNotebooks[index - 1];
        return Stack(
          children: [
            Positioned.fill(
              child: NotebookCard(
                item: item,
                onTap: () => onOpenNotebook(item),
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

class _CreateNotebookTile extends StatelessWidget {
  const _CreateNotebookTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        key: const ValueKey('create-notebook-list-tile'),
        leading: const Icon(LucideIcons.plus),
        title: const Text('新建'),
        subtitle: const Text('创建快捷笔记'),
        onTap: onTap,
      ),
    );
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.item,
    required this.selectionMode,
    required this.onTap,
  });

  final NotebookItem item;
  final bool selectionMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 48,
            height: 58,
            child: NotebookCover(item: item),
          ),
        ),
        title: Text(item.title),
        subtitle: Text(item.date),
        trailing: selectionMode
            ? const Checkbox(value: false, onChanged: null)
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
    required this.viewMode,
    required this.sortAscending,
    required this.selectionMode,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
  });

  final bool compact;
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
        if (compact)
          IconButton(
            tooltip: '菜单',
            onPressed: () {},
            icon: const Icon(LucideIcons.menu),
          ),
        Text(
          '全部笔记',
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
        const SizedBox(width: 8),
        IconButton(
          tooltip: sortAscending ? '按日期升序' : '按日期降序',
          onPressed: onSortDirectionChanged,
          icon: Icon(
            sortAscending
                ? LucideIcons.arrowUpNarrowWide
                : LucideIcons.arrowDownWideNarrow,
          ),
        ),
        const SizedBox(width: 8),
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
