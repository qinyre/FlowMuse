import 'dart:convert';
import 'dart:typed_data';

import '../../core/io/io.dart';
import '../../core/scene/scene_exports.dart';
import '../../core/serialization/serialization.dart';
import 'zlib_inflate.dart';

/// Utility for embedding and extracting `.markdraw` data in PNG tEXt chunks.
///
/// PNG files consist of an 8-byte signature followed by chunks.
/// Each chunk is: 4-byte length + 4-byte type + data + 4-byte CRC32.
/// The `tEXt` chunk stores key-value metadata as: keyword + NUL + text.
///
/// This class injects a `tEXt` chunk with keyword `markdraw` containing
/// base64-encoded `.markdraw` serialization of the scene, enabling
/// lossless round-trip: export a PNG, then re-import the full scene.
class PngMetadata {
  static const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const _keyword = 'markdraw';
  static const _excalidrawKeyword = 'application/vnd.excalidraw+json';

  /// Injects a PNG `tEXt` chunk with the given [keyword] and [value].
  ///
  /// The chunk is inserted just before the IEND chunk.
  /// Returns null if [pngBytes] is not a valid PNG.
  static Uint8List? injectTextChunk(
    Uint8List pngBytes,
    String keyword,
    String value,
  ) {
    if (!_isPng(pngBytes)) return null;

    // Find IEND chunk position
    final iendOffset = _findChunkOffset(pngBytes, 'IEND');
    if (iendOffset == null) return null;

    // Build tEXt chunk data: keyword + NUL + text
    final keyBytes = utf8.encode(keyword);
    final valBytes = latin1.encode(value);
    final chunkData = Uint8List(keyBytes.length + 1 + valBytes.length);
    chunkData.setAll(0, keyBytes);
    chunkData[keyBytes.length] = 0; // NUL separator
    chunkData.setAll(keyBytes.length + 1, valBytes);

    // Build full chunk: length + type + data + CRC
    final chunkBytes = _buildChunk('tEXt', chunkData);

    // Assemble: everything before IEND + tEXt chunk + IEND chunk
    final builder = BytesBuilder();
    builder.add(pngBytes.sublist(0, iendOffset));
    builder.add(chunkBytes);
    builder.add(pngBytes.sublist(iendOffset));
    return builder.toBytes();
  }

  /// Extracts the text value for a `tEXt` chunk with the given [keyword].
  ///
  /// Returns null if the PNG has no matching tEXt chunk or is not valid PNG.
  static String? extractTextChunk(Uint8List pngBytes, String keyword) {
    if (!_isPng(pngBytes)) return null;

    int offset = 8; // skip signature

    while (offset + 8 <= pngBytes.length) {
      final length = _readUint32(pngBytes, offset);
      final type = String.fromCharCodes(pngBytes, offset + 4, offset + 8);

      if (type == 'tEXt' && offset + 8 + length <= pngBytes.length) {
        final data = pngBytes.sublist(offset + 8, offset + 8 + length);
        // Find NUL separator
        final nulIndex = data.indexOf(0);
        if (nulIndex >= 0) {
          final chunkKeyword = utf8.decode(data.sublist(0, nulIndex));
          if (chunkKeyword == keyword) {
            return latin1.decode(data.sublist(nulIndex + 1));
          }
        }
      }

      if (type == 'IEND') break;
      // Move to next chunk: length(4) + type(4) + data(length) + crc(4)
      offset += 12 + length;
    }
    return null;
  }

  /// Embeds the full scene as base64-encoded `.markdraw` data in a PNG tEXt chunk.
  ///
  /// Returns null if [pngBytes] is not valid PNG.
  static Uint8List? embedMarkdrawData(Uint8List pngBytes, Scene scene) {
    final doc = SceneDocumentConverter.sceneToDocument(scene);
    final markdrawContent = DocumentSerializer.serialize(doc);
    final base64Data = base64Encode(utf8.encode(markdrawContent));
    return injectTextChunk(pngBytes, _keyword, base64Data);
  }

