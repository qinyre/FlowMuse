import 'dart:typed_data';

/// Binary image data stored in the file store.
class ImageFile {
  final String mimeType;
  final Uint8List bytes;

  const ImageFile({required this.mimeType, required this.bytes});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageFile &&
          mimeType == other.mimeType &&
          _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode => Object.hash(mimeType, bytes.length);

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'ImageFile($mimeType, ${bytes.length} bytes)';
}
