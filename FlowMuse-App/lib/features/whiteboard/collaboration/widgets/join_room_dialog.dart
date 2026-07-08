import 'package:flutter/material.dart';

import '../models/collaboration_room.dart';

class JoinRoomDialog extends StatefulWidget {
  const JoinRoomDialog({super.key});

  @override
  State<JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<JoinRoomDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final room = CollaborationRoom.parse(_controller.text).room;
    if (room == null) {
      setState(() => _error = '请输入完整房间链接、#room=房间号,密钥 或 房间号,密钥');
      return;
    }
    Navigator.of(context).pop(room);
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
          hintText: '粘贴链接、#room=... 或 roomId,roomKey',
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
