import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/services/invitation_crypto.dart';

void main() {
  test('邀请绑定全部上下文，换设备/邀请/过期与不规范编码拒绝', () async {
    final a = await X25519().newKeyPair(), b = await X25519().newKeyPair();
    final pubA = invitationBase64((await a.extractPublicKey()).bytes);
    final pubB = invitationBase64((await b.extractPublicKey()).bytes);
    final context = InvitationContext(
      inviteId: 'i',
      roomId: 'r',
      senderId: 'a',
      recipientId: 'b',
      senderDeviceId: 'ad',
      senderKeyId: 'ak',
      recipientDeviceId: 'bd',
      keyId: 'bk',
      expiresAt: 2000000000000,
    );
    expect(
      utf8.decode(context.aad),
      '[1,"i","r","a","b","ad","ak","bd","bk","2000000000000"]',
    );
    final crypto = InvitationCrypto();
    final key = invitationBase64(List.generate(16, (i) => i));
    final envelope = await crypto.seal(
      context: context,
      roomKey: key,
      sender: a,
      recipientPublicKey: pubB,
    );
    final plain = await crypto.open(
      envelope: envelope,
      expected: context,
      recipient: b,
      trustedSenderPublicKey: pubA,
    );
    expect(plain == key, isTrue);
    expect(envelope.toJson().containsKey('roomKey'), isFalse);
    for (final field in [
      'inviteId',
      'roomId',
      'senderId',
      'recipientId',
      'senderDeviceId',
      'senderKeyId',
      'recipientDeviceId',
      'keyId',
    ]) {
      final changed = InvitationContext.fromJson({
        ...context.toJson(),
        field: 'changed',
      });
      await expectLater(
        crypto.open(
          envelope: envelope,
          expected: changed,
          recipient: b,
          trustedSenderPublicKey: pubA,
        ),
        throwsFormatException,
      );
    }
    await expectLater(
      crypto.open(
        envelope: envelope,
        expected: context,
        recipient: b,
        trustedSenderPublicKey: pubA,
        now: DateTime.fromMillisecondsSinceEpoch(context.expiresAt),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          InvitationEnvelope.fromJson({...envelope.toJson(), 'suite': 'Base'}),
      throwsFormatException,
    );
    expect(() => invitationBytes('${envelope.enc}='), throwsFormatException);
    expect(() => invitationBytes('A' * 4096), throwsFormatException);
    await expectLater(
      crypto.seal(
        context: context,
        roomKey: 'invalid',
        sender: a,
        recipientPublicKey: pubB,
      ),
      throwsFormatException,
    );
  });
}
