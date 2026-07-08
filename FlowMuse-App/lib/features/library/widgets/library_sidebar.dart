import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/shared_sidebar.dart';
import '../../notebooks/view_models/notebooks_view_model.dart';
import '../repositories/library_repository.dart';
import '../../tags/view_models/tags_view_model.dart';

class LibrarySidebar extends ConsumerStatefulWidget {
  const LibrarySidebar({super.key, required this.section});

  final ShellSection section;

  @override
  ConsumerState<LibrarySidebar> createState() => _LibrarySidebarState();
}

class _LibrarySidebarState extends ConsumerState<LibrarySidebar> {
  bool _allNotesExpanded = true;
  bool _notebooksExpanded = true;
  bool _tagsExpanded = true;

  @override
  Widget build(BuildContext context) {
    final notebooks = ref.watch(notebooksViewModelProvider).visibleNotebooks;
    final tags = ref.watch(tagsViewModelProvider).tags;
    final libraryIndex = ref.watch(libraryIndexProvider).asData?.value;
    final hasNotebooks = notebooks.isNotEmpty;
    final hasTags = tags.isNotEmpty;

    return SharedSidebar(
      header: SharedSidebarHeader(
        trailing: [
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
                  ? Column(
                      key: ValueKey('all-notes-children'),
                      children: [
                        SharedSidebarItem(
                          icon: LucideIcons.bookX,
                          label: '未归入笔记本',
                          count: (libraryIndex?.unnotebookedCount ?? 0)
                              .toString(),
                          level: 1,
                          onTap: () => context.go(AppRoutes.unnotebooked),
                        ),
                        SharedSidebarItem(
                          icon: LucideIcons.tags,
                          label: '未标签',
                          count: (libraryIndex?.untaggedCount ?? 0).toString(),
                          level: 1,
                          onTap: () => context.go(AppRoutes.untagged),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('empty-children')),
            ),
            SharedSidebarItem(
              icon: LucideIcons.trash2,
              label: '回收站',
              count: (libraryIndex?.deletedNotes.length ?? 0).toString(),
              onTap: () => context.go(AppRoutes.trash),
            ),
          ],
        ),
        SharedSidebarBlock(
          children: [
            SharedSidebarItem(
              icon: LucideIcons.bookOpen,
              label: '笔记本',
              selected: widget.section == ShellSection.notebooks,
              actionIcon: LucideIcons.circlePlus,
              leadingAction: true,
              emptyLabel: hasNotebooks ? null : '暂无笔记本',
              trailingIcon: hasNotebooks
                  ? (_notebooksExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight)
                  : null,
              onActionTap: () {
                ref.read(notebooksViewModelProvider.notifier).createNotebook();
                context.go(AppRoutes.notebooks);
              },
              onTrailingTap: () {
                setState(() => _notebooksExpanded = !_notebooksExpanded);
              },
              onTap: () => context.go(AppRoutes.notebooks),
            ),
            if (hasNotebooks)
              SharedSidebarChildren(
                expanded: _notebooksExpanded,
                emptyKey: 'empty-notebooks',
                childrenKey: 'notebook-children',
                children: [
                  for (final notebook in notebooks)
                    SharedSidebarItem(
                      icon: LucideIcons.bookOpen,
                      label: notebook.name,
                      count: notebook.count.toString(),
                      level: 1,
                      onTap: () =>
                          context.go(AppRoutes.notebookPath(notebook.id)),
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
