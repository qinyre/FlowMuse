import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/social/view_models/social_view_model.dart';
import '../features/social/views/social_page.dart';
import '../features/whiteboard/editor_core/src/ui/studio_rail_icon_button.dart';
import '../shared/widgets/app_shell.dart';

/// Host-owned action: inbox updates rebuild this button, never the canvas.
class SocialMessagesAction extends ConsumerWidget {
  const SocialMessagesAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, count) = ref.watch(
      socialViewModelProvider.select((s) => (s.status, s.badgeCount)),
    );
    if (status == SocialStatus.disabled) return const SizedBox.shrink();
    return StudioRailIconButton(
      tooltip: '好友与消息',
      size: 44,
      onPressed: () => showSocialOverlay(context),
      child: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(LucideIcons.messagesSquare, size: 20),
      ),
    );
  }
}

Future<void> showSocialOverlay(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final size = MediaQuery.sizeOf(context);
    final body = Scaffold(
      body: SafeArea(
        child: SocialPage(onClose: () => Navigator.of(context).pop()),
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
