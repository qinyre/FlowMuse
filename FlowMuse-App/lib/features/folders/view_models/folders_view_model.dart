import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/notebook_item.dart';
import '../../library/repositories/library_repository.dart';

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
    final index = ref.watch(libraryIndexProvider).asData?.value;
    final folders = index == null
        ? const <FolderItem>[]
        : [
            for (final folder in index.folders)
              FolderItem(
                id: folder.id,
                name: folder.name,
                count: index.notebooks
                    .where((item) => item.folderId == folder.id)
                    .length,
                coverColor: folder.coverColor,
                notebookIds: [
                  for (final notebook in index.notebooks)
                    if (notebook.folderId == folder.id) notebook.id,
                ],
              ),
          ];
    return FoldersState(folders: folders);
  }

  Future<void> createFolder() {
    return ref.read(libraryIndexProvider.notifier).createFolder();
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
