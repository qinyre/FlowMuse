import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../library/widgets/note_card.dart';
import '../view_models/search_view_model.dart';

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(searchViewModelProvider);
    final viewModel = ref.read(searchViewModelProvider.notifier);
    final libraryIndex =
        ref.watch(libraryIndexProvider).asData?.value ?? const LibraryIndex();
    final notebookLabel = state.notebookScopeId == null
        ? '全部笔记本'
        : libraryIndex.notebooks
                  .where((item) => item.id == state.notebookScopeId)
                  .firstOrNull
                  ?.name ??
              '全部笔记本';
    final tagLabel = state.tagScopeId == null
        ? '全部标签'
        : libraryIndex.tags
                  .where((item) => item.id == state.tagScopeId)
                  .firstOrNull
                  ?.name ??
              '全部标签';
    final results = _searchNotes(state, libraryIndex);

    return RightPageScaffold(
      header: Row(
        children: [
          Expanded(
            child: SearchBar(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: AppSpacing.sidebarInset),
              ),
              leading: Icon(
                LucideIcons.search,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              hintText: '请输入关键字搜索笔记',
              onChanged: viewModel.changeQuery,
            ),
          ),
          const SizedBox(width: AppSpacing.controlGap),
          TextButton(
            onPressed: () => context.go(AppRoutes.library),
            child: const Text('取消'),
          ),
        ],
      ),
      topContent: [
        Wrap(
          spacing: AppSpacing.listGap,
          runSpacing: AppSpacing.controlGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _ScopeMenu(
              icon: LucideIcons.notebook,
              tooltip: '选择笔记本范围',
              label: notebookLabel,
              options: [
                const _ScopeOption(id: null, label: '全部笔记本'),
                for (final notebook in libraryIndex.notebooks)
                  _ScopeOption(id: notebook.id, label: notebook.name),
              ],
              onSelected: viewModel.selectNotebookScope,
            ),
            _ScopeMenu(
              icon: LucideIcons.tag,
              tooltip: '选择标签范围',
              label: tagLabel,
              options: [
                const _ScopeOption(id: null, label: '全部标签'),
                for (final tag in libraryIndex.tags)
                  _ScopeOption(id: tag.id, label: tag.name),
              ],
              onSelected: viewModel.selectTagScope,
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                state.query.trim().isEmpty
                    ? '本地搜索 · 标题与副标题'
                    : '找到 ${results.length} 条笔记',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.listGap),
      ],
      body: _SearchResults(
        query: state.query,
        results: results,
        onOpenNote: (item) {
          context.push(
            AppRoutes.whiteboardPath(
              noteId: item.id,
              discardIfUnchanged: false,
            ),
          );
        },
      ),
    );
  }
}

class _ScopeOption {
  const _ScopeOption({required this.id, required this.label});

  final String? id;
  final String label;
}

class _ScopeMenu extends StatelessWidget {
  const _ScopeMenu({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final List<_ScopeOption> options;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Tooltip(
          message: tooltip,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
              ),
              onPressed: () async {
                final selected = await showAnchoredPopupMenu<_ScopeOption>(
                  context: context,
                  placement: AnchoredPopupPlacement.below,
                  items: [
                    for (final option in options)
                      PopupMenuItem<_ScopeOption>(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                );
                if (selected == null || !context.mounted) {
                  return;
                }
                runAfterUiTeardown(() => onSelected(selected.id));
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: AppSpacing.controlGap),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpacing.controlGap),
                  const Icon(LucideIcons.chevronDown, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.results,
    required this.onOpenNote,
  });

  final String query;
  final List<NoteItem> results;
  final ValueChanged<NoteItem> onOpenNote;

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return const _SearchEmptyState(
        icon: LucideIcons.search,
        title: '输入标题关键字',
        message: '按标题或副标题查找本地笔记。',
      );
    }
    if (results.isEmpty) {
      return const _SearchEmptyState(
        icon: LucideIcons.fileX,
        title: '没有匹配笔记',
        message: '换一个关键字或调整搜索范围。',
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.listGap),
      itemBuilder: (context, index) {
        final item = results[index];
        return Card.outlined(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 58,
                child: NoteCover(item: item),
              ),
            ),
            title: Text(item.title),
            subtitle: Text(item.date),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => onOpenNote(item),
          ),
        );
      },
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 38,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

List<NoteItem> _searchNotes(SearchState state, LibraryIndex libraryIndex) {
  final query = state.query.trim().toLowerCase();
  if (query.isEmpty) {
    return const [];
  }
  return libraryIndex.notesForQuery(
    LibraryQuery(
      queryText: query,
      notebookId: state.notebookScopeId,
      tagIds: state.tagScopeId == null ? const [] : [state.tagScopeId!],
    ),
  );
}
