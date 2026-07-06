import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../folders/view_models/folders_view_model.dart';
import '../../tags/view_models/tags_view_model.dart';
import '../../../shared/widgets/app_shell.dart';

class LibrarySidebar extends ConsumerStatefulWidget {
  const LibrarySidebar({super.key, required this.section});

  final ShellSection section;

  @override
  ConsumerState<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends ConsumerState<LibrarySidebar> {
  bool _allNotesExpanded = true;
  bool _foldersExpanded = true;
  bool _tagsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final folders = ref.watch(foldersViewModelProvider).visibleFolders;
    final tags = ref.watch(tagsViewModelProvider).tags;
    final hasFolders = folders.isNotEmpty;
    final hasTags = tags.isNotEmpty;

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
        border: Border(
          right: BorderSide(color: colorScheme.primary.withValues(alpha: 0.14)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _UserAvatar(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderIconButton(
                      tooltip: '侧边栏',
                      onPressed: () {},
                      icon: const Icon(LucideIcons.panelLeft),
                    ),
                    const SizedBox(width: 4),
                    _HeaderIconButton(
                      tooltip: '设置',
                      onPressed: () => context.go(AppRoutes.settings),
                      icon: const Icon(LucideIcons.settings),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SidebarItem(
            icon: LucideIcons.search,
            label: '搜索',
            selected: widget.section == ShellSection.search,
            onTap: () => context.go(AppRoutes.search),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
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
                _SidebarItem(
                  icon: LucideIcons.folder,
                  label: '文件夹',
                  selected: widget.section == ShellSection.folders,
                  actionIcon: LucideIcons.circlePlus,
                  leadingAction: true,
                  emptyLabel: hasFolders ? null : '暂无文件夹',
                  trailingIcon: hasFolders
                      ? (_foldersExpanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight)
                      : null,
                  onActionTap: () {
                    ref.read(foldersViewModelProvider.notifier).createFolder();
                    context.go(AppRoutes.folders);
                  },
                  onTrailingTap: () {
                    setState(() => _foldersExpanded = !_foldersExpanded);
                  },
                  onTap: () => context.go(AppRoutes.folders),
                ),
                if (hasFolders)
                  _SidebarChildren(
                    expanded: _foldersExpanded,
                    emptyKey: 'empty-folders',
                    childrenKey: 'folder-children',
                    children: [
                      for (final folder in folders)
                        _SidebarItem(
                          icon: LucideIcons.folder,
                          label: folder.name,
                          count: folder.count.toString(),
                          level: 1,
                          onTap: () =>
                              context.go(AppRoutes.folderPath(folder.id)),
                        ),
                    ],
                  ),
                _SidebarItem(
                  icon: LucideIcons.hash,
                  label: '标签',
                  selected: widget.section == ShellSection.tags,
                  actionIcon: LucideIcons.circlePlus,
                  leadingAction: true,
                  emptyLabel: hasTags ? null : '暂无标签',
                  trailingIcon: hasTags
                      ? (_tagsExpanded
                            ? LucideIcons.chevronDown
                            : LucideIcons.chevronRight)
                      : null,
                  onActionTap: () {
                    ref.read(tagsViewModelProvider.notifier).createTag();
                    context.go(AppRoutes.tags);
                  },
                  onTrailingTap: () {
                    setState(() => _tagsExpanded = !_tagsExpanded);
                  },
                  onTap: () => context.go(AppRoutes.tags),
                ),
                if (hasTags)
                  _SidebarChildren(
                    expanded: _tagsExpanded,
                    emptyKey: 'empty-tags',
                    childrenKey: 'tag-children',
                    children: [
                      for (final tag in tags)
                        _SidebarItem(
                          icon: LucideIcons.hash,
                          label: tag.name,
                          count: tag.count.toString(),
                          level: 1,
                          onTap: () => context.go(AppRoutes.tagPath(tag.id)),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
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
    this.emptyLabel,
    this.leadingAction = false,
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
  final String? emptyLabel;
  final bool leadingAction;
  final VoidCallback? onActionTap;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTap;
  final int level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: level == 0 ? 36 : 32,
        padding: EdgeInsets.fromLTRB(16 + level * 18, 0, 10, 0),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: colorScheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground.withValues(alpha: 0.78), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        fontSize: level == 0 ? 13 : 12,
                        height: 1.0,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (leadingAction && actionIcon != null) ...[
                    const SizedBox(width: 6),
                    _SidebarActionButton(
                      tooltip: '新建$label',
                      icon: actionIcon!,
                      onPressed: onActionTap,
                    ),
                  ],
                ],
              ),
            ),
            if (!leadingAction && actionIcon != null) ...[
              _SidebarActionButton(
                tooltip: '新建$label',
                icon: actionIcon!,
                onPressed: onActionTap,
              ),
              const SizedBox(width: 8),
            ],
            if (count != null)
              Text(
                count!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.0,
                ),
              ),
            if (emptyLabel != null)
              Text(
                emptyLabel!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
                  fontSize: 11,
                  height: 1.0,
                ),
              ),
            if (trailingIcon != null)
              IconButton(
                tooltip: '$label展开收起',
                constraints: const BoxConstraints.tightFor(
                  width: 26,
                  height: 26,
                ),
                padding: EdgeInsets.zero,
                onPressed: onTrailingTap,
                icon: Icon(
                  trailingIcon,
                  color: colorScheme.onSurfaceVariant,
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarChildren extends StatelessWidget {
  const _SidebarChildren({
    required this.expanded,
    required this.emptyKey,
    required this.childrenKey,
    required this.children,
  });

  final bool expanded;
  final String emptyKey;
  final String childrenKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: expanded
          ? Column(key: ValueKey(childrenKey), children: children)
          : SizedBox.shrink(key: ValueKey(emptyKey)),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  const _SidebarActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 15),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar();

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.12),
      child: Icon(
        LucideIcons.sparkles,
        color: Theme.of(context).colorScheme.primary,
        size: 20,
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
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: icon,
    );
  }
}
