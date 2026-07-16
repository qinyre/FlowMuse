import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../whiteboard/collaboration/models/collaboration_room.dart';
import '../../whiteboard/collaboration/widgets/join_room_dialog.dart';
import '../models/library_special_view.dart';
import '../models/note_item.dart';
import '../repositories/library_repository.dart';
import '../view_models/library_home_view_model.dart';
import '../widgets/library_content.dart';

class LibraryHomePage extends ConsumerWidget {
  const LibraryHomePage({
    super.key,
    this.specialView = LibrarySpecialView.none,
  });

  final LibrarySpecialView specialView;

  void _openWhiteboard(BuildContext context, {required String noteId}) {
    context.push(
      AppRoutes.whiteboardPath(noteId: noteId, discardIfUnchanged: false),
    );
  }

  Future<void> _joinRoom(BuildContext context) async {
    final room = await showDialog<CollaborationRoom>(
      context: context,
      builder: (context) => const JoinRoomDialog(),
    );
    if (room == null || !context.mounted) {
      return;
    }
    runAfterContextTeardown(context, () {
      context.push(
        '${AppRoutes.collaborationWhiteboard}#room=${room.toRoomValue()}',
        extra: room,
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryHomeViewModelProvider);
    final viewModel = ref.read(libraryHomeViewModelProvider.notifier);
    final libraryIndex =
        ref.watch(libraryIndexProvider).asData?.value ?? const LibraryIndex();
    final notes = _notesForSpecialView(specialView, state, libraryIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return LibraryContent(
          compact: compact,
          state: state,
          title: _titleForSpecialView(specialView),
          notes: notes,
          libraryIndex: libraryIndex,
          specialView: specialView,
          onFilterChanged: viewModel.selectFilter,
          onViewModeChanged: viewModel.changeViewMode,
          onSortDirectionChanged: viewModel.toggleSortDirection,
          onSelectionModeChanged: viewModel.toggleSelectionMode,
          onSelectionChanged: viewModel.toggleNoteSelection,
          onClearSelection: viewModel.clearSelection,
          onDeleteSelected: viewModel.deleteSelectedNotes,
          onRestoreSelected: viewModel.restoreSelectedNotes,
          onRestoreNote: (noteId) =>
              ref.read(libraryIndexProvider.notifier).restoreNotes([noteId]),
          onDeleteNoteForever: (noteId) => ref
              .read(libraryIndexProvider.notifier)
              .deleteNotesForever([noteId]),
          onDeleteSelectedForever: viewModel.deleteSelectedNotesForever,
          onMoveSelectedToNotebook: viewModel.moveSelectedNotesToNotebook,
          onAddTagsToSelected: viewModel.addTagsToSelectedNotes,
          onCreate: () {
            context.push(AppRoutes.createNote);
          },
          onJoinRoom: () {
            _joinRoom(context);
          },
          onOpenNote: specialView == LibrarySpecialView.trash
              ? (NoteItem item) => viewModel.toggleNoteSelection(item.id)
              : (NoteItem item) {
                  _openWhiteboard(context, noteId: item.id);
                },
          onRenameNote: (noteId, newName) => ref
              .read(libraryIndexProvider.notifier)
              .renameNote(noteId, newName),
          onMoveNoteToNotebook: (noteId, notebookId) => ref
              .read(libraryIndexProvider.notifier)
              .moveNotesToNotebook([noteId], notebookId),
          onSetNoteTags: (noteId, tagIds) => ref
              .read(libraryIndexProvider.notifier)
              .setNoteTags(noteId, tagIds),
          onDeleteNote: (noteId) =>
              ref.read(libraryIndexProvider.notifier).deleteNotes([noteId]),
        );
      },
    );
  }
}

String _titleForSpecialView(LibrarySpecialView specialView) {
  return switch (specialView) {
    LibrarySpecialView.none => '全部笔记',
    LibrarySpecialView.unnotebooked => '未归入笔记本',
    LibrarySpecialView.untagged => '未标签',
    LibrarySpecialView.trash => '回收站',
  };
}

List<NoteItem> _notesForSpecialView(
  LibrarySpecialView specialView,
  LibraryHomeState state,
  LibraryIndex libraryIndex,
) {
  final source = switch (specialView) {
    LibrarySpecialView.none => state.visibleNotes,
    LibrarySpecialView.unnotebooked => libraryIndex.notesForQuery(
      const LibraryQuery(onlyUnnotebooked: true),
    ),
    LibrarySpecialView.untagged => libraryIndex.notesForQuery(
      const LibraryQuery(onlyUntagged: true),
    ),
    LibrarySpecialView.trash => libraryIndex.notesForQuery(
      const LibraryQuery(onlyDeleted: true),
    ),
  };
  return source.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
