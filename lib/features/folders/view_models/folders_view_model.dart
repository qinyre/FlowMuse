import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/notebook_item.dart';

@immutable
class FolderItem {
  const FolderItem({
    required this.id,
    required this.name,
    required this.count,
    required this.coverColor,
    this.notebookIds = const [],
  });

  final String id;
  final String name;
  final int count;
  final Color coverColor;
  final List<String> notebookIds;
}

@immutable
class FoldersState {
  const FoldersState({
    this.folders = const [],
    this.viewMode = LibraryViewMode.grid,
    this.sortAscending = true,
    this.selectionMode = false,
  });

  final List<FolderItem> folders;
  final LibraryViewMode viewMode;
  final bool sortAscending;
  final bool selectionMode;

  List<FolderItem> get visibleFolders {
    final sorted = folders.toList()
      ..sort((a, b) {
        final result = a.name.compareTo(b.name);
        return sortAscending ? result : -result;
      });
    return sorted;
  }

  FoldersState copyWith({
    List<FolderItem>? folders,
    LibraryViewMode? viewMode,
    bool? sortAscending,
    bool? selectionMode,
  }) {
    return FoldersState(
      folders: folders ?? this.folders,
      viewMode: viewMode ?? this.viewMode,
      sortAscending: sortAscending ?? this.sortAscending,
      selectionMode: selectionMode ?? this.selectionMode,
    );
  }
}

class FoldersViewModel extends Notifier<FoldersState> {
  @override
  FoldersState build() {
    return const FoldersState();
  }

  void createFolder() {
    final nextIndex = state.folders.length + 1;
    state = state.copyWith(
      folders: [
        ...state.folders,
        FolderItem(
          id: 'folder-$nextIndex',
          name: '新建文件夹 $nextIndex',
          count: 0,
          coverColor: _folderColors[(nextIndex - 1) % _folderColors.length],
        ),
      ],
    );
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

final foldersViewModelProvider =
    NotifierProvider<FoldersViewModel, FoldersState>(FoldersViewModel.new);

const _folderColors = [
  Color(0xFF8DB6C9),
  Color(0xFFD9B48F),
  Color(0xFF8CBDB5),
  Color(0xFF9CA2E6),
];
