import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/notebook_item.dart';
import '../../library/repositories/library_repository.dart';

@immutable
class TagItem {
  const TagItem({
    required this.id,
    required this.name,
    required this.count,
    required this.coverColor,
    this.notebookIds = const [],
  });

  final String id;
  final String name;
  final int count;
  final Color coverColor;
  final List<String> notebookIds;
}

@immutable
class TagsState {
  const TagsState({
    this.tags = const [],
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = true,
    this.selectionMode = false,
  });

  final List<TagItem> tags;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;

  List<TagItem> get visibleTags {
    final sorted = tags.toList()
      ..sort((a, b) {
        final result = a.name.compareTo(b.name);
        return sortAscending ? result : -result;
      });
    return sorted;
  }

  TagsState copyWith({
    List<TagItem>? tags,
    LibraryViewMode? viewMode,
    bool? sortAscending,
    bool? selectionMode,
  }) {
    return TagsState(
      tags: tags ?? this.tags,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
    );
  }
}

class TagsViewModel extends Notifier<TagsState> {
  @override
  TagsState build() {
    final index = ref.watch(libraryIndexProvider).asData?.value;
    final tags = index == null
        ? const <TagItem>[]
        : [
            for (final tag in index.tags)
              TagItem(
                id: tag.id,
                name: tag.name,
                count: index.notebooks
                    .where((item) => item.tagIds.contains(tag.id))
                    .length,
                coverColor: tag.coverColor,
                notebookIds: [
                  for (final notebook in index.notebooks)
                    if (notebook.tagIds.contains(tag.id)) notebook.id,
                ],
              ),
          ];
    return TagsState(tags: tags);
  }

  Future<void> createTag() {
    return ref.read(libraryIndexProvider.notifier).createTag();
  }

  void changeViewMode(LibraryViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void toggleSortDirection() {
    state = state.copyWith(sortAscending: !state.sortAscending);
  }

  void toggleSelectionMode() {
    state = state.copyWith(selectionMode: !state.selectionMode);
  }
}

final tagsViewModelProvider = NotifierProvider<TagsViewModel, TagsState>(
  TagsViewModel.new,
);
