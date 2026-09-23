// Compile with dart compile js; open generated page on localhost or HTTPS.
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:web/web.dart' as web;
import 'package:flow_muse/features/social/services/hpke_auth.dart';
import '../test/features/social/fixtures/hpke_auth_vector.dart';

List<int> hex(String s) => [
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
];
Future<void> main() async {
  final target = web.document.querySelector('#result')!;
  try {
    final v = jsonDecode(hpkeAuthVectorJson);
    final e = v['encryption'];
    final a = await X25519().newKeyPairFromSeed(hex(v['skSm']));
    final b = await X25519().newKeyPairFromSeed(hex(v['skRm']));
    final hpke = HpkeAuth(
      ephemeralKeyPair: () => X25519().newKeyPairFromSeed(hex(v['skEm'])),
    );
    final box = await hpke.seal(
      sender: a,
      recipientPublicKey: hex(v['pkRm']),
      info: hex(v['info']),
      aad: hex(e['aad']),
      plaintext: hex(e['pt']),
    );
    if (base64Encode(box.ciphertext) != base64Encode(hex(e['ct']))) {
      throw StateError('Vector mismatch');
    }
    final plain = await hpke.open(
      recipient: b,
      senderPublicKey: hex(v['pkSm']),
      enc: box.enc,
      ciphertext: box.ciphertext,
      info: hex(v['info']),
      aad: hex(e['aad']),
    );
    if (base64Encode(plain) != base64Encode(hex(e['pt']))) {
      throw StateError('Roundtrip mismatch');
    }
    var rejected = false;
    try {
      await hpke.open(
        recipient: b,
        senderPublicKey: hex(v['pkSm']),
        enc: box.enc,
        ciphertext: box.ciphertext,
        info: hex(v['info']),
        aad: [0],
      );
    } on Exception {
      rejected = true;
    }
    if (!rejected) throw StateError('Tamper accepted');
    target.textContent =
        'PASS: RFC 9180 Auth vector, browser decrypt, tamper rejection';
  } on Object {
    target.textContent = 'FAIL: invitation crypto probe (no sensitive output)';
  }
}
