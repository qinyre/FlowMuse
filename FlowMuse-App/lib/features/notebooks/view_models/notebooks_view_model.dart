import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';

@immutable
class NotebookCollectionItem {
  const NotebookCollectionItem({
    required this.id,
    required this.name,
    required this.count,
    required this.coverColor,
    this.noteIds = const [],
  });

  final String id;
  final String name;
  final int count;
  final Color coverColor;
  final List<String> noteIds;
}

@immutable
class NotebooksState {
  const NotebooksState({
    this.notebooks = const [],
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = true,
    this.selectionMode = false,
    this.selectedNotebookIds = const {},
  });

  final List<NotebookCollectionItem> notebooks;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final Set<String> selectedNotebookIds;

  List<NotebookCollectionItem> get visibleNotebooks {
    final sorted = notebooks.toList()
      ..sort((a, b) {
        final result = a.name.compareTo(b.name);
        return sortAscending ? result : -result;
      });
    return sorted;
  }

  NotebooksState copyWith({
    List<NotebookCollectionItem>? notebooks,
    LibraryViewMode? viewMode,
    bool? sortAscending,
    bool? selectionMode,
    Set<String>? selectedNotebookIds,
  }) {
    return NotebooksState(
      notebooks: notebooks ?? this.notebooks,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      selectedNotebookIds: selectedNotebookIds ?? this.selectedNotebookIds,
    );
  }
}

class NotebooksViewModel extends Notifier<NotebooksState> {
  @override
  NotebooksState build() {
    final index = ref.watch(libraryIndexProvider).asData?.value;
    final notebooks = index == null
        ? const <NotebookCollectionItem>[]
        : [
            for (final notebook in index.notebooks)
              NotebookCollectionItem(
                id: notebook.id,
                name: notebook.name,
                count: index.notes
                    .where((item) => item.notebookId == notebook.id)
                    .length,
                coverColor: notebook.coverColor,
                noteIds: [
                  for (final note in index.notes)
                    if (note.notebookId == notebook.id) note.id,
                ],
              ),
          ];
    return NotebooksState(notebooks: notebooks);
  }

  Future<void> createNotebook({String? name, Color? coverColor}) {
    return ref
        .read(libraryIndexProvider.notifier)
        .createNotebook(name: name, coverColor: coverColor);
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
      selectedNotebookIds: const {},
    );
  }

  void toggleNotebookSelection(String notebookId) {
    final selected = Set<String>.from(state.selectedNotebookIds);
    selected.contains(notebookId)
        ? selected.remove(notebookId)
        : selected.add(notebookId);
    state = state.copyWith(selectedNotebookIds: selected);
  }

  void clearSelection() {
    state = state.copyWith(selectionMode: false, selectedNotebookIds: const {});
  }

  Future<void> renameNotebook(String notebookId, String name) {
    return ref.read(libraryIndexProvider.notifier).renameNotebook(notebookId, name);
  }

  Future<void> deleteNotebook(String notebookId) {
    return ref.read(libraryIndexProvider.notifier).deleteNotebook(notebookId);
  }

  Future<void> deleteSelectedNotebooks() async {
    for (final id in state.selectedNotebookIds) {
      await ref.read(libraryIndexProvider.notifier).deleteNotebook(id);
    }
    clearSelection();
  }
}

final notebooksViewModelProvider =
    NotifierProvider<NotebooksViewModel, NotebooksState>(
      NotebooksViewModel.new,
    );
