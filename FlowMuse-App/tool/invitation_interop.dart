// Test data only. Usage: dart run --no-enable-asserts tool/invitation_interop.dart emit|verify FILE
import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flow_muse/features/social/services/hpke_auth.dart';

Future<void> main(List<String> args) async {
  final hpke = HpkeAuth();
  final x = X25519();
  if (args.length != 2) throw ArgumentError('Use emit|verify FILE');
  if (args[0] == 'emit') {
    final vectors = <Map<String, dynamic>>[];
    for (var i = 0; i < 16; i++) {
      final a = await x.newKeyPairFromSeed(
        List.generate(32, (n) => (n + i) % 256),
      );
      final b = await x.newKeyPairFromSeed(
        List.generate(32, (n) => (n + i + 70) % 256),
      );
      final info = utf8.encode('FlowMuse/room-invite/v1');
      final aad = utf8.encode('test-context-$i');
      final plaintext = utf8.encode('public-interop-fixture-$i');
      final box = await hpke.seal(
        sender: a,
        recipientPublicKey: (await b.extractPublicKey()).bytes,
        info: info,
        aad: aad,
        plaintext: plaintext,
      );
      vectors.add({
        'senderPrivate': base64Encode((await a.extract()).bytes),
        'recipientPrivate': base64Encode((await b.extract()).bytes),
        'info': base64Encode(info),
        'aad': base64Encode(aad),
        'plaintext': base64Encode(plaintext),
        'enc': base64Encode(box.enc),
        'ciphertext': base64Encode(box.ciphertext),
      });
    }
    await File(args[1]).writeAsString(jsonEncode(vectors));
    stdout.writeln('16 public test vectors written');
  } else if (args[0] == 'verify') {
    final vectors = jsonDecode(await File(args[1]).readAsString()) as List;
    if (vectors.length != 16) throw StateError('Unexpected vector count');
    for (final v in vectors) {
      final a = await x.newKeyPairFromSeed(base64Decode(v['senderPrivate']));
      final b = await x.newKeyPairFromSeed(base64Decode(v['recipientPrivate']));
      final plain = await hpke.open(
        recipient: b,
        senderPublicKey: (await a.extractPublicKey()).bytes,
        info: base64Decode(v['info']),
        aad: base64Decode(v['aad']),
        enc: base64Decode(v['enc']),
        ciphertext: base64Decode(v['ciphertext']),
      );
      if (base64Encode(plain) != v['plaintext']) {
        throw StateError('Interop mismatch');
      }
    }
    stdout.writeln('CIRCL -> Dart: 16 Auth vectors passed');
  } else {
    throw ArgumentError('Use emit|verify FILE');
  }
}
