import 'package:flutter/foundation.dart';

import 'social_models.dart';

@immutable
class SocialNotice {
  const SocialNotice({
    required this.key,
    required this.userId,
    required this.person,
    required this.summary,
    this.conversationId,
    this.seq,
    this.invitation = false,
    this.expiresAt,
    this.count = 1,
  });

  final String key, userId, summary;
  final SocialPerson person;
  final String? conversationId;
  final BigInt? seq;
  final bool invitation;
  final int? expiresAt;
  final int count;

  bool get friendRequest => conversationId == null;
  String get label => friendRequest
      ? '新的好友申请'
      : invitation
      ? '协作邀请'
      : count > 1
      ? '$count 条未读消息'
      : '新消息';
}
