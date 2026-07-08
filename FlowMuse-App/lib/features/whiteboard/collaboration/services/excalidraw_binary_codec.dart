import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/encrypted_payload.dart';
import 'collaboration_crypto.dart';

class ExcalidrawDecodedBinary {
  const ExcalidrawDecodedBinary({required this.metadata, required this.data});

  final Map<String, Object?>? metadata;
  final Uint8List data;
}

class ExcalidrawBinaryCodec {
  ExcalidrawBinaryCodec({CollaborationCrypto? crypto})
    : _crypto = crypto ?? CollaborationCrypto();

  static const int _concatBuffersVersion = 1;
  static const int _uint32Bytes = 4;

  final CollaborationCrypto _crypto;

  Future<Uint8List> compressData({
    required Uint8List data,
    required String encryptionKey,
    Map<String, Object?>? metadata,
  }) async {
    final encodingMetadata = utf8.encode(
      jsonEncode({
        'version': 2,
        'compression': 'pako@1',
        'encryption': 'AES-GCM',
      }),
    );
    final contentsMetadata = utf8.encode(jsonEncode(metadata));
    final contents = _concatBuffers([contentsMetadata, data]);
    final compressed = Uint8List.fromList(
      const ZLibEncoder().encodeBytes(contents),
    );
    final encrypted = await _crypto.encrypt(
      roomKey: encryptionKey,
      plainBytes: compressed,
    );
    return _concatBuffers([
      encodingMetadata,
      encrypted.iv,
      encrypted.encryptedBuffer,
    ]);
  }

  Future<ExcalidrawDecodedBinary> decompressData({
    required Uint8List buffer,
    required String decryptionKey,
  }) async {
    final chunks = _splitBuffers(buffer);
    if (chunks.length != 3) {
      throw const FormatException('Invalid Excalidraw binary chunk count');
    }

    final encodingMetadata =
        jsonDecode(utf8.decode(chunks[0])) as Map<String, Object?>;
    if (encodingMetadata['encryption'] != 'AES-GCM') {
      throw FormatException(
        'Unsupported Excalidraw file encryption: '
        '${encodingMetadata['encryption']}',
      );
    }

    final decrypted = await _crypto.decrypt(
      roomKey: decryptionKey,
      encryptedPayload: EncryptedPayload(
        encryptedBuffer: chunks[2],
        iv: chunks[1],
      ),
    );
    final decompressed = Uint8List.fromList(
      const ZLibDecoder().decodeBytes(decrypted),
    );
    final contents = _splitBuffers(decompressed);
    if (contents.length != 2) {
      throw const FormatException('Invalid Excalidraw file contents');
    }

    final metadata = jsonDecode(utf8.decode(contents[0]));
    return ExcalidrawDecodedBinary(
      metadata: metadata is Map ? Map<String, Object?>.from(metadata) : null,
      data: contents[1],
    );
  }

  static Uint8List _concatBuffers(List<List<int>> buffers) {
    final length =
        _uint32Bytes +
        buffers.length * _uint32Bytes +
        buffers.fold<int>(0, (sum, buffer) => sum + buffer.length);
    final result = Uint8List(length);
    var cursor = 0;
    _writeUint32(result, cursor, _concatBuffersVersion);
    cursor += _uint32Bytes;
    for (final buffer in buffers) {
      _writeUint32(result, cursor, buffer.length);
      cursor += _uint32Bytes;
      result.setRange(cursor, cursor + buffer.length, buffer);
      cursor += buffer.length;
    }
    return result;
  }

  static List<Uint8List> _splitBuffers(Uint8List buffer) {
    var cursor = 0;
    final version = _readUint32(buffer, cursor);
    if (version > _concatBuffersVersion) {
      throw FormatException('Unsupported Excalidraw concat version $version');
    }
    cursor += _uint32Bytes;

    final chunks = <Uint8List>[];
    while (cursor < buffer.length) {
      final chunkSize = _readUint32(buffer, cursor);
      cursor += _uint32Bytes;
      final nextCursor = cursor + chunkSize;
      if (nextCursor > buffer.length) {
        throw const FormatException('Invalid Excalidraw binary chunk size');
      }
      chunks.add(Uint8List.fromList(buffer.sublist(cursor, nextCursor)));
      cursor = nextCursor;
    }
    return chunks;
  }

  static void _writeUint32(Uint8List target, int offset, int value) {
    ByteData.sublistView(target).setUint32(offset, value);
  }

  static int _readUint32(Uint8List source, int offset) {
    if (offset + _uint32Bytes > source.length) {
      throw const FormatException('Unexpected end of Excalidraw binary data');
    }
    return ByteData.sublistView(source).getUint32(offset);
  }
}
