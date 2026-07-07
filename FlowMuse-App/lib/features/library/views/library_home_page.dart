import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../whiteboard/collaboration/models/collaboration_room.dart';
import '../models/note_item.dart';
import '../view_models/library_home_view_model.dart';
import '../widgets/library_content.dart';

class LibraryHomePage extends ConsumerWidget {
  const LibraryHomePage({super.key});

  void _openWhiteboard(BuildContext context, {required String noteId}) {
    context.push(AppRoutes.whiteboardPath(noteId: noteId));
  }

  Future<void> _joinRoom(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final room = await showDialog<CollaborationRoom>(
        context: context,
        builder: (context) => _JoinRoomDialog(controller: controller),
      );
      if (room == null || !context.mounted) {
        return;
      }
      context.push(
        '${AppRoutes.collaborationWhiteboard}#room=${room.toRoomValue()}',
        extra: room,
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryHomeViewModelProvider);
    final viewModel = ref.read(libraryHomeViewModelProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return LibraryContent(
          compact: compact,
          state: state,
          onFilterChanged: viewModel.selectFilter,
          onViewModeChanged: viewModel.changeViewMode,
          onSortDirectionChanged: viewModel.toggleSortDirection,
          onSelectionModeChanged: viewModel.toggleSelectionMode,
          onCreate: () async {
            final note = await viewModel.createNote();
            if (context.mounted) {
              _openWhiteboard(context, noteId: note.id);
            }
          },
          onJoinRoom: () {
            _joinRoom(context);
          },
          onOpenNote: (NoteItem item) {
            _openWhiteboard(context, noteId: item.id);
          },
        );
      },
    );
  }
}

class _JoinRoomDialog extends StatefulWidget {
  const _JoinRoomDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  String? _error;

  void _submit() {
    final room = _parseRoomInput(widget.controller.text);
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
        controller: widget.controller,
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
