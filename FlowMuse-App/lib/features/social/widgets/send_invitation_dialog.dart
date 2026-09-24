import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invitation_models.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/invitation_view_model.dart';
import '../view_models/social_view_model.dart';

class SendInvitationDialog extends ConsumerStatefulWidget {
  const SendInvitationDialog({
    super.key,
    required this.peer,
    required this.roomId,
    required this.roomKey,
    required this.stillCurrent,
    this.supplement,
  });
  final SocialPerson peer;
  final String roomId, roomKey;
  final bool Function() stillCurrent;
  final SocialInvitation? supplement;
  @override
  ConsumerState<SendInvitationDialog> createState() =>
      _SendInvitationDialogState();
}

class _SendInvitationDialogState extends ConsumerState<SendInvitationDialog> {
  List<SocialDevice> _devices = [];
  SocialDevice? _target;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _run(Future<void> Function(InvitationController) action) async {
    if (_busy || !mounted) return;
    final controller = ref.read(invitationControllerProvider);
    if (controller == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(controller);
    } catch (e) {
      if (mounted && ref.read(invitationControllerProvider) == controller) {
        if (e is SocialException) {
          ref.read(socialViewModelProvider.notifier).handleSessionFailure(e);
        }
        setState(
          () => _error = e is SocialException ? e.message : '邀请发送失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run((controller) async {
    final set = await controller.repo.devices(friendId: widget.peer.id);
    final available = await controller.trusted(
      set.devices,
      requireVerification: false,
    );
    if (!mounted || ref.read(invitationControllerProvider) != controller) {
      return;
    }
    setState(() {
      _devices = available;
      _target = available.firstOrNull;
    });
  });

  Future<void> _send() => _run((controller) async {
    await controller.send(
      roomId: widget.roomId,
      roomKey: widget.roomKey,
      recipientId: widget.peer.id,
      stillCurrent: () => mounted && widget.stillCurrent(),
      supplement: widget.supplement,
      target: widget.supplement == null ? null : _target,
    );
    if (!mounted || ref.read(invitationControllerProvider) != controller) {
      return;
    }
    ref.read(socialViewModelProvider.notifier).refresh();
    Navigator.pop(context);
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(invitationControllerProvider, (before, after) {
      if (before != after && mounted) Navigator.pop(context);
    });
    final supplement = widget.supplement != null;
    return AlertDialog(
      title: Text(supplement ? '向新设备补发' : '邀请 ${widget.peer.name} 协作'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                supplement
                    ? '选择好友当前使用的设备重新发送，邀请有效期保持不变。'
                    : '好友接受后可共同编辑当前白板。邀请有效期为 1 小时，房间结束后立即失效。',
              ),
              const SizedBox(height: 16),
              if (!_busy && _devices.isEmpty) ...[
                const Text('好友暂时无法接收邀请，请让对方打开应用后重试，也可直接分享协作码。'),
                TextButton(onPressed: _load, child: const Text('刷新')),
              ],
              if (supplement && _devices.isNotEmpty)
                DropdownButton<SocialDevice>(
                  isExpanded: true,
                  value: _target,
                  items: _devices
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.label, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _busy ? null : (d) => setState(() => _target = d),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy || _devices.isEmpty ? null : _send,
          child: Text(supplement ? '补发邀请' : '发送邀请'),
        ),
      ],
    );
  }
}
