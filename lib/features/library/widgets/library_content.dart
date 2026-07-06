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
      padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 30, compact ? 20 : 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LibraryHeader(compact: compact),
          const SizedBox(height: 28),
          SegmentedButton<LibraryFilter>(
            key: const ValueKey('library-filter-tabs'),
            segments: const [
              ButtonSegment(value: LibraryFilter.all, label: Text('全部')),
              ButtonSegment(value: LibraryFilter.notes, label: Text('笔记')),
              ButtonSegment(value: LibraryFilter.pdf, label: Text('PDF')),
            ],
            selected: {state.selectedFilter},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              onFilterChanged(selection.first);
            },
          ),
          const SizedBox(height: 30),
          Expanded(
            child: GridView.builder(
              itemCount: state.visibleNotebooks.length + 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: compact ? 2 : 3,
                mainAxisExtent: 310,
                crossAxisSpacing: compact ? 24 : 48,
                mainAxisSpacing: 40,
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
            fontWeight: FontWeight.w700,
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
