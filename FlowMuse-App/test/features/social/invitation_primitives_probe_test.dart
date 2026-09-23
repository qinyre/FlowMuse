// T03 prerequisite only. This does NOT implement or validate HPKE Auth.
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

void main() {
  test('邀请原语探针：RFC 7748 X25519 固定向量', () async {
    // Public test data from https://datatracker.ietf.org/doc/html/rfc7748#section-6.1
    final x = X25519();
    final alice = await x.newKeyPairFromSeed(
      _hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
    );
    final bob = await x.newKeyPairFromSeed(
      _hex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb'),
    );
    final publicAlice = await alice.extractPublicKey();
    final publicBob = await bob.extractPublicKey();
    expect(
      publicAlice.bytes,
      _hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a'),
    );
    expect(
      publicBob.bytes,
      _hex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f'),
    );
    final a = await x.sharedSecretKey(
      keyPair: alice,
      remotePublicKey: publicBob,
    );
    final b = await x.sharedSecretKey(
      keyPair: bob,
      remotePublicKey: publicAlice,
    );
    expect(
      await a.extractBytes(),
      _hex('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742'),
    );
    expect(await b.extractBytes(), await a.extractBytes());
  });

  test('邀请原语探针：RFC 5869 HKDF-SHA256 向量', () async {
    // https://datatracker.ietf.org/doc/html/rfc5869#appendix-A.1
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
      secretKey: SecretKey(List.filled(22, 0x0b)),
      nonce: _hex('000102030405060708090a0b0c'),
      info: _hex('f0f1f2f3f4f5f6f7f8f9'),
    );
    expect(
      await key.extractBytes(),
      _hex(
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
      ),
    );
  });

  test('邀请原语探针：AES-128-GCM 往返及错误 AAD 拒绝', () async {
    final aes = AesGcm.with128bits();
    final key = await aes.newSecretKey();
    final body = List.generate(16, (i) => i);
    final box = await aes.encrypt(body, secretKey: key, aad: [1, 2, 3]);
    expect(await aes.decrypt(box, secretKey: key, aad: [1, 2, 3]), body);
    await expectLater(
      aes.decrypt(box, secretKey: key, aad: [1, 2, 4]),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
