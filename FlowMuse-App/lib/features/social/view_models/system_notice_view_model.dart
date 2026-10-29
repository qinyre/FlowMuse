import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_notice.dart';
import '../models/system_notice.dart';
import '../services/system_notice_service.dart';
import 'social_notice_preferences.dart';
import 'social_notice_view_model.dart';
import 'social_view_model.dart';

final systemNoticeProvider =
    NotifierProvider<SystemNoticeViewModel, SystemNoticeTarget?>(
      SystemNoticeViewModel.new,
    );

class SystemNoticeViewModel extends Notifier<SystemNoticeTarget?> {
  late SystemNoticeService _service;
  final _sent = <String, SystemNoticeMessage>{};
  final _expiry = <String, Timer>{};
  Future<void> _operations = Future.value();
  int _generation = 0;

  @override
  SystemNoticeTarget? build() {
    _service = ref.watch(systemNoticeServiceProvider);
    ref.listen(socialSessionProvider, (before, next) {
      if (before?.userId != next?.userId) {
        _clear();
        if (state?.userId != next?.userId) state = null;
      }
    });
    ref.listen(socialNoticePreferencesProvider, (_, next) {
      final prefs = next.asData?.value;
      if (prefs?.systemEnabled != true || prefs?.doNotDisturb != false) {
        _clear();
      }
      // Previously visible previews must disappear when preview is disabled.
      if (prefs?.preview == false) _clear();
    });
    ref.listen(socialViewModelProvider, (_, next) {
      for (final entry in _sent.entries.toList()) {
        final notice = entry.value;
        final target = notice.target;
        final conversation = next.conversations
            .where((c) => c.id == target.conversationId)
            .firstOrNull;
        final request = next.requests
            .where((r) => 'request:${r.id}' == target.key)
            .firstOrNull;
        final peer = conversation?.person.id ?? request?.person.id;
        final stale =
            next.status != SocialStatus.ready ||
            next.me?.person.id != target.userId ||
            next.blocks.any((p) => p.id == peer) ||
            target.expiresAt <= DateTime.now().millisecondsSinceEpoch ||
            (target.conversationId == null
                ? !next.requests.any((r) => 'request:${r.id}' == target.key)
                : conversation != null &&
                      (!conversation.canSend ||
                          conversation.unreadCount == 0 ||
                          (next.foreground &&
                              ref
                                  .read(socialNoticeActivityProvider)
                                  .isViewing(conversation.id)) ||
                          (conversation.lastMessage?.invitation != null &&
                              !conversation
                                  .lastMessage!
                                  .invitation!
                                  .canAccept)));
        if (stale) _cancel(entry.key);
      }
    });
    ref.listen(socialNoticeProvider, (before, next) {
      final old = {for (final n in before ?? <SocialNotice>[]) n.key: n};
      for (final notice in next) {
        if (!identical(notice, old[notice.key])) _show(notice);
      }
    });
    Future.microtask(() async {
      if (!ref.mounted) return;
      try {
        await _service.initialize((target) {
          if (!ref.mounted) return;
          final session = ref.read(socialSessionProvider);
          if (session != null && session.userId != target.userId) return;
          state = target;
        });
        // A fresh process clears old OS previews; click intents were consumed first.
        if (ref.mounted) _clear();
      } catch (_) {
        debugPrint('[FlowMuseSocial] system notice initialization unavailable');
      }
    });
    ref.onDispose(() {
      _generation++;
      for (final timer in _expiry.values) {
        timer.cancel();
      }
    });
    return null;
  }

  void consumeTap() => state = null;

  void _enqueue(Future<void> Function() action) {
    _operations = _operations.then((_) => action()).catchError((Object _) {
      debugPrint('[FlowMuseSocial] system notice operation unavailable');
    });
  }

  bool _allowed(SocialNotice notice) {
    final prefs = ref.read(socialNoticePreferencesProvider).asData?.value;
    final social = ref.read(socialViewModelProvider);
    return ref.read(socialSessionProvider)?.userId == notice.userId &&
        social.status == SocialStatus.ready &&
        prefs?.systemEnabled == true &&
        prefs?.doNotDisturb == false &&
        (!social.foreground || prefs?.enabled == false) &&
        (notice.expiresAt == null ||
            notice.expiresAt! > DateTime.now().millisecondsSinceEpoch);
  }

  void _show(SocialNotice notice) {
    final generation = _generation;
    if (!_allowed(notice)) return;
    _enqueue(() async {
      if (!ref.mounted || generation != _generation || !_allowed(notice)) {
        return;
      }
      if (await _service.permission() != SystemNoticePermission.granted) return;
      if (!ref.mounted || generation != _generation || !_allowed(notice)) {
        return;
      }
      // A read/blocked event may have overtaken the permission lookup.
      if (!ref.read(socialNoticeProvider).contains(notice)) return;
      final preview =
          ref.read(socialNoticePreferencesProvider).asData?.value.preview ==
          true;
      final message = SystemNoticeMessage.fromNotice(notice, preview: preview);
      await _service.show(message);
      if (!ref.mounted || generation != _generation) return;
      if (!_allowed(notice) ||
          !ref.read(socialNoticeProvider).contains(notice)) {
        await _service.cancel(message.tag);
        return;
      }
      _sent[message.tag] = message;
      _expiry.remove(message.tag)?.cancel();
      _expiry[message.tag] = Timer(
        Duration(
          milliseconds:
              message.target.expiresAt - DateTime.now().millisecondsSinceEpoch,
        ),
        () => _cancel(message.tag),
      );
      if (_sent.length > 20) _cancel(_sent.keys.first);
    });
  }

  void _cancel(String tag) {
    _sent.remove(tag);
    _expiry.remove(tag)?.cancel();
    _enqueue(() => _service.cancel(tag));
  }

  void _clear() {
    _generation++;
    _sent.clear();
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    _enqueue(_service.clear);
  }
}
