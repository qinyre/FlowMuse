import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import '../models/social_notice.dart';
import 'social_notice_preferences.dart';
import 'social_view_model.dart';

/// Views register a visibility check so covered or inactive chats do not mute
/// notifications. No UI state is written during widget build/disposal.
class SocialNoticeActivity {
  final conversations = <Object, bool Function(String)>{};
  final inboxes = <Object, bool Function(SocialNotice)>{};
  bool isViewing(String id) => conversations.values.any((check) => check(id));
  bool openInbox(SocialNotice notice) =>
      inboxes.values.any((open) => open(notice));
}

final socialNoticeActivityProvider = Provider((ref) => SocialNoticeActivity());
final socialNoticeProvider =
    NotifierProvider<SocialNoticeViewModel, List<SocialNotice>>(
      SocialNoticeViewModel.new,
    );

class SocialNoticeViewModel extends Notifier<List<SocialNotice>> {
  final _seen = <String, BigInt>{};
  bool _baselinePending = true;

  @override
  List<SocialNotice> build() {
    ref.listen(socialNoticePreferencesProvider, (_, next) {
      final prefs = next.asData?.value;
      if (prefs == null || !prefs.enabled || prefs.doNotDisturb) {
        state = const [];
      }
    });
    ref.listen(socialViewModelProvider, _observe);
    return const [];
  }

  void _observe(SocialState? before, SocialState next) {
    final user = next.me?.person.id;
    if (next.status != SocialStatus.ready ||
        !next.foreground ||
        user == null ||
        before?.me?.person.id != user ||
        before?.foreground != true ||
        (next.connected && before?.connected != true)) {
      _baselinePending = true;
      _seen.clear();
      state = const [];
    }
    if (next.status != SocialStatus.ready || !next.foreground || user == null) {
      return;
    }
    final previousSeq = Map<String, BigInt>.of(_seen);
    for (final c in next.conversations) {
      final seen = _seen[c.id] ?? BigInt.zero;
      if (c.lastSeq > seen) _seen[c.id] = c.lastSeq;
    }
    if (before?.revision == next.revision) return;
    if (_baselinePending) {
      _baselinePending = false;
      return;
    }
    final prefs = ref.read(socialNoticePreferencesProvider).asData?.value;
    if (prefs == null || !prefs.enabled || prefs.doNotDisturb) return;
    final activity = ref.read(socialNoticeActivityProvider);
    final conversations = {for (final c in next.conversations) c.id: c};
    final requests = {for (final r in next.requests) r.id};
    var queue = state.where((n) {
      if (next.blocks.any((p) => p.id == n.person.id)) return false;
      if (n.friendRequest) {
        return requests.contains(n.key.substring('request:'.length));
      }
      final c = conversations[n.conversationId];
      return !activity.isViewing(n.conversationId!) &&
          (c == null ||
              (c.canSend && c.readSeq < n.seq! && c.unreadCount > 0)) &&
          (n.expiresAt == null ||
              n.expiresAt! > DateTime.now().millisecondsSinceEpoch) &&
          (!n.invitation ||
              c?.lastMessage?.seq != n.seq ||
              c?.lastMessage?.invitation?.canAccept == true);
    }).toList();
    void add(SocialNotice notice) {
      queue.removeWhere((n) => n.key == notice.key);
      queue.add(notice);
    }

    // Oldest first, so a burst displays its newest conversation first.
    final ordered = next.conversations.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    for (final c in ordered) {
      final m = c.lastMessage;
      if (!c.canSend ||
          c.unreadCount == 0 ||
          m == null ||
          m.senderId == user ||
          m.seq <= (previousSeq[c.id] ?? BigInt.zero) ||
          m.seq <= c.readSeq ||
          activity.isViewing(c.id)) {
        continue;
      }
      final invite = m.invitation;
      if (invite != null &&
          (!invite.canAccept ||
              invite.expiresAt <= DateTime.now().millisecondsSinceEpoch)) {
        continue;
      }
      add(
        SocialNotice(
          key: 'conversation:${c.id}',
          userId: user,
          person: c.person,
          conversationId: c.id,
          seq: m.seq,
          count: c.unreadCount,
          invitation: invite != null,
          expiresAt: invite?.expiresAt,
          summary: invite == null ? m.text : '邀请你一起编辑白板',
        ),
      );
    }
    final oldRequests = {
      for (final r in before?.requests ?? <SocialRelationship>[]) r.id,
    };
    for (final r in next.requests) {
      if (r.requesterId == user || oldRequests.contains(r.id)) continue;
      add(
        SocialNotice(
          key: 'request:${r.id}',
          userId: user,
          person: r.person,
          summary: r.message.isEmpty ? '希望添加你为好友' : r.message,
        ),
      );
    }
    // Keep only a small, account-local queue; unread history stays in the inbox.
    if (queue.length > 5) queue = queue.sublist(queue.length - 5);
    state = List.unmodifiable(queue);
  }

  void dismiss(String key) =>
      state = List.unmodifiable(state.where((n) => n.key != key));
}
