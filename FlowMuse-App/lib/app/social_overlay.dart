import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/social/view_models/social_view_model.dart';
import '../features/social/views/social_page.dart';
import '../features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import '../shared/widgets/app_shell.dart';
import 'app_router.dart';
import 'social_invitation_host.dart';

/// Host-owned action: inbox updates rebuild this button, never the canvas.
class SocialMessagesAction extends ConsumerWidget {
  const SocialMessagesAction({super.key, this.prepareToOpenInvitation});
  final Future<bool> Function()? prepareToOpenInvitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, count) = ref.watch(
      socialViewModelProvider.select((s) => (s.status, s.badgeCount)),
    );
    if (status == SocialStatus.disabled) return const SizedBox.shrink();
    return StudioRailIconButton(
      tooltip: '好友与消息',
      size: 44,
      onPressed: () => showSocialOverlay(
        context,
        prepareToOpenInvitation: prepareToOpenInvitation,
      ),
      child: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(LucideIcons.messagesSquare, size: 20),
      ),
    );
  }
}

Future<void> showSocialOverlay(
  BuildContext context, {
  Future<bool> Function()? prepareToOpenInvitation,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) {
    final size = MediaQuery.sizeOf(dialogContext);
    final body = Scaffold(
      body: SafeArea(
        child: SocialInvitationHost(
          onOpen: (id) async {
            // Close the inbox only after the whiteboard has confirmed and saved.
            if (prepareToOpenInvitation == null ||
                !await prepareToOpenInvitation()) {
              return;
            }
            if (!context.mounted || !dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            context.go(AppRoutes.socialInvitationPath(id));
          },
          child: SocialPage(onClose: () => Navigator.of(dialogContext).pop()),
        ),
      ),
    );
    // A modal keeps the owning whiteboard route and collaboration alive.
    return size.width < shellCompactBreakpoint
        ? Dialog.fullscreen(child: body)
        : Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: math.min(1120, size.width - 64),
              height: math.min(800, size.height - 64),
              child: body,
            ),
          );
  },
);
