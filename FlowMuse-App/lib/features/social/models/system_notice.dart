import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'social_models.dart';
import 'social_notice.dart';

enum SystemNoticePermission { unsupported, prompt, denied, granted }

/// Only account-local routing identifiers cross the OS boundary.
@immutable
class SystemNoticeTarget {
  const SystemNoticeTarget({
    required this.userId,
    required this.key,
    required this.expiresAt,
    this.conversationId,
  });
  final String userId, key;
  final String? conversationId;
  final int expiresAt;

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static SystemNoticeTarget? parse(Object? raw) {
    try {
      if (raw is! String || raw.length > 1024) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final user = data['userId'] as String;
      final key = data['key'] as String;
      final conversation = data['conversationId'] as String?;
      final expires = data['expiresAt'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (data['version'] != 1 ||
          !_id.hasMatch(user) ||
          expires <= now ||
          expires > now + const Duration(days: 1).inMilliseconds ||
          (conversation != null
              ? !_id.hasMatch(conversation) ||
                    key != 'conversation:$conversation'
              : !key.startsWith('request:') ||
                    !_id.hasMatch(key.substring('request:'.length)))) {
        return null;
      }
      return SystemNoticeTarget(
        userId: user,
        key: key,
        conversationId: conversation,
        expiresAt: expires,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'version': 1,
    'userId': userId,
    'key': key,
    'conversationId': conversationId,
    'expiresAt': expiresAt,
  });

  SocialNotice toNotice() => SocialNotice(
    userId: userId,
    key: key,
    conversationId: conversationId,
    expiresAt: expiresAt,
    person: const SocialPerson(id: '', name: ''),
    summary: '',
  );
}

@immutable
class SystemNoticeMessage {
  const SystemNoticeMessage({
    required this.target,
    required this.title,
    required this.body,
  });
  factory SystemNoticeMessage.fromNotice(
    SocialNotice notice, {
    required bool preview,
  }) {
    final latest = DateTime.now()
        .add(const Duration(days: 1))
        .millisecondsSinceEpoch;
    return SystemNoticeMessage(
      target: SystemNoticeTarget(
        userId: notice.userId,
        key: notice.key,
        conversationId: notice.conversationId,
        expiresAt: notice.expiresAt == null || notice.expiresAt! > latest
            ? latest
            : notice.expiresAt!,
      ),
      title: preview
          ? notice.person.name.characters.take(60).toString()
          : 'FlowMuse',
      body: preview
          ? '${notice.label} · ${notice.summary.characters.take(120)}'
          : notice.friendRequest
          ? '你收到了一条好友申请'
          : notice.invitation
          ? '你收到了一条协作邀请'
          : '你收到了一条新消息',
    );
  }
  final SystemNoticeTarget target;
  final String title, body;
  String get tag => '${target.userId}:${target.key}';
  Map<String, Object> toJson() => {
    'tag': tag,
    'title': title,
    'body': body,
    'target': target.encode(),
    'expiresAt': target.expiresAt,
  };
}
