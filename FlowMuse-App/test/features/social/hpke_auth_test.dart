import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/social/services/hpke_auth.dart';
import 'fixtures/hpke_auth_vector.dart';

List<int> hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

void main() {
  final v = jsonDecode(hpkeAuthVectorJson) as Map<String, dynamic>;
  test('HPKE Auth 固定单次封装匹配 RFC 9180 A.1.3', () async {
    final sender = await X25519().newKeyPairFromSeed(hex(v['skSm']));
    final recipient = await X25519().newKeyPairFromSeed(hex(v['skRm']));
    final hpke = HpkeAuth(
      ephemeralKeyPair: () => X25519().newKeyPairFromSeed(hex(v['skEm'])),
    );
    final e = v['encryption'];
    final box = await hpke.seal(
      sender: sender,
      recipientPublicKey: hex(v['pkRm']),
      info: hex(v['info']),
      aad: hex(e['aad']),
      plaintext: hex(e['pt']),
    );
    // Compare booleans so failures never print keys or plaintext.
    expect(base64Encode(box.enc) == base64Encode(hex(v['enc'])), isTrue);
    expect(base64Encode(box.ciphertext) == base64Encode(hex(e['ct'])), isTrue);
    final plain = await hpke.open(
      recipient: recipient,
      senderPublicKey: hex(v['pkSm']),
      enc: box.enc,
      ciphertext: box.ciphertext,
      info: hex(v['info']),
      aad: hex(e['aad']),
    );
    expect(base64Encode(plain) == base64Encode(hex(e['pt'])), isTrue);
  });

  test('HPKE 错接收者、伪造发送者、AAD、密文与异常公钥全部拒绝', () async {
    final x = X25519();
    final a = await x.newKeyPair(),
        b = await x.newKeyPair(),
        wrong = await x.newKeyPair();
    final ap = (await a.extractPublicKey()).bytes,
        bp = (await b.extractPublicKey()).bytes;
    final hpke = HpkeAuth();
    final box = await hpke.seal(
      sender: a,
      recipientPublicKey: bp,
      info: [1],
      aad: [2],
      plaintext: [3],
    );
    Future<List<int>> open({
      SimpleKeyPair? key,
      List<int>? sender,
      List<int>? aad,
      List<int>? ciphertext,
      List<int>? enc,
    }) => hpke.open(
      recipient: key ?? b,
      senderPublicKey: sender ?? ap,
      enc: enc ?? box.enc,
      ciphertext: ciphertext ?? box.ciphertext,
      info: [1],
      aad: aad ?? [2],
    );
    await expectLater(open(key: wrong), throwsA(isA<Exception>()));
    await expectLater(
      open(sender: (await wrong.extractPublicKey()).bytes),
      throwsA(isA<Exception>()),
    );
    await expectLater(open(aad: [4]), throwsA(isA<Exception>()));
    await expectLater(
      open(
        ciphertext: [
          ...box.ciphertext.take(box.ciphertext.length - 1),
          box.ciphertext.last ^ 1,
        ],
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(open(enc: List.filled(32, 0)), throwsA(isA<Exception>()));
    await expectLater(
      open(sender: List.filled(31, 1)),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      open(ciphertext: List.filled(1041, 1)),
      throwsA(isA<Exception>()),
    );
    final other = await hpke.seal(
      sender: a,
      recipientPublicKey: bp,
      info: [1],
      aad: [2],
      plaintext: [3],
    );
    expect(base64Encode(box.enc) != base64Encode(other.enc), isTrue);
  });
}
