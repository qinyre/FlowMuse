import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../folders/view_models/folders_view_model.dart';
import '../../../shared/widgets/app_shell.dart';

class LibrarySidebar extends ConsumerWidget {
  const LibrarySidebar({super.key, required this.section});

  final ShellSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;

    return Container(
      width: sharedSidebarWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primary.withValues(alpha: 0.035),
            colorScheme.primary.withValues(alpha: 0.11),
          ],
        ),
        border: const Border(right: BorderSide(color: Color(0xFFE3EFEC))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _ProMark(),
                IconButton(
                  tooltip: '侧边栏',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.panelLeft),
                ),
                IconButton(
                  tooltip: '设置',
                  onPressed: () => context.go(AppRoutes.settings),
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
          _SidebarSearch(
            selected: section == ShellSection.search,
            onTap: () => context.go(AppRoutes.search),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 12),
              children: [
                _SidebarItem(
                  icon: LucideIcons.squarePen,
                  label: '全部笔记',
                  selected: section == ShellSection.library,
                  trailingIcon: LucideIcons.chevronDown,
                  onTap: () => context.go(AppRoutes.library),
                ),
                const _SidebarItem(
                  icon: LucideIcons.folderX,
                  label: '未分类',
                  count: '10',
                ),
                const _SidebarItem(
                  icon: LucideIcons.tags,
                  label: '未标签',
                  count: '10',
                ),
                const _SidebarItem(icon: LucideIcons.trash2, label: '回收站'),
                const Divider(
                  height: 28,
                  indent: 26,
                  endIndent: 32,
                  color: Color(0xFFE3EFEC),
                ),
                _SidebarItem(
                  icon: LucideIcons.folder,
                  label: '文件夹',
                  selected: section == ShellSection.folders,
                  count: '暂无文件夹',
                  actionIcon: LucideIcons.circlePlus,
                  onActionTap: () {
                    ref.read(foldersViewModelProvider.notifier).createFolder();
                    context.go(AppRoutes.folders);
                  },
                  onTap: () => context.go(AppRoutes.folders),
                ),
                const _SidebarItem(
                  icon: LucideIcons.hash,
                  label: '标签',
                  count: '暂无标签',
                  actionIcon: LucideIcons.circlePlus,
                ),
              ],
            ),
          ),
          _MountainFooter(accent: accent),
        ],
      ),
    );
  }
}

class _SidebarSearch extends StatelessWidget {
  const _SidebarSearch({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected ? colorScheme.primary : const Color(0xFF202827);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 30, color: color),
            const SizedBox(width: 18),
            Text(
              '搜索',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.count,
    this.trailingIcon,
    this.actionIcon,
    this.onActionTap,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? count;
  final IconData? trailingIcon;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : const Color(0xFF252C2A);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.10)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 26),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (actionIcon != null) ...[
              IconButton(
                tooltip: '新建$label',
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: onActionTap,
                icon: Icon(actionIcon, color: colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 16),
            ],
            if (count != null)
              Text(
                count!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA5AFAA),
                ),
              ),
            if (trailingIcon != null)
              Icon(trailingIcon, color: const Color(0xFF69736F), size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProMark extends StatelessWidget {
  const _ProMark();

  @override
  Widget build(BuildContext context) {
    return Badge(
      label: const Text('PRO'),
      backgroundColor: const Color(0xFFE7D5BC),
      textColor: const Color(0xFF876D43),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFF9F5EA),
        child: Icon(
          LucideIcons.sparkles,
          color: Theme.of(context).colorScheme.primary,
          size: 28,
        ),
      ),
    );
  }
}

class _MountainFooter extends StatelessWidget {
  const _MountainFooter({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: accent.withValues(alpha: 0.08)),
          Positioned(
            left: -20,
            right: -20,
            bottom: 0,
            child: Icon(
              LucideIcons.mountain,
              size: 220,
              color: accent.withValues(alpha: 0.32),
            ),
          ),
        ],
      ),
    );
  }
}
