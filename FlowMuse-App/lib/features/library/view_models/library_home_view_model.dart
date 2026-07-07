import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notebook_item.dart';
import '../repositories/library_repository.dart';

@immutable
class LibraryHomeState {
  const LibraryHomeState({
    this.selectedFilter = LibraryFilter.all,
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = false,
    this.selectionMode = false,
    this.notebooks = const [],
    this.loading = false,
  });

  final LibraryFilter selectedFilter;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final List<NotebookItem> notebooks;
  final bool loading;

  List<NotebookItem> get visibleNotebooks {
    final filtered = selectedFilter == LibraryFilter.all
        ? notebooks
        : notebooks.where((item) => item.kind == selectedFilter);
    final sorted = filtered.toList()
      ..sort((a, b) {
        final result = a.updatedAt.compareTo(b.updatedAt);
        return sortAscending ? result : -result;
      });
    return sorted;
  }

  LibraryHomeState copyWith({
    LibraryFilter? selectedFilter,
    LibraryViewMode? viewMode,
    bool? sortAscending,
    bool? selectionMode,
    List<NotebookItem>? notebooks,
    bool? loading,
  }) {
    return LibraryHomeState(
      selectedFilter: selectedFilter ?? this.selectedFilter,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      notebooks: notebooks ?? this.notebooks,
      loading: loading ?? this.loading,
    );
  }
}

class LibraryHomeViewModel extends Notifier<LibraryHomeState> {
  @override
  LibraryHomeState build() {
    final libraryIndex = ref.watch(libraryIndexProvider);
    return LibraryHomeState(
      notebooks: libraryIndex.asData?.value.notebooks ?? const [],
      loading: libraryIndex.isLoading,
    );
  }

  void selectFilter(LibraryFilter filter) {
    if (state.selectedFilter == filter) {
      return;
    }
    state = state.copyWith(selectedFilter: filter);
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

  Future<NotebookItem> createNotebook() {
    return ref.read(libraryIndexProvider.notifier).createNotebook();
  }
}

final libraryHomeViewModelProvider =
    NotifierProvider<LibraryHomeViewModel, LibraryHomeState>(
      LibraryHomeViewModel.new,
    );
