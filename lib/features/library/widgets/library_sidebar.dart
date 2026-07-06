import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../folders/view_models/folders_view_model.dart';
import '../../../shared/widgets/app_shell.dart';

class LibrarySidebar extends ConsumerStatefulWidget {
  const LibrarySidebar({super.key, required this.section});

  final ShellSection section;

  @override
  ConsumerState<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends ConsumerState<LibrarySidebar> {
  bool _allNotesExpanded = true;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _ProMark(),
                _HeaderIconButton(
                  tooltip: '侧边栏',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.panelLeft),
                ),
                _HeaderIconButton(
                  tooltip: '设置',
                  onPressed: () => context.go(AppRoutes.settings),
                  icon: const Icon(LucideIcons.settings),
                ),
                _HeaderIconButton(
                  tooltip: '商店',
                  onPressed: () {},
                  icon: const Icon(LucideIcons.store),
                ),
              ],
            ),
          ),
          _SidebarSearch(
            selected: widget.section == ShellSection.search,
            onTap: () => context.go(AppRoutes.search),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                _SidebarItem(
                  icon: LucideIcons.squarePen,
                  label: '全部笔记',
                  selected: widget.section == ShellSection.library,
                  trailingIcon: _allNotesExpanded
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  onTrailingTap: () {
                    setState(() => _allNotesExpanded = !_allNotesExpanded);
                  },
                  onTap: () => context.go(AppRoutes.library),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeOutCubic,
                  child: _allNotesExpanded
                      ? const Column(
                          key: ValueKey('all-notes-children'),
                          children: [
                            _SidebarItem(
                              icon: LucideIcons.folderX,
                              label: '未分类',
                              count: '10',
                              level: 1,
                            ),
                            _SidebarItem(
                              icon: LucideIcons.tags,
                              label: '未标签',
                              count: '10',
                              level: 1,
                            ),
                          ],
                        )
                      : const SizedBox.shrink(key: ValueKey('empty-children')),
                ),
                const _SidebarItem(icon: LucideIcons.trash2, label: '回收站'),
                const Divider(
                  height: 20,
                  indent: 24,
                  endIndent: 28,
                  color: Color(0xFFE3EFEC),
                ),
                _SidebarItem(
                  icon: LucideIcons.folder,
                  label: '文件夹',
                  selected: widget.section == ShellSection.folders,
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
        height: 46,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 20, color: color),
            const SizedBox(width: 10),
            Text(
              '搜索',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                height: 1.1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
    this.onTrailingTap,
    this.onTap,
    this.level = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? count;
  final IconData? trailingIcon;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTap;
  final int level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : const Color(0xFF252C2A);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: level == 0 ? 42 : 36,
        margin: EdgeInsets.fromLTRB(10 + level * 16, 1, 10, 1),
        padding: EdgeInsets.fromLTRB(level == 0 ? 12 : 10, 0, 8, 0),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground.withValues(alpha: 0.86), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (actionIcon != null) ...[
              IconButton(
                tooltip: '新建$label',
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: onActionTap,
                icon: Icon(actionIcon, color: colorScheme.primary, size: 16),
              ),
              const SizedBox(width: 8),
            ],
            if (count != null)
              Text(
                count!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFA5AFAA),
                  height: 1.1,
                ),
              ),
            if (trailingIcon != null)
              IconButton(
                tooltip: '$label展开收起',
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: onTrailingTap,
                icon: Icon(
                  trailingIcon,
                  color: const Color(0xFF69736F),
                  size: 16,
                ),
              ),
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
        radius: 18,
        backgroundColor: const Color(0xFFF9F5EA),
        child: Icon(
          LucideIcons.sparkles,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      iconSize: 18,
      color: const Color(0xFF53605B),
      icon: icon,
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
