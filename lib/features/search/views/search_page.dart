import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_shell.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      section: ShellSection.search,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 34, 36, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: SearchBar(
                    leading: Icon(LucideIcons.search),
                    hintText: '请输入关键字搜索笔记',
                    trailing: [_SmartSearchChip()],
                  ),
                ),
                const SizedBox(width: 28),
                TextButton(
                  onPressed: () => context.go(AppRoutes.library),
                  child: const Text('取消'),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text(
              '搜索范围',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFF8F9B96)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 26,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: const [
                Text('文件夹'),
                _ScopeMenu(label: '尚未选择文件夹'),
                Text('标签'),
                _ScopeMenu(label: '尚未选择标签'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.fileSearch, color: Color(0xFF8F9B96)),
                    SizedBox(width: 8),
                    Text('已选搜索范围', style: TextStyle(color: Color(0xFF8F9B96))),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartSearchChip extends StatelessWidget {
  const _SmartSearchChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        '智能搜索',
        style: TextStyle(color: Color(0xFFFAFCFA), fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ScopeMenu extends StatelessWidget {
  const _ScopeMenu({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: () {
            controller.isOpen ? controller.close() : controller.open();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 58),
              const Icon(LucideIcons.chevronDown, size: 16),
            ],
          ),
        );
      },
      menuChildren: const [MenuItemButton(child: Text('暂无可选项'))],
    );
  }
}
