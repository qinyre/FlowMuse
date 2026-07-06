import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models/notebook_item.dart';
import '../view_models/folders_view_model.dart';

class FoldersPage extends ConsumerWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(foldersViewModelProvider);
    final viewModel = ref.read(foldersViewModelProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 34, 36, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FoldersHeader(
            state: state,
            onCreate: viewModel.createFolder,
            onViewModeChanged: viewModel.changeViewMode,
            onSortDirectionChanged: viewModel.toggleSortDirection,
            onSelectionModeChanged: viewModel.toggleSelectionMode,
          ),
          const SizedBox(height: 34),
          Expanded(
            child: state.visibleFolders.isEmpty
                ? _EmptyFolders(onCreate: viewModel.createFolder)
                : _FolderItems(state: state),
          ),
        ],
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.folderSearch,
            size: 126,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 28),
          Text(
            '这里空空如也...',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: const Color(0xFF555F5B)),
          ),
          const SizedBox(height: 12),
          Text(
            '点击新建文件夹开始整理笔记',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFA5AFAA)),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(LucideIcons.folderPlus),
            label: const Text('新建文件夹'),
          ),
        ],
      ),
    );
  }
}

class _FolderItems extends StatelessWidget {
  const _FolderItems({required this.state});

  final FoldersState state;

  @override
  Widget build(BuildContext context) {
    if (state.viewMode == LibraryViewMode.list) {
      return ListView.separated(
        itemCount: state.visibleFolders.length,
        separatorBuilder: (context, index) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final folder = state.visibleFolders[index];
          return Card.outlined(
            child: ListTile(
              leading: const Icon(LucideIcons.folder),
              title: Text(folder.name),
              subtitle: Text('${folder.count} 个项目'),
              trailing: state.selectionMode
                  ? const Checkbox(value: false, onChanged: null)
                  : const Icon(LucideIcons.chevronRight),
            ),
          );
        },
      );
    }

    return GridView.builder(
      itemCount: state.visibleFolders.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 156,
        crossAxisSpacing: 22,
        mainAxisSpacing: 22,
      ),
      itemBuilder: (context, index) {
        final folder = state.visibleFolders[index];
        return Card.outlined(
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.folder,
                      color: Theme.of(context).colorScheme.primary,
                      size: 34,
                    ),
                    const Spacer(),
                    Text(
                      folder.name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${folder.count} 个项目',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFA5AFAA),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.selectionMode)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Checkbox(value: false, onChanged: null),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FoldersHeader extends StatelessWidget {
  const _FoldersHeader({
    required this.state,
    required this.onCreate,
    required this.onViewModeChanged,
    required this.onSortDirectionChanged,
    required this.onSelectionModeChanged,
  });

  final FoldersState state;
  final VoidCallback onCreate;
  final ValueChanged<LibraryViewMode> onViewModeChanged;
  final VoidCallback onSortDirectionChanged;
  final VoidCallback onSelectionModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '文件夹',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F2624),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '新建文件夹',
          onPressed: onCreate,
          icon: const Icon(LucideIcons.folderPlus),
        ),
        const SizedBox(width: 8),
        MenuAnchor(
          builder: (context, controller, child) {
            return IconButton(
              tooltip: state.viewMode == LibraryViewMode.grid ? '网格视图' : '列表视图',
              onPressed: () {
                controller.isOpen ? controller.close() : controller.open();
              },
              icon: Icon(
                state.viewMode == LibraryViewMode.grid
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
          tooltip: state.sortAscending ? '按名称升序' : '按名称降序',
          onPressed: onSortDirectionChanged,
          icon: Icon(
            state.sortAscending
                ? LucideIcons.arrowUpNarrowWide
                : LucideIcons.arrowDownWideNarrow,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: state.selectionMode ? '退出多选' : '多选',
          isSelected: state.selectionMode,
          onPressed: onSelectionModeChanged,
          icon: const Icon(LucideIcons.squareCheck),
          selectedIcon: const Icon(LucideIcons.checkSquare),
        ),
      ],
    );
  }
}
