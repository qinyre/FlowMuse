import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/invitation_models.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/invitation_view_model.dart';
import '../view_models/social_view_model.dart';
import 'invitation_actions.dart';

String invitationStatus(SocialInvitation i) => switch (i.status) {
  'pending' => '等待接受',
  'accepted' => i.joinedAt > 0 ? '已加入过白板' : '已接受，尚未加入',
  'declined' => '已拒绝',
  'revoked' => '已撤销',
  'expired' => '已过期',
  'room_ended' => '房间已结束',
  _ => '邀请不可用',
};

class InvitationCard extends ConsumerStatefulWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    required this.peer,
    required this.canInteract,
  });
  final SocialInvitation invitation;
  final SocialPerson peer;
  final bool canInteract;
  @override
  ConsumerState<InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends ConsumerState<InvitationCard> {
  bool _busy = false;
  String? _error;
  Future<void> _action(SocialInvitation invite, String action) async {
    final repo = ref.read(socialRepositoryProvider);
    if (_busy || repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.invitationAction(invite, action);
      if (mounted && ref.read(socialRepositoryProvider) == repo) {
        ref.invalidate(socialInvitationProvider(invite.id));
        ref.read(socialViewModelProvider.notifier).refresh();
      }
    } catch (e) {
      if (mounted && ref.read(socialRepositoryProvider) == repo) {
        if (e is SocialException) {
          ref.read(socialViewModelProvider.notifier).handleSessionFailure(e);
        }
        setState(() => _error = e is SocialException ? e.message : '操作失败，请重试');
        ref.invalidate(socialInvitationProvider(invite.id));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fresh = ref.watch(socialInvitationProvider(widget.invitation.id));
    final invite = fresh.asData?.value ?? widget.invitation;
    final mine = invite.senderId == ref.watch(socialSessionProvider)?.userId;
    final expired = invite.expiresAt <= DateTime.now().millisecondsSinceEpoch;
    final available =
        !_busy &&
        widget.canInteract &&
        !fresh.hasError &&
        fresh.hasValue &&
        invite.canAccept &&
        !expired;
    final host = InvitationActions.of(context);
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(
      invite.expiresAt,
    ).toLocal();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.draw_outlined, size: 22),
                SizedBox(width: 10),
                Expanded(child: Text('一起协作白板')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              expired && invite.canAccept ? '已过期' : invitationStatus(invite),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '有效至 ${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (fresh.hasError) const Text('状态暂时无法更新，请刷新后再操作'),
            if (_error != null)
              Text(_error!, style: TextStyle(color: colors.error)),
            Wrap(
              spacing: 8,
              children: [
                if (mine) ...[
                  TextButton(
                    onPressed: available
                        ? () => _action(invite, 'revoke')
                        : null,
                    child: const Text('撤销'),
                  ),
                  TextButton(
                    onPressed: available && host != null
                        ? () => host.send(widget.peer, invite)
                        : null,
                    child: const Text('补发新设备'),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: available
                        ? () => _action(invite, 'decline')
                        : null,
                    child: const Text('拒绝'),
                  ),
                  FilledButton.tonal(
                    onPressed: available && host != null
                        ? () => host.open(invite.id)
                        : null,
                    child: const Text('查看并加入'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
