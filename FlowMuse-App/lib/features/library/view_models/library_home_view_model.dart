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
    this.selectedNoteIds = const {},
    this.notes = const [],
    this.loading = false,
  });

  final LibraryFilter selectedFilter;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final Set<String> selectedNoteIds;
  final List<NoteItem> notes;
  final bool loading;

  List<NoteItem> get visibleNotes {
    final activeNotes = notes.where((item) => !item.isDeleted);
    final filtered = selectedFilter == LibraryFilter.all
        ? activeNotes
        : activeNotes.where((item) => item.kind == selectedFilter);
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
    Set<String>? selectedNoteIds,
    List<NoteItem>? notes,
    bool? loading,
  }) {
    return LibraryHomeState(
      selectedFilter: selectedFilter ?? this.selectedFilter,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedNoteIds: selectedNoteIds ?? this.selectedNoteIds,
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
    state = state.copyWith(
      selectionMode: !state.selectionMode,
      selectedNoteIds: const {},
    );
  }

  void toggleNoteSelection(String noteId) {
    final selected = Set<String>.from(state.selectedNoteIds);
    selected.contains(noteId) ? selected.remove(noteId) : selected.add(noteId);
    state = state.copyWith(selectedNoteIds: selected);
  }

  void clearSelection() {
    state = state.copyWith(selectionMode: false, selectedNoteIds: const {});
  }

  Future<NoteItem> createNote() {
    return ref.read(libraryIndexProvider.notifier).createNote();
  }

  Future<void> deleteSelectedNotes() async {
    await ref
        .read(libraryIndexProvider.notifier)
        .deleteNotes(state.selectedNoteIds.toList());
    clearSelection();
  }

  Future<void> restoreSelectedNotes() async {
    await ref
        .read(libraryIndexProvider.notifier)
        .restoreNotes(state.selectedNoteIds.toList());
    clearSelection();
  }

  Future<void> deleteSelectedNotesForever() async {
    await ref
        .read(libraryIndexProvider.notifier)
        .deleteNotesForever(state.selectedNoteIds.toList());
    clearSelection();
  }

  Future<void> moveSelectedNotesToNotebook(String? notebookId) async {
    await ref
        .read(libraryIndexProvider.notifier)
        .moveNotesToNotebook(state.selectedNoteIds.toList(), notebookId);
    clearSelection();
  }

  Future<void> addTagsToSelectedNotes(List<String> tagIds) async {
    await ref
        .read(libraryIndexProvider.notifier)
        .addTagsToNotes(state.selectedNoteIds.toList(), tagIds);
    clearSelection();
  }
}

final libraryHomeViewModelProvider =
    NotifierProvider<LibraryHomeViewModel, LibraryHomeState>(
      LibraryHomeViewModel.new,
    );
