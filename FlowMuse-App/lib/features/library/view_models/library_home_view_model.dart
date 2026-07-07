import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note_item.dart';
import '../repositories/library_repository.dart';

@immutable
class LibraryHomeState {
  const LibraryHomeState({
    this.selectedFilter = LibraryFilter.all,
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = false,
    this.selectionMode = false,
    this.notes = const [],
    this.loading = false,
  });

  final LibraryFilter selectedFilter;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final List<NoteItem> notes;
  final bool loading;

  List<NoteItem> get visibleNotes {
    final filtered = selectedFilter == LibraryFilter.all
        ? notes
        : notes.where((item) => item.kind == selectedFilter);
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
    List<NoteItem>? notes,
    bool? loading,
  }) {
    return LibraryHomeState(
      selectedFilter: selectedFilter ?? this.selectedFilter,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      notes: notes ?? this.notes,
      loading: loading ?? this.loading,
    );
  }
}

class LibraryHomeViewModel extends Notifier<LibraryHomeState> {
  @override
  LibraryHomeState build() {
    final libraryIndex = ref.watch(libraryIndexProvider);
    return LibraryHomeState(
      notes: libraryIndex.asData?.value.notes ?? const [],
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

  Future<NoteItem> createNote() {
    return ref.read(libraryIndexProvider.notifier).createNote();
  }
}

final libraryHomeViewModelProvider =
    NotifierProvider<LibraryHomeViewModel, LibraryHomeState>(
      LibraryHomeViewModel.new,
    );
