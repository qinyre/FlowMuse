import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';

void main() {
  test(
    'encrypts and decrypts a collaboration payload with generated room key',
    () async {
      final crypto = CollaborationCrypto();
      final roomKey = crypto.generateRoomKey();
      final payload = utf8.encode('{"type":"scene_update"}');

      final encrypted = await crypto.encrypt(
        roomKey: roomKey,
        plainBytes: payload,
      );
      final decrypted = await crypto.decrypt(
        roomKey: roomKey,
        encryptedPayload: encrypted,
      );

      expect(utf8.decode(decrypted), '{"type":"scene_update"}');
    },
  );

  test('generates a different iv for each encrypted payload', () async {
    final crypto = CollaborationCrypto();
    final roomKey = crypto.generateRoomKey();

    final first = await crypto.encrypt(
      roomKey: roomKey,
      plainBytes: utf8.encode('same'),
    );
    final second = await crypto.encrypt(
      roomKey: roomKey,
      plainBytes: utf8.encode('same'),
    );

    expect(first.iv, isNot(second.iv));
    expect(first.encryptedBuffer, isNot(second.encryptedBuffer));
  });
}
