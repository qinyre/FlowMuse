import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notebook_item.dart';

@immutable
class LibraryHomeState {
  const LibraryHomeState({
    this.selectedFilter = LibraryFilter.all,
    this.notebooks = sampleNotebooks,
  });

  final LibraryFilter selectedFilter;
  final List<NotebookItem> notebooks;

  List<NotebookItem> get visibleNotebooks {
    if (selectedFilter == LibraryFilter.all) {
      return notebooks;
    }
    return notebooks.where((item) => item.kind == selectedFilter).toList();
  }

  LibraryHomeState copyWith({LibraryFilter? selectedFilter}) {
    return LibraryHomeState(
      selectedFilter: selectedFilter ?? this.selectedFilter,
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
}

final libraryHomeViewModelProvider =
    NotifierProvider<LibraryHomeViewModel, LibraryHomeState>(
      LibraryHomeViewModel.new,
    );

const sampleNotebooks = [
  NotebookItem(
    title: '操作系统',
    date: '2026/06/26',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF8DB6C9),
    subtitle: '操作系统概念',
  ),
  NotebookItem(
    title: 'LectureNotes',
    date: '2026/05/28',
    kind: LibraryFilter.pdf,
    coverColor: Color(0xFFD9B48F),
  ),
  NotebookItem(
    title: '量子计算',
    date: '2026/05/16',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF2E5872),
  ),
  NotebookItem(
    title: '小说',
    date: '2026/04/23',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF8CBDB5),
  ),
  NotebookItem(
    title: '草稿本',
    date: '2026/04/03',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFD6D6D0),
  ),
  NotebookItem(
    title: '软件工程',
    date: '2026/03/05',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFE9993F),
  ),
  NotebookItem(
    title: '未命名笔记',
    date: '2026/03/04',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFFE6E4DD),
  ),
  NotebookItem(
    title: '算法设计 喻丹丹',
    date: '2026/03/02',
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF9CA2E6),
  ),
];
