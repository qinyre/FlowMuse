class EncryptedPayload {
  const EncryptedPayload({
    required this.cipherText,
    required this.iv,
    required this.mac,
  });

  final List<int> cipherText;
  final List<int> iv;
  final List<int> mac;
}
