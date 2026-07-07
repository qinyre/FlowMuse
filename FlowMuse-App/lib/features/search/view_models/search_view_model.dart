import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SearchState {
  const SearchState({this.query = '', this.folderScopeId, this.tagScopeId});

  final String query;
  final String? folderScopeId;
  final String? tagScopeId;

  SearchState copyWith({
    String? query,
    String? folderScopeId,
    String? tagScopeId,
    bool clearFolderScope = false,
    bool clearTagScope = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      folderScopeId: clearFolderScope
          ? null
          : folderScopeId ?? this.folderScopeId,
      tagScopeId: clearTagScope ? null : tagScopeId ?? this.tagScopeId,
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

  void selectFolderScope(String? folderScopeId) {
    state = state.copyWith(
      folderScopeId: folderScopeId,
      clearFolderScope: folderScopeId == null,
    );
  }

  void selectTagScope(String? tagScopeId) {
    state = state.copyWith(
      tagScopeId: tagScopeId,
      clearTagScope: tagScopeId == null,
    );
  }
}

final searchViewModelProvider = NotifierProvider<SearchViewModel, SearchState>(
  SearchViewModel.new,
);
