import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';

class CollaborationCrypto {
  CollaborationCrypto({AesGcm? algorithm})
    : _algorithm = algorithm ?? AesGcm.with128bits();

  static final Random _random = Random.secure();
  final AesGcm _algorithm;

  String generateRoomKey() {
    final bytes = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<EncryptedPayload> encrypt({
    required String roomKey,
    required List<int> plainBytes,
  }) async {
    final nonce = _randomBytes(12);
    final secretBox = await _algorithm.encrypt(
      plainBytes,
      secretKey: SecretKey(_decodeRoomKey(roomKey)),
      nonce: nonce,
    );
    return EncryptedPayload(
      cipherText: secretBox.cipherText,
      iv: secretBox.nonce,
      mac: secretBox.mac.bytes,
    );
  }

  Future<List<int>> decrypt({
    required String roomKey,
    required EncryptedPayload encryptedPayload,
  }) {
    return _algorithm.decrypt(
      SecretBox(
        encryptedPayload.cipherText,
        nonce: encryptedPayload.iv,
        mac: Mac(encryptedPayload.mac),
      ),
      secretKey: SecretKey(_decodeRoomKey(roomKey)),
    );
  }

  static List<int> _decodeRoomKey(String roomKey) {
    return base64Url.decode(base64Url.normalize(roomKey));
  }

  static List<int> _randomBytes(int length) {
    return List<int>.generate(
      length,
      (_) => _random.nextInt(256),
      growable: false,
    );
  }
}
