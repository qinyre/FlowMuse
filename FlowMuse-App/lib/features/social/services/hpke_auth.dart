import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

/// RFC 9180 single-shot Auth: X25519 / HKDF-SHA256 / AES-128-GCM.
/// Each call owns a fresh context and uses sequence 0 exactly once. No fallback
/// to Base mode, multi-message context, secret exporter, or algorithm negotiation.
class HpkeAuth {
  HpkeAuth({Future<SimpleKeyPair> Function()? ephemeralKeyPair})
    : _ephemeralKeyPair = ephemeralKeyPair ?? X25519().newKeyPair;

  // Injectable randomness is only for published test vectors.
  final Future<SimpleKeyPair> Function() _ephemeralKeyPair;
  static const suite = 'HPKE-Auth-X25519-HKDF-SHA256-AES128GCM-v1';
  static final _kem = [...ascii.encode('KEM'), 0, 32];
  static final _suite = [...ascii.encode('HPKE'), 0, 32, 0, 1, 0, 1];

  Future<({List<int> enc, List<int> ciphertext})> seal({
    required SimpleKeyPair sender,
    required List<int> recipientPublicKey,
    required List<int> info,
    required List<int> aad,
    required List<int> plaintext,
  }) async {
    _limits(info, aad, plaintext.length, 1024);
    final ephemeral = await _ephemeralKeyPair();
    final enc = (await ephemeral.extractPublicKey()).bytes;
    final senderPublic = (await sender.extractPublicKey()).bytes;
    final dh = [
      ...await _dh(ephemeral, recipientPublicKey),
      ...await _dh(sender, recipientPublicKey),
    ];
    final context = _schedule(dh, [
      ...enc,
      ...recipientPublicKey,
      ...senderPublic,
    ], info);
    final box = await AesGcm.with128bits().encrypt(
      plaintext,
      secretKey: context.key,
      nonce: context.nonce,
      aad: aad,
    );
    return (enc: enc, ciphertext: [...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> open({
    required SimpleKeyPair recipient,
    required List<int> senderPublicKey,
    required List<int> enc,
    required List<int> ciphertext,
    required List<int> info,
    required List<int> aad,
  }) async {
    _limits(info, aad, ciphertext.length, 1040);
    if (ciphertext.length < 16) {
      throw const FormatException('Invalid invitation');
    }
    final recipientPublic = (await recipient.extractPublicKey()).bytes;
    final dh = [
      ...await _dh(recipient, enc),
      ...await _dh(recipient, senderPublicKey),
    ];
    final context = _schedule(dh, [
      ...enc,
      ...recipientPublic,
      ...senderPublicKey,
    ], info);
    return AesGcm.with128bits().decrypt(
      SecretBox(
        ciphertext.sublist(0, ciphertext.length - 16),
        nonce: context.nonce,
        mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
      ),
      secretKey: context.key,
      aad: aad,
    );
  }

  static void _limits(List<int> info, List<int> aad, int size, int max) {
    if (info.length > 1024 || aad.length > 2048 || size > max) {
      throw const FormatException('Invalid invitation');
    }
  }

  static Future<List<int>> _dh(SimpleKeyPair key, List<int> publicKey) async {
    if (publicKey.length != 32) {
      throw const FormatException('Invalid public key');
    }
    final secret = await X25519().sharedSecretKey(
      keyPair: key,
      remotePublicKey: SimplePublicKey(publicKey, type: KeyPairType.x25519),
    );
    final bytes = await secret.extractBytes();
    var nonzero = 0;
    for (final b in bytes) {
      nonzero |= b;
    }
    if (bytes.length != 32 || nonzero == 0) {
      throw const FormatException('Invalid public key');
    }
    return bytes;
  }

  static ({SecretKey key, List<int> nonce}) _schedule(
    List<int> dh,
    List<int> kemContext,
    List<int> info,
  ) {
    final eae = _extract(_kem, const [], 'eae_prk', dh);
    final shared = _expand(_kem, eae, 'shared_secret', kemContext, 32);
    final context = [
      2,
      ..._extract(_suite, const [], 'psk_id_hash', const []),
      ..._extract(_suite, const [], 'info_hash', info),
    ];
    final secret = _extract(_suite, shared, 'secret', const []);
    return (
      key: SecretKey(_expand(_suite, secret, 'key', context, 16)),
      nonce: _expand(_suite, secret, 'base_nonce', context, 12),
    );
  }

  static List<int> _extract(
    List<int> suite,
    List<int> salt,
    String label,
    List<int> ikm,
  ) => hash.Hmac(hash.sha256, salt).convert([
    ...ascii.encode('HPKE-v1'),
    ...suite,
    ...ascii.encode(label),
    ...ikm,
  ]).bytes;

  static List<int> _expand(
    List<int> suite,
    List<int> prk,
    String label,
    List<int> info,
    int length,
  ) {
    // All outputs in this fixed suite are at most one SHA-256 block.
    assert(length > 0 && length <= 32);
    return hash.Hmac(hash.sha256, prk)
        .convert([
          0,
          length,
          ...ascii.encode('HPKE-v1'),
          ...suite,
          ...ascii.encode(label),
          ...info,
          1,
        ])
        .bytes
        .sublist(0, length);
  }
}
