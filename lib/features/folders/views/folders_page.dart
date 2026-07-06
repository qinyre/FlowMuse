import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_shell.dart';

class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      section: ShellSection.folders,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 34, 36, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FoldersHeader(),
            const Spacer(),
            Center(
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF555F5B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '点击左侧「文件夹 +」创建文件夹',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFA5AFAA),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

class _FoldersHeader extends StatelessWidget {
  const _FoldersHeader();

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
