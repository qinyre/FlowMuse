import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';

void main() {
  test('长笔大包保持AES格式互通并拒绝篡改', () async {
    final crypto = CollaborationCrypto();
    final roomKey = crypto.generateRoomKey();
    final bytes = List<int>.generate(256 * 1024, (i) => i % 251);
    final encrypted = await crypto.encrypt(roomKey: roomKey, plainBytes: bytes);
    expect(encrypted.iv.length, 12);
    expect(encrypted.encryptedBuffer.length, bytes.length + 16);
    final decrypted = await crypto.decrypt(
      roomKey: roomKey,
      encryptedPayload: encrypted,
    );
    expect(listEquals(decrypted, bytes), isTrue);
    final oldFormat = await CollaborationCrypto(
      algorithm: AesGcm.with128bits(),
    ).encrypt(roomKey: roomKey, plainBytes: bytes);
    expect(
      listEquals(
        await crypto.decrypt(roomKey: roomKey, encryptedPayload: oldFormat),
        bytes,
      ),
      isTrue,
    );
    oldFormat.encryptedBuffer[0] ^= 1;
    await expectLater(
      crypto.decrypt(roomKey: roomKey, encryptedPayload: oldFormat),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

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
