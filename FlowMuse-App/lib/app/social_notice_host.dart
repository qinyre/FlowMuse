import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../features/account/widgets/account_avatar.dart';
import '../features/social/models/social_notice.dart';
import '../features/social/view_models/social_notice_preferences.dart';
import '../features/social/view_models/social_notice_view_model.dart';
import '../features/social/view_models/social_view_model.dart';
import '../shared/widgets/app_motion.dart';
import '../shared/widgets/app_spacing.dart';
import 'social_overlay.dart';

class SocialNoticeHost extends ConsumerStatefulWidget {
  const SocialNoticeHost({
    super.key,
    required this.router,
    required this.child,
  });
  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<SocialNoticeHost> createState() => _SocialNoticeHostState();
}

class _SocialNoticeHostState extends ConsumerState<SocialNoticeHost> {
  Timer? _timer;
  SocialNotice? _displayed;
  bool _opening = false, _hovered = false, _focused = false;

  void _scheduleDismiss() {
    _timer?.cancel();
    final notice = _displayed;
    if (notice == null) return;
    Duration? duration;
    if (!_hovered && !_focused && !MediaQuery.accessibleNavigationOf(context)) {
      duration = const Duration(seconds: 8);
    }
    if (notice.expiresAt != null) {
      final remaining = Duration(
        milliseconds: notice.expiresAt! - DateTime.now().millisecondsSinceEpoch,
      );
      if (duration == null || remaining < duration) {
        duration = remaining.isNegative ? Duration.zero : remaining;
      }
    }
    if (duration == null) return;
    _timer = Timer(duration, () {
      if (mounted && identical(_displayed, notice)) {
        ref.read(socialNoticeProvider.notifier).dismiss(notice.key);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _open(SocialNotice notice) async {
    if (notice.userId != ref.read(socialSessionProvider)?.userId) {
      return;
    }
    if (ref.read(socialNoticeActivityProvider).openInbox(notice)) {
      ref.read(socialNoticeProvider.notifier).dismiss(notice.key);
      return;
    }
    if (_opening) return;
    final context = widget.router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    _opening = true;
    ref.read(socialNoticeProvider.notifier).dismiss(notice.key);
    try {
      final whiteboard = ref
          .read(socialInboxPresenterProvider)
          .openFromWhiteboard;
      if (whiteboard != null) {
        await whiteboard(notice);
      } else {
        await showSocialOverlay(
          context,
          initialConversationId: notice.conversationId,
          initialTab: notice.friendRequest ? 2 : 0,
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(socialNoticeProvider);
    final notice = notices.lastOrNull;
    final visibility = ref.watch(
      socialViewModelProvider.select((s) => (s.me?.person.id, s.foreground)),
    );
    final preview =
        ref.watch(socialNoticePreferencesProvider).asData?.value.preview ??
        false;
    if (!identical(_displayed, notice)) {
      _displayed = notice;
      _hovered = false;
      _focused = false;
      _scheduleDismiss();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sidebarInset),
                child: AnimatedSwitcher(
                  key: ValueKey(visibility),
                  duration: AppMotion.resolve(context, AppMotion.standard),
                  reverseDuration: AppMotion.resolve(context, AppMotion.exit),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -.12),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: notice == null
                      ? const SizedBox.shrink()
                      : MouseRegion(
                          key: ValueKey(notice.key),
                          onEnter: (_) {
                            _hovered = true;
                            _scheduleDismiss();
                          },
                          onExit: (_) {
                            _hovered = false;
                            _scheduleDismiss();
                          },
                          child: Focus(
                            onFocusChange: (value) {
                              _focused = value;
                              _scheduleDismiss();
                            },
                            child: SocialNoticeBanner(
                              notice: notice,
                              preview: preview,
                              onOpen: () => _open(notice),
                              onDismiss: () => ref
                                  .read(socialNoticeProvider.notifier)
                                  .dismiss(notice.key),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SocialNoticeBanner extends StatelessWidget {
  const SocialNoticeBanner({
    super.key,
    required this.notice,
    required this.preview,
    required this.onOpen,
    required this.onDismiss,
  });
  final SocialNotice notice;
  final bool preview;
  final VoidCallback onOpen, onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = preview
        ? notice.summary
        : notice.invitation
        ? '邀请你一起编辑白板'
        : notice.friendRequest
        ? '希望添加你为好友'
        : '发来一条新消息';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Semantics(
        liveRegion: true,
        child: Material(
          color: colors.surfaceContainerLow,
          elevation: 5,
          shadowColor: colors.shadow.withValues(alpha: .16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.listGap),
            side: BorderSide(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sidebarInset),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: AccountAvatar(
                            label: notice.person.name,
                            avatarUrl: notice.person.avatarUrl,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.listGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notice.label,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: colors.primary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                notice.person.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                summary.replaceAll(RegExp(r'\s+'), ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: AppSpacing.controlGap),
                              Text(
                                notice.friendRequest
                                    ? '查看申请'
                                    : notice.invitation
                                    ? '查看邀请'
                                    : '查看消息',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: colors.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onDismiss,
                icon: const Icon(
                  LucideIcons.x,
                  size: 18,
                  semanticLabel: '关闭提醒',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
