import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';

@immutable
class TagItem {
  const TagItem({
    required this.id,
    required this.name,
    required this.count,
    required this.coverColor,
    this.coverImage,
    this.noteIds = const [],
  });

  final String id;
  final String name;
  final int count;
  final Color coverColor;
  final String? coverImage;
  final List<String> noteIds;
}

@immutable
class TagsState {
  const TagsState({
    this.tags = const [],
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = true,
    this.selectionMode = false,
    this.selectedTagIds = const {},
  });

  final List<TagItem> tags;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final Set<String> selectedTagIds;

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
    Set<String>? selectedTagIds,
  }) {
    return TagsState(
      tags: tags ?? this.tags,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedTagIds: selectedTagIds ?? this.selectedTagIds,
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
                count: index.countNotesWithTag(tag.id),
                coverColor: tag.coverColor,
                coverImage: tag.coverImage,
                noteIds: [
                  for (final note in index.notes)
                    if (!note.isDeleted && note.tagIds.contains(tag.id))
                      note.id,
                ],
              ),
          ];
    return TagsState(tags: tags);
  }

  Future<LibraryTag> createTag({
    String? name,
    Color? coverColor,
    String? coverImage,
  }) {
    return ref
        .read(libraryIndexProvider.notifier)
        .createTag(name: name, coverColor: coverColor, coverImage: coverImage);
  }

  void changeViewMode(LibraryViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void toggleSortDirection() {
    state = state.copyWith(sortAscending: !state.sortAscending);
  }

  void toggleSelectionMode() {
    state = state.copyWith(
      selectionMode: !state.selectionMode,
      selectedTagIds: const {},
    );
  }

  void toggleTagSelection(String tagId) {
    final selected = Set<String>.from(state.selectedTagIds);
    selected.contains(tagId) ? selected.remove(tagId) : selected.add(tagId);
    state = state.copyWith(selectedTagIds: selected);
  }

  void clearSelection() {
    state = state.copyWith(selectionMode: false, selectedTagIds: const {});
  }

  Future<void> renameTag(String tagId, String name) {
    return ref.read(libraryIndexProvider.notifier).renameTag(tagId, name);
  }

  Future<void> editTag({
    required String tagId,
    String? name,
    Color? coverColor,
    String? coverImage,
  }) {
    return ref.read(libraryIndexProvider.notifier).updateTag(
          tagId,
          name: name,
          coverColor: coverColor,
          coverImage: coverImage,
        );
  }

  Future<void> deleteTag(String tagId) async {
    // 先将该标签从所有笔记中移除
    final index = ref.read(libraryIndexProvider).asData?.value;
    if (index != null) {
      final notesWithTag = index.notes
          .where((note) => !note.isDeleted && note.tagIds.contains(tagId))
          .map((note) => note.id)
          .toList();
      if (notesWithTag.isNotEmpty) {
        await ref
            .read(libraryIndexProvider.notifier)
            .removeTagFromNotes(notesWithTag, tagId);
      }
    }
    return ref.read(libraryIndexProvider.notifier).deleteTag(tagId);
  }

  Future<void> deleteSelectedTags() async {
    for (final id in state.selectedTagIds) {
      await deleteTag(id);
    }
    clearSelection();
  }
}

final tagsViewModelProvider = NotifierProvider<TagsViewModel, TagsState>(
  TagsViewModel.new,
);
