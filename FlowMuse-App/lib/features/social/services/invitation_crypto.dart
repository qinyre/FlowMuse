import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../models/invitation_models.dart';
import 'hpke_auth.dart';

class InvitationCrypto {
  InvitationCrypto({HpkeAuth? hpke}) : _hpke = hpke ?? HpkeAuth();
  final HpkeAuth _hpke;
  static final _info = utf8.encode('FlowMuse/room-invite/v1');

  Future<InvitationEnvelope> seal({
    required InvitationContext context,
    required String roomKey,
    required SimpleKeyPair sender,
    required String recipientPublicKey,
  }) async {
    invitationBytes(roomKey, length: 16);
    final box = await _hpke.seal(
      sender: sender,
      recipientPublicKey: invitationBytes(recipientPublicKey, length: 32),
      info: _info,
      aad: context.aad,
      plaintext: utf8.encode(
        jsonEncode({...context.toJson(), 'roomKey': roomKey}),
      ),
    );
    return InvitationEnvelope(
      context: context,
      enc: invitationBase64(box.enc),
      ciphertext: invitationBase64(box.ciphertext),
    );
  }

  Future<String> open({
    required InvitationEnvelope envelope,
    required InvitationContext expected,
    required SimpleKeyPair recipient,
    required String trustedSenderPublicKey,
    DateTime? now,
  }) async {
    if (jsonEncode(envelope.context.toJson()) !=
            jsonEncode(expected.toJson()) ||
        expected.expiresAt <= (now ?? DateTime.now()).millisecondsSinceEpoch) {
      throw const FormatException('Invitation context changed or expired');
    }
    final plain = await _hpke.open(
      recipient: recipient,
      senderPublicKey: invitationBytes(trustedSenderPublicKey, length: 32),
      enc: invitationBytes(envelope.enc, length: 32),
      ciphertext: invitationBytes(envelope.ciphertext),
      info: _info,
      aad: expected.aad,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final key = json.remove('roomKey');
    if (json.length != expected.toJson().length ||
        expected.toJson().entries.any((e) => json[e.key] != e.value) ||
        key is! String) {
      throw const FormatException('Invitation content mismatch');
    }
    invitationBytes(key, length: 16);
    return key;
  }
}
