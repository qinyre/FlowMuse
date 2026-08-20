import 'encrypted_payload.dart';

class ReceivedLiveInkFrame {
  const ReceivedLiveInkFrame({
    required this.senderSocketId,
    required this.payload,
  });

  final String senderSocketId;
  final EncryptedPayload payload;
}
