import 'package:flutter/foundation.dart';
import 'invitation_models.dart';

typedef SocialJson = Map<String, Object?>;

SocialJson socialJson(Object? value) => (value as Map).cast<String, Object?>();
BigInt socialSequence(Object? value) => BigInt.parse(value as String);

@immutable
class SocialPerson {
  const SocialPerson({
    required this.id,
    required this.name,
    this.avatarUrl = '',
    this.friendCode = '',
  });
  factory SocialPerson.fromJson(SocialJson json) => SocialPerson(
    id: json['id']! as String,
    name: json['displayName']! as String,
    avatarUrl: json['avatarUrl'] as String? ?? '',
    friendCode: json['friendCode'] as String? ?? '',
  );
  final String id, name, avatarUrl, friendCode;
  String get formattedCode => friendCode.length == 12
      ? '${friendCode.substring(0, 4)}-${friendCode.substring(4, 8)}-${friendCode.substring(8)}'
      : friendCode;
}

@immutable
class SocialRelationship {
  const SocialRelationship({
    required this.id,
    required this.person,
    required this.requesterId,
    required this.clientRequestId,
    required this.status,
    required this.version,
    this.message = '',
    this.conversationId = '',
  });
  factory SocialRelationship.fromJson(SocialJson json) => SocialRelationship(
    id: json['id']! as String,
    person: SocialPerson.fromJson(socialJson(json['person'])),
    requesterId: json['requesterId']! as String,
    clientRequestId: json['clientRequestId']! as String,
    status: json['state']! as String,
    version: socialSequence(json['version']),
    message: json['requestMessage'] as String? ?? '',
    conversationId: json['conversationId'] as String? ?? '',
  );
  final String id,
      requesterId,
      clientRequestId,
      status,
      message,
      conversationId;
  final SocialPerson person;
  final BigInt version;
}

@immutable
class SocialLookup {
  const SocialLookup(this.person, this.version, this.relationship);
  factory SocialLookup.fromJson(SocialJson json) => SocialLookup(
    SocialPerson.fromJson(socialJson(json['person'])),
    socialSequence(json['version']),
    json['relationship'] == null
        ? null
        : SocialRelationship.fromJson(socialJson(json['relationship'])),
  );
  final SocialPerson person;
  final BigInt version;
  final SocialRelationship? relationship;
}

@immutable
class SocialMessage {
  const SocialMessage({
    required this.id,
    required this.conversationId,
    required this.seq,
    required this.senderId,
    required this.clientMessageId,
    required this.text,
    required this.createdAt,
    this.invitation,
  });
  factory SocialMessage.fromJson(SocialJson json) {
    if (json['kind'] != 'text' && json['kind'] != 'invitation') {
      throw const FormatException('Unsupported message kind');
    }
    return SocialMessage(
      id: json['id']! as String,
      conversationId: json['conversationId']! as String,
      seq: socialSequence(json['seq']),
      senderId: json['senderId']! as String,
      clientMessageId: json['clientMessageId']! as String,
      text: json['kind'] == 'invitation' ? '协作白板' : json['text']! as String,
      invitation: json['kind'] == 'invitation'
          ? SocialInvitation.fromJson(
              Map<String, dynamic>.from(json['invitation']! as Map),
            )
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt']! as num).toInt(),
      ),
    );
  }
  final String id, conversationId, senderId, clientMessageId, text;
  final BigInt seq;
  final DateTime createdAt;
  final SocialInvitation? invitation;
}

@immutable
class SocialConversation {
  const SocialConversation({
    required this.id,
    required this.person,
    required this.canSend,
    required this.lastSeq,
    required this.readSeq,
    required this.unreadCount,
    required this.updatedAt,
    this.lastMessage,
  });
  factory SocialConversation.fromJson(SocialJson json) => SocialConversation(
    id: json['id']! as String,
    person: SocialPerson.fromJson(socialJson(json['person'])),
    canSend: json['canSend']! as bool,
    lastSeq: socialSequence(json['lastSeq']),
    readSeq: socialSequence(json['readSeq']),
    unreadCount: (json['unreadCount']! as num).toInt(),
    updatedAt: (json['updatedAt']! as num).toInt(),
    lastMessage: json['lastMessage'] == null
        ? null
        : SocialMessage.fromJson(socialJson(json['lastMessage'])),
  );
  final String id;
  final SocialPerson person;
  final bool canSend;
  final BigInt lastSeq, readSeq;
  final int unreadCount, updatedAt;
  final SocialMessage? lastMessage;
}

@immutable
class SocialMe {
  const SocialMe({
    required this.person,
    required this.unreadCount,
    required this.pendingRequestCount,
    required this.textMessages,
    this.invitations = false,
  });
  factory SocialMe.fromJson(SocialJson json) => SocialMe(
    person: SocialPerson.fromJson(socialJson(json['person'])),
    unreadCount: (json['unreadCount']! as num).toInt(),
    pendingRequestCount: (json['pendingRequestCount']! as num).toInt(),
    textMessages: socialJson(json['capabilities'])['textMessages'] == true,
    invitations: socialJson(json['capabilities'])['invitations'] == true,
  );
  final SocialPerson person;
  final int unreadCount, pendingRequestCount;
  final bool textMessages, invitations;
}

@immutable
class SocialPageResult<T> {
  const SocialPageResult(
    this.items, {
    this.nextCursor = '',
    this.hasMore = false,
  });
  factory SocialPageResult.fromJson(
    SocialJson json,
    T Function(SocialJson) read,
  ) => SocialPageResult(
    List.unmodifiable(
      (json['items']! as List).map((item) => read(socialJson(item))),
    ),
    nextCursor: json['nextCursor'] as String? ?? '',
    hasMore: json['hasMore'] == true,
  );
  final List<T> items;
  final String nextCursor;
  final bool hasMore;
}
