import 'dart:io';
import 'dart:typed_data';

/// Decompresses zlib-compressed bytes using dart:io's ZLibDecoder.
Uint8List zlibInflate(Uint8List compressed) {
  final decoder = ZLibDecoder();
  return Uint8List.fromList(decoder.convert(compressed));
}
