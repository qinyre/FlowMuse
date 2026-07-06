import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/notebook_item.dart';

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
    return const TagsState();
  }

  void createTag() {
    final nextIndex = state.tags.length + 1;
    state = state.copyWith(
      tags: [
        ...state.tags,
        TagItem(
          id: 'tag-$nextIndex',
          name: '新建标签 $nextIndex',
          count: 0,
          coverColor: _tagColors[(nextIndex - 1) % _tagColors.length],
        ),
      ],
    );
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

const _tagColors = [
  Color(0xFF8CBDB5),
  Color(0xFFE9993F),
  Color(0xFF9CA2E6),
  Color(0xFF2E5872),
];
