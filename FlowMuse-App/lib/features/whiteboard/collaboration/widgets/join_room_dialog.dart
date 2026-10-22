import 'package:flutter/material.dart';
import 'package:flow_muse/shared/widgets/app_spacing.dart';

import '../models/collaboration_room.dart';
import '../services/room_qr_scanner.dart';

class JoinRoomDialog extends StatefulWidget {
  const JoinRoomDialog({super.key, this.scanner});

  final Future<CollaborationRoom?> Function(BuildContext)? scanner;

  @override
  State<JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<JoinRoomDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _scanning = false;

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

  Future<void> _scan() async {
    if (_scanning) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final room = await (widget.scanner ?? scanRoomQr)(context);
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (room != null) Navigator.of(context).pop(room);
    } catch (_) {
      if (mounted) setState(() => _error = '扫码暂不可用，请重试或粘贴房间链接。');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('加入协作房间'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.scanner != null || canScanRoomQr) ...[
            FilledButton.tonalIcon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_scanning ? '正在扫码…' : '扫码加入房间'),
            ),
            const SizedBox(height: AppSpacing.controlGap * 2),
            const Text('也可以粘贴房间链接'),
            const SizedBox(height: AppSpacing.controlGap),
          ],
          TextField(
            controller: _controller,
            autofocus: !(widget.scanner != null || canScanRoomQr),
            enabled: !_scanning,
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _scanning ? null : _submit,
          child: const Text('加入'),
        ),
      ],
    );
  }
}
