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
    required this.onCreate,
    required this.onOpenNotebook,
  });

  final bool compact;
  final LibraryHomeState state;
  final ValueChanged<LibraryFilter> onFilterChanged;
  final VoidCallback onCreate;
  final ValueChanged<NotebookItem> onOpenNotebook;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 34, compact ? 20 : 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(compact: compact),
          const SizedBox(height: 46),
          _FilterTabs(
            selected: state.selectedFilter,
            onFilterChanged: onFilterChanged,
          ),
          const SizedBox(height: 34),
          Expanded(
            child: GridView.builder(
              itemCount: state.visibleNotebooks.length + 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: compact ? 2 : 3,
                mainAxisExtent: 332,
                crossAxisSpacing: compact ? 26 : 66,
                mainAxisSpacing: 62,
              ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return CreateNotebookCard(onTap: onCreate);
                }
                final item = state.visibleNotebooks[index - 1];
                return NotebookCard(
                  item: item,
                  onTap: () => onOpenNotebook(item),
                );
              },
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
    return Row(
      key: const ValueKey('library-filter-tabs'),
      children: [
        _FilterTab(
          label: '全部',
          selected: selected == LibraryFilter.all,
          onTap: () => onFilterChanged(LibraryFilter.all),
        ),
        const SizedBox(width: 42),
        _FilterTab(
          label: '笔记',
          selected: selected == LibraryFilter.notes,
          onTap: () => onFilterChanged(LibraryFilter.notes),
        ),
        const SizedBox(width: 42),
        _FilterTab(
          label: 'PDF',
          selected: selected == LibraryFilter.pdf,
          onTap: () => onFilterChanged(LibraryFilter.pdf),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
  const _LibraryHeader({required this.compact});

  final bool compact;

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
        IconButton(
          tooltip: '网格视图',
          onPressed: () {},
          icon: const Icon(LucideIcons.layoutGrid),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '排序',
          onPressed: () {},
          icon: const Icon(LucideIcons.arrowDownUp),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '多选',
          onPressed: () {},
          icon: const Icon(LucideIcons.squareCheck),
        ),
      ],
    );
  }
}
