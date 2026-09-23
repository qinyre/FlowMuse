import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/social/models/invitation_models.dart';
import '../features/social/models/social_models.dart';
import '../features/social/view_models/invitation_view_model.dart';
import '../features/social/widgets/invitation_actions.dart';
import '../features/social/widgets/send_invitation_dialog.dart';
import '../features/whiteboard/view_models/whiteboard_view_model.dart';
import 'app_router.dart';

/// The application boundary owns access to the live whiteboard and navigation.
class SocialInvitationHost extends ConsumerWidget {
  const SocialInvitationHost({super.key, required this.child, this.onOpen});
  final Widget child;
  final Future<void> Function(String id)? onOpen;

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    SocialPerson peer,
    SocialInvitation? supplement,
  ) async {
    final board = ref.read(whiteboardViewModelProvider);
    final room = board.activeRoom;
    final controller = ref.read(invitationControllerProvider);
    if (controller == null ||
        room == null ||
        !board.collaborating ||
        !board.isRoomOwner ||
        board.roomEnded ||
        (supplement != null && supplement.roomId != room.roomId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在自己创建的协作白板中打开好友消息，再发送或补发邀请')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => SendInvitationDialog(
        peer: peer,
        roomId: room.roomId,
        roomKey: room.roomKey,
        supplement: supplement,
        stillCurrent: () {
          if (!context.mounted ||
              ref.read(invitationControllerProvider) != controller) {
            return false;
          }
          final current = ref.read(whiteboardViewModelProvider);
          return identical(current.activeRoom, room) &&
              current.collaborating &&
              current.isRoomOwner &&
              !current.roomEnded;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => InvitationActions(
    open:
        onOpen ??
        (id) async {
          await context.push(AppRoutes.socialInvitationPath(id));
        },
    send: (peer, supplement) => _send(context, ref, peer, supplement),
    child: child,
  );
}
