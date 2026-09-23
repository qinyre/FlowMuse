import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart' show immutable;
import '../services/hpke_auth.dart';

List<int> invitationBytes(String value, {int? length, int max = 2048}) {
  if (value.length > (max * 4 + 2) ~/ 3 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid invitation encoding');
  }
  final bytes = base64Url.decode(base64Url.normalize(value));
  if (bytes.length > max ||
      (length != null && bytes.length != length) ||
      invitationBase64(bytes) != value) {
    throw const FormatException('Invalid invitation encoding');
  }
  return bytes;
}

String invitationBase64(List<int> value) =>
    base64Url.encode(value).replaceAll('=', '');

@immutable
class InvitationContext {
  InvitationContext({
    required this.inviteId,
    required this.roomId,
    required this.senderId,
    required this.recipientId,
    required this.senderDeviceId,
    required this.senderKeyId,
    required this.recipientDeviceId,
    required this.keyId,
    required this.expiresAt,
  }) {
    if ([
          inviteId,
          roomId,
          senderId,
          recipientId,
          senderDeviceId,
          senderKeyId,
          recipientDeviceId,
          keyId,
        ].any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) ||
        senderId == recipientId ||
        expiresAt <= 0 ||
        expiresAt > 9007199254740991) {
      throw const FormatException('Invalid invitation context');
    }
  }
  factory InvitationContext.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported invitation');
    }
    return InvitationContext(
      inviteId: json['inviteId'],
      roomId: json['roomId'],
      senderId: json['senderId'],
      recipientId: json['recipientId'],
      senderDeviceId: json['senderDeviceId'],
      senderKeyId: json['senderKeyId'],
      recipientDeviceId: json['recipientDeviceId'],
      keyId: json['keyId'],
      expiresAt: json['expiresAt'],
    );
  }
  final String inviteId,
      roomId,
      senderId,
      recipientId,
      senderDeviceId,
      senderKeyId,
      recipientDeviceId,
      keyId;
  final int expiresAt;
  List<int> get aad => utf8.encode(
    jsonEncode([
      1,
      inviteId,
      roomId,
      senderId,
      recipientId,
      senderDeviceId,
      senderKeyId,
      recipientDeviceId,
      keyId,
      expiresAt.toString(),
    ]),
  );
  Map<String, dynamic> toJson() => {
    'version': 1,
    'inviteId': inviteId,
    'roomId': roomId,
    'senderId': senderId,
    'recipientId': recipientId,
    'senderDeviceId': senderDeviceId,
    'senderKeyId': senderKeyId,
    'recipientDeviceId': recipientDeviceId,
    'keyId': keyId,
    'expiresAt': expiresAt,
  };
}

@immutable
class InvitationEnvelope {
  InvitationEnvelope({
    required this.context,
    required this.enc,
    required this.ciphertext,
  }) {
    invitationBytes(enc, length: 32);
    if (invitationBytes(ciphertext).length < 16) {
      throw const FormatException('Invalid invitation');
    }
  }
  factory InvitationEnvelope.fromJson(Map<String, dynamic> json) {
    if (json['suite'] != HpkeAuth.suite) {
      throw const FormatException('Unsupported invitation suite');
    }
    return InvitationEnvelope(
      context: InvitationContext.fromJson(json),
      enc: json['enc'],
      ciphertext: json['ciphertext'],
    );
  }
  final InvitationContext context;
  final String enc, ciphertext;
  Map<String, dynamic> toJson() => {
    ...context.toJson(),
    'suite': HpkeAuth.suite,
    'enc': enc,
    'ciphertext': ciphertext,
  };
}

@immutable
class SocialDevice {
  const SocialDevice({
    required this.id,
    required this.userId,
    required this.keyId,
    required this.publicKey,
    required this.fingerprint,
    required this.label,
    this.revokedAt = 0,
  });
  factory SocialDevice.fromJson(Map<String, dynamic> json) => SocialDevice(
    id: json['id'],
    userId: json['userId'],
    keyId: json['keyId'],
    publicKey: json['publicKey'],
    fingerprint: json['fingerprint'],
    label: json['label'],
    revokedAt: (json['revokedAt'] as num?)?.toInt() ?? 0,
  );
  final String id, userId, keyId, publicKey, fingerprint, label;
  final int revokedAt;
}

@immutable
class SocialDeviceSet {
  SocialDeviceSet.fromJson(Map<String, dynamic> json)
    : version = BigInt.parse(json['keysetVersion'] as String),
      devices = List.unmodifiable(
        (json['items'] as List).map(
          (v) => SocialDevice.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      );
  final BigInt version;
  final List<SocialDevice> devices;
}

@immutable
class SocialInvitation {
  const SocialInvitation({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.recipientId,
    required this.conversationId,
    required this.status,
    required this.version,
    required this.expiresAt,
    this.joinedAt = 0,
  });
  factory SocialInvitation.fromJson(Map<String, dynamic> json) =>
      SocialInvitation(
        id: json['id'],
        roomId: json['roomId'],
        senderId: json['senderId'],
        recipientId: json['recipientId'],
        conversationId: json['conversationId'],
        status: json['status'],
        version: BigInt.parse(json['version']),
        expiresAt: (json['expiresAt'] as num).toInt(),
        joinedAt: (json['joinedAt'] as num?)?.toInt() ?? 0,
      );
  final String id, roomId, senderId, recipientId, conversationId, status;
  final BigInt version;
  final int expiresAt, joinedAt;
  bool get canAccept => status == 'pending' || status == 'accepted';
}
