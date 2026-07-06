import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notebook_item.dart';

@immutable
class LibraryHomeState {
  const LibraryHomeState({
    this.selectedFilter = LibraryFilter.all,
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = false,
    this.selectionMode = false,
    this.notebooks = sampleNotebooks,
  });

  final LibraryFilter selectedFilter;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;
  final List<NotebookItem> notebooks;

  List<NotebookItem> get visibleNotebooks {
    final filtered = selectedFilter == LibraryFilter.all
        ? notebooks
        : notebooks.where((item) => item.kind == selectedFilter);
    final sorted = filtered.toList()
      ..sort((a, b) {
        final result = a.date.compareTo(b.date);
        return sortAscending ? result : -result;
      });
    return sorted;
  }

  LibraryHomeState copyWith({
    LibraryFilter? selectedFilter,
    LibraryViewMode? viewMode,
    bool? sortAscending,
    bool? selectionMode,
  }) {
    return LibraryHomeState(
      selectedFilter: selectedFilter ?? this.selectedFilter,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
      notebooks: notebooks,
    );
  }
}

class LibraryHomeViewModel extends Notifier<LibraryHomeState> {
  @override
  LibraryHomeState build() {
    return const LibraryHomeState();
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
}

final libraryHomeViewModelProvider =
    NotifierProvider<LibraryHomeViewModel, LibraryHomeState>(
      LibraryHomeViewModel.new,
    );

const sampleNotebooks = [
  NotebookItem(
    id: 'whiteboard-os',
    title: '操作系统',
    date: '2026/06/26',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF8DB6C9),
    subtitle: '操作系统概念',
  ),
  NotebookItem(
    id: 'whiteboard-lecture-notes',
    title: 'LectureNotes',
    date: '2026/05/28',
    kind: LibraryFilter.pdf,
    coverColor: Color(0xFFD9B48F),
  ),
  NotebookItem(
    id: 'whiteboard-quantum-computing',
    title: '量子计算',
    date: '2026/05/16',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF2E5872),
  ),
  NotebookItem(
    id: 'whiteboard-novel',
    title: '小说',
    date: '2026/04/23',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF8CBDB5),
  ),
  NotebookItem(
    id: 'whiteboard-drafts',
    title: '草稿本',
    date: '2026/04/03',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFD6D6D0),
  ),
  NotebookItem(
    id: 'whiteboard-software-engineering',
    title: '软件工程',
    date: '2026/03/05',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFE9993F),
  ),
  NotebookItem(
    id: 'whiteboard-untitled-note',
    title: '未命名笔记',
    date: '2026/03/04',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFE6E4DD),
  ),
  NotebookItem(
    id: 'whiteboard-algorithm-yudandan',
    title: '算法设计 喻丹丹',
    date: '2026/03/02',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF9CA2E6),
  ),
];
