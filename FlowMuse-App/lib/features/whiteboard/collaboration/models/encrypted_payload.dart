import 'dart:convert';

class EncryptedPayload {
  const EncryptedPayload({required this.encryptedBuffer, required this.iv});

  final List<int> encryptedBuffer;
  final List<int> iv;

  Map<String, Object?> toJson() {
    return {'encryptedBuffer': encryptedBuffer, 'iv': iv};
  }

  factory EncryptedPayload.fromJson(Map<String, Object?> json) {
    return EncryptedPayload(
      encryptedBuffer: _bytes(json['encryptedBuffer']),
      iv: _bytes(json['iv']),
    );
  }

  static List<int> _bytes(Object? value) {
    if (value is List<int>) {
      return value;
    }
    if (value is List) {
      return [for (final item in value) (item as num).toInt()];
    }
    if (value is String) {
      return base64Decode(value);
    }
    throw FormatException('Invalid encrypted payload bytes: $value');
  }
}