  /// Extracts a [Scene] from a PNG's embedded `.markdraw` tEXt chunk.
  ///
  /// Returns null if no markdraw data is found or the PNG is invalid.
  static Scene? extractMarkdrawData(Uint8List pngBytes) {
    final base64Data = extractTextChunk(pngBytes, _keyword);
    if (base64Data == null) return null;

    try {
      final markdrawContent = utf8.decode(base64Decode(base64Data));
      final parsed = DocumentParser.parse(markdrawContent);
      return SceneDocumentConverter.documentToScene(parsed.value);
    } catch (_) {
      return null;
    }
  }

  /// Extracts a [Scene] from a PNG's embedded Excalidraw tEXt chunk.
  ///
  /// Supports both legacy v1 (raw JSON) and v2 (encoded/compressed wrapper).
  /// Returns null if no Excalidraw data is found, the PNG is invalid,
  /// or the data cannot be decoded.
  static Scene? extractExcalidrawData(Uint8List pngBytes) {
    final rawText = extractTextChunk(pngBytes, _excalidrawKeyword);
    if (rawText == null) return null;

    try {
      final json = _decodeExcalidrawPayload(rawText);
      if (json == null) return null;
      final parsed = ExcalidrawJsonCodec.parse(json);
      return SceneDocumentConverter.documentToScene(parsed.value);
    } catch (_) {
      return null;
    }
  }

  /// Decodes an Excalidraw tEXt chunk payload to a JSON string.
  ///
  /// V1 (legacy): the raw text is the Excalidraw scene JSON directly.
  /// V2 (current): the raw text is a JSON wrapper with `encoded`, `encoding`,
  /// `compressed`, and `version` fields.
  static String? _decodeExcalidrawPayload(String rawText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawText);
    } catch (_) {
      return null;
    }

    if (decoded is! Map<String, Object?>) return null;

    // V1: raw Excalidraw scene JSON (has "type": "excalidraw")
    if (decoded['type'] == 'excalidraw') return rawText;

    // V2: encoded wrapper
    final encoded = decoded['encoded'];
    final compressed = decoded['compressed'];
    if (encoded is! String) return null;

    // Convert Latin-1 byte string back to raw bytes
    final bytes = Uint8List.fromList(
      encoded.codeUnits.map((c) => c & 0xFF).toList(),
    );

    if (compressed == true) {
      try {
        final decompressed = zlibInflate(bytes);
        return utf8.decode(decompressed);
      } catch (_) {
        return null;
      }
    } else {
      return utf8.decode(bytes);
    }
  }

  static bool _isPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  /// Finds the byte offset of a chunk with the given [type].
  static int? _findChunkOffset(Uint8List bytes, String type) {
    int offset = 8; // skip signature
    while (offset + 8 <= bytes.length) {
      final length = _readUint32(bytes, offset);
      final chunkType = String.fromCharCodes(bytes, offset + 4, offset + 8);
      if (chunkType == type) return offset;
      offset += 12 + length;
    }
    return null;
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static Uint8List _buildChunk(String type, Uint8List data) {
    final typeBytes = utf8.encode(type);
    final length = data.length;

    // CRC is computed over type + data
    final crcInput = Uint8List(4 + data.length);
    crcInput.setAll(0, typeBytes);
    crcInput.setAll(4, data);
    final crc = _crc32(crcInput);

    final chunk = Uint8List(12 + data.length);
    // Length (big-endian)
    chunk[0] = (length >> 24) & 0xFF;
    chunk[1] = (length >> 16) & 0xFF;
    chunk[2] = (length >> 8) & 0xFF;
    chunk[3] = length & 0xFF;
    // Type
    chunk.setAll(4, typeBytes);
    // Data
    chunk.setAll(8, data);
    // CRC (big-endian)
    chunk[8 + data.length] = (crc >> 24) & 0xFF;
    chunk[9 + data.length] = (crc >> 16) & 0xFF;
    chunk[10 + data.length] = (crc >> 8) & 0xFF;
    chunk[11 + data.length] = crc & 0xFF;

    return chunk;
  }

  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
