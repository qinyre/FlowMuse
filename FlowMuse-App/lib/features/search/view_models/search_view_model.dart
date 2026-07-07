import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class SearchState {
  const SearchState({this.query = '', this.notebookScopeId, this.tagScopeId});

  final String query;
  final String? notebookScopeId;
  final String? tagScopeId;

  SearchState copyWith({
    String? query,
    String? notebookScopeId,
    String? tagScopeId,
    bool clearNotebookScope = false,
    bool clearTagScope = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      notebookScopeId: clearNotebookScope
          ? null
          : notebookScopeId ?? this.notebookScopeId,
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

  void selectNotebookScope(String? notebookScopeId) {
    state = state.copyWith(
      notebookScopeId: notebookScopeId,
      clearNotebookScope: notebookScopeId == null,
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
