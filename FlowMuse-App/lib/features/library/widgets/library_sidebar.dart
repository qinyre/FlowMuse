import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/shared_sidebar.dart';
import '../../folders/view_models/folders_view_model.dart';
import '../../tags/view_models/tags_view_model.dart';

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
    final folders = ref.watch(foldersViewModelProvider).visibleFolders;
    final tags = ref.watch(tagsViewModelProvider).tags;
    final hasFolders = folders.isNotEmpty;
    final hasTags = tags.isNotEmpty;

    return SharedSidebar(
      header: SharedSidebarHeader(
        trailing: [
          SharedSidebarIconButton(
            tooltip: '侧边栏',
            onPressed: () {},
            icon: const Icon(LucideIcons.panelLeft),
          ),
          SharedSidebarIconButton(
            tooltip: '设置',
            onPressed: () => context.go(AppRoutes.settings),
            icon: const Icon(LucideIcons.settings),
          ),
        ],
      ),
      children: [
        SharedSidebarItem(
          icon: LucideIcons.search,
          label: '搜索',
          selected: widget.section == ShellSection.search,
          onTap: () => context.go(AppRoutes.search),
        ),
        SharedSidebarBlock(
          children: [
            SharedSidebarItem(
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
                        SharedSidebarItem(
                          icon: LucideIcons.folderX,
                          label: '未分类',
                          count: '10',
                          level: 1,
                        ),
                        SharedSidebarItem(
                          icon: LucideIcons.tags,
                          label: '未标签',
                          count: '10',
                          level: 1,
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('empty-children')),
            ),
            const SharedSidebarItem(icon: LucideIcons.trash2, label: '回收站'),
          ],
        ),
        SharedSidebarBlock(
          children: [
            SharedSidebarItem(
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
              SharedSidebarChildren(
                expanded: _foldersExpanded,
                emptyKey: 'empty-folders',
                childrenKey: 'folder-children',
                children: [
                  for (final folder in folders)
                    SharedSidebarItem(
                      icon: LucideIcons.folder,
                      label: folder.name,
                      count: folder.count.toString(),
                      level: 1,
                      onTap: () => context.go(AppRoutes.folderPath(folder.id)),
                    ),
                ],
              ),
          ],
        ),
        SharedSidebarBlock(
          children: [
            SharedSidebarItem(
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
              SharedSidebarChildren(
                expanded: _tagsExpanded,
                emptyKey: 'empty-tags',
                childrenKey: 'tag-children',
                children: [
                  for (final tag in tags)
                    SharedSidebarItem(
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
      ],
    );
  }
}
