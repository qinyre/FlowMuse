import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF6F2),
        border: Border(right: BorderSide(color: Color(0xFFDCE9E5))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFF8F6EE),
                  foregroundColor: const Color(0xFFC0A779),
                  child: Text(
                    'PRO',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '侧边栏',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.panelLeft),
                ),
                IconButton(
                  tooltip: '设置',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.settings),
                ),
                IconButton(
                  tooltip: '商店',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.store),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: SearchBar(leading: Icon(LucideIcons.search), hintText: '搜索'),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: NavigationRail(
              extended: true,
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(LucideIcons.notebookPen),
                  selectedIcon: Icon(LucideIcons.notebookPen),
                  label: Text('全部笔记'),
                ),
                NavigationRailDestination(
                  icon: Badge(
                    label: Text('10'),
                    child: Icon(LucideIcons.folderX),
                  ),
                  label: Text('未分类'),
                ),
                NavigationRailDestination(
                  icon: Badge(label: Text('10'), child: Icon(LucideIcons.tag)),
                  label: Text('未标签'),
                ),
                NavigationRailDestination(
                  icon: Icon(LucideIcons.trash2),
                  label: Text('回收站'),
                ),
                NavigationRailDestination(
                  icon: Icon(LucideIcons.folder),
                  label: Text('文件夹'),
                ),
                NavigationRailDestination(
                  icon: Icon(LucideIcons.hash),
                  label: Text('标签'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Card.filled(
              color: colorScheme.primaryContainer.withValues(alpha: 0.45),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(LucideIcons.palette),
                    SizedBox(width: 12),
                    Expanded(child: Text('主题色和侧栏背景可在设置中自定义')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
