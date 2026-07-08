import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../shared/utils/ui_lifecycle.dart';
import '../../whiteboard/collaboration/models/collaboration_room.dart';
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
    context.push(AppRoutes.whiteboardPath(noteId: noteId));
  }

  Future<void> _joinRoom(BuildContext context) async {
    final room = await showDialog<CollaborationRoom>(
      context: context,
      builder: (context) => const _JoinRoomDialog(),
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
          onDeleteSelectedForever: viewModel.deleteSelectedNotesForever,
          onMoveSelectedToNotebook: viewModel.moveSelectedNotesToNotebook,
          onAddTagsToSelected: viewModel.addTagsToSelectedNotes,
          onCreate: () async {
            final note = await viewModel.createNote();
            if (context.mounted) {
              _openWhiteboard(context, noteId: note.id);
            }
          },
          onJoinRoom: () {
            _joinRoom(context);
          },
          onOpenNote: specialView == LibrarySpecialView.trash
              ? (NoteItem item) => viewModel.toggleNoteSelection(item.id)
              : (NoteItem item) {
                  _openWhiteboard(context, noteId: item.id);
                },
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
    LibrarySpecialView.unnotebooked =>
      libraryIndex.activeNotes
          .where((item) => item.notebookId == null)
          .toList(),
    LibrarySpecialView.untagged =>
      libraryIndex.activeNotes.where((item) => item.tagIds.isEmpty).toList(),
    LibrarySpecialView.trash => libraryIndex.deletedNotes,
  };
  return source.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

class _JoinRoomDialog extends StatefulWidget {
  const _JoinRoomDialog();

  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final room = _parseRoomInput(_controller.text);
    if (room == null) {
      setState(() => _error = '请输入完整房间链接或 roomId,roomKey');
      return;
    }
    Navigator.of(context).pop(room);
  }

  CollaborationRoom? _parseRoomInput(String value) {
    return CollaborationRoom.parse(value).room;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('加入协作房间'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '房间链接',
          hintText: '粘贴链接或 roomId,roomKey',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('加入')),
      ],
    );
  }
}
