import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class TagItem {
  const TagItem({required this.name, required this.count});

  final String name;
  final int count;
}

@immutable
class TagsState {
  const TagsState({this.tags = const []});

  final List<TagItem> tags;

  TagsState copyWith({List<TagItem>? tags}) {
    return TagsState(tags: tags ?? this.tags);
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
        TagItem(name: '新建标签 $nextIndex', count: 0),
      ],
    );
  }
}

final tagsViewModelProvider = NotifierProvider<TagsViewModel, TagsState>(
  TagsViewModel.new,
);
