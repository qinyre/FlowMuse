import 'dart:typed_data';

/// Stub for web — zlib decompression requires dart:io.
Uint8List zlibInflate(Uint8List compressed) {
  throw UnsupportedError('zlib decompression not supported on web');
}
