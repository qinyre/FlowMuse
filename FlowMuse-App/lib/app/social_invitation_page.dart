import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/social/repositories/social_repository.dart';
import '../features/social/view_models/invitation_view_model.dart';
import '../features/social/view_models/social_view_model.dart';
import '../features/social/widgets/device_security_dialog.dart';
import '../features/social/widgets/invitation_card.dart';
import '../features/whiteboard/collaboration/models/collaboration_room.dart';
import '../features/whiteboard/views/whiteboard_page.dart';
import 'app_router.dart';

/// This route carries only an invitation ID. The decrypted key exists solely in
/// this session's widget memory and is handed to the existing join flow.
class SocialInvitationPage extends ConsumerWidget {
  const SocialInvitationPage({super.key, required this.inviteId});
  final String inviteId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => _InvitationSession(
    key: ValueKey(ref.watch(invitationControllerProvider)),
    inviteId: inviteId,
  );
}

class _InvitationSession extends ConsumerStatefulWidget {
  const _InvitationSession({super.key, required this.inviteId});
  final String inviteId;
  @override
  ConsumerState<_InvitationSession> createState() => _InvitationSessionState();
}

class _InvitationSessionState extends ConsumerState<_InvitationSession> {
  CollaborationRoom? _room;
  InvitationController? _roomController;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    final controller = ref.read(invitationControllerProvider);
    if (_busy || controller == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accepted = await controller.accept(widget.inviteId);
      if (!mounted || ref.read(invitationControllerProvider) != controller) {
        return;
      }
      setState(() {
        _roomController = controller;
        _room = CollaborationRoom(
          roomId: accepted.invitation.roomId,
          roomKey: accepted.roomKey,
        );
      });
    } catch (e) {
      if (mounted && ref.read(invitationControllerProvider) == controller) {
        if (e is SocialException) {
          ref.read(socialViewModelProvider.notifier).handleSessionFailure(e);
        }
        setState(
          () => _error = e is SocialException ? e.message : '邀请无法打开，请刷新后重试',
        );
        ref.invalidate(socialInvitationProvider(widget.inviteId));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joined() async {
    final controller = ref.read(invitationControllerProvider);
    if (controller == null || controller != _roomController || _room == null) {
      return;
    }
    try {
      await controller.repo.invitationJoined(widget.inviteId);
      if (mounted && ref.read(invitationControllerProvider) == controller) {
        ref.invalidate(socialInvitationProvider(widget.inviteId));
        ref.read(socialViewModelProvider.notifier).refresh();
      }
    } catch (_) {
      if (mounted && ref.read(invitationControllerProvider) == controller) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('白板已加入，邀请状态暂未同步'),
            action: SnackBarAction(label: '重试同步', onPressed: _joined),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_room != null) {
      return WhiteboardPage.collaborationRoom(
        initialRoom: _room!,
        onInitialRoomJoined: _joined,
      );
    }
    final controller = ref.watch(invitationControllerProvider);
    final inbox = ref.watch(socialViewModelProvider);
    final invitation = controller == null
        ? null
        : ref.watch(socialInvitationProvider(widget.inviteId));
    final i = invitation?.asData?.value;
    final peer = inbox.friends
        .where((f) => f.person.id == i?.senderId)
        .firstOrNull
        ?.person;
    final canJoin =
        i != null &&
        i.recipientId == controller?.devices.userId &&
        i.canAccept &&
        i.expiresAt > DateTime.now().millisecondsSinceEpoch;
    return Scaffold(
      appBar: AppBar(
        title: const Text('协作邀请'),
        leading: IconButton(
          tooltip: '返回好友与消息',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.social),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.draw_outlined, size: 48),
                const SizedBox(height: 24),
                if (controller == null) ...[
                  const Text('登录接收邀请的账号后继续。'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.push(AppRoutes.accountSettings),
                    child: const Text('登录后继续'),
                  ),
                ] else if (invitation!.isLoading && i == null)
                  const LinearProgressIndicator()
                else if (i == null) ...[
                  const Text('未找到可查看的邀请，请确认账号或稍后重试。'),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      socialInvitationProvider(widget.inviteId),
                    ),
                    child: const Text('重新加载'),
                  ),
                ] else ...[
                  Text(
                    peer == null ? '好友邀请你共同编辑白板' : '${peer.name} 邀请你共同编辑白板',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(invitationStatus(i)),
                  const SizedBox(height: 12),
                  const Text('加入后将打开一个临时协作白板，退出时可另存到本地。'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: canJoin && !_busy ? _accept : null,
                    child: Text(_busy ? '正在安全打开…' : '接受并加入白板'),
                  ),
                  if (peer != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => showDeviceSecurity(context, peer: peer),
                      child: const Text('核验邀请发送者设备'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : () => showDeviceSecurity(context),
                    child: const Text('我的设备安全'),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
