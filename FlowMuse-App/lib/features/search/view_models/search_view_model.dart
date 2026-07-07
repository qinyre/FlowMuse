import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SearchState {
  const SearchState({
    this.query = '',
    this.folderScope = '尚未选择文件夹',
    this.tagScope = '尚未选择标签',
  });

  final String query;
  final String folderScope;
  final String tagScope;

  SearchState copyWith({String? query, String? folderScope, String? tagScope}) {
    return SearchState(
      query: query ?? this.query,
      folderScope: folderScope ?? this.folderScope,
      tagScope: tagScope ?? this.tagScope,
    );
  }
}

class SearchViewModel extends Notifier<SearchState> {
  @override
  SearchState build() {
    return const SearchState();
  }

  void changeQuery(String query) {
    state = state.copyWith(query: query);
  }

  void selectFolderScope(String folderScope) {
    state = state.copyWith(folderScope: folderScope);
  }

  void selectTagScope(String tagScope) {
    state = state.copyWith(tagScope: tagScope);
  }
}

final searchViewModelProvider = NotifierProvider<SearchViewModel, SearchState>(
  SearchViewModel.new,
);
