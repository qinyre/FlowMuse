import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../editor_core/flow_muse_whiteboard_editor.dart' show ImageFile;
import 'excalidraw_binary_codec.dart';

abstract interface class CollaborationFileStore {
  Future<void> uploadFiles({
    required String roomId,
    required String roomKey,
    required Map<String, Object?> filesJson,
    Set<String>? alreadyUploadedFileIds,
  });

  Future<Map<String, ImageFile>> loadMissingFiles({
    required String roomId,
    required String roomKey,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  });
}

class HttpCollaborationFileStore implements CollaborationFileStore {
  HttpCollaborationFileStore({
    required String serverUrl,
    http.Client? client,
    ExcalidrawBinaryCodec? binaryCodec,
  }) : _serverUri = Uri.parse(serverUrl),
       _client = client ?? http.Client(),
       _binaryCodec = binaryCodec ?? ExcalidrawBinaryCodec();

  final Uri _serverUri;
  final http.Client _client;
  final ExcalidrawBinaryCodec _binaryCodec;
  static const int _maxFileBytes = 10 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 20);

  @override
  Future<void> uploadFiles({
    required String roomId,
    required String roomKey,
    required Map<String, Object?> filesJson,
    Set<String>? alreadyUploadedFileIds,
  }) async {
    for (final entry in filesJson.entries) {
      if (alreadyUploadedFileIds?.contains(entry.key) ?? false) {
        continue;
      }
      final file = entry.value;
      if (file is! Map) {
        continue;
      }
      final dataUrl = file['dataURL'];
      if (dataUrl is! String || dataUrl.isEmpty) {
        continue;
      }
      final comma = dataUrl.indexOf(',');
      if (comma < 0) {
        continue;
      }
      final media = dataUrl.substring(0, comma);
      final mimeType = media.startsWith('data:')
          ? media.substring(5).split(';').first
          : 'application/octet-stream';
      final encodedFile = await _binaryCodec.compressData(
        data: Uint8List.fromList(utf8.encode(dataUrl)),
        encryptionKey: roomKey,
        metadata: {
          'id': entry.key,
          'mimeType': mimeType,
          'created': DateTime.now().millisecondsSinceEpoch,
          'lastRetrieved': DateTime.now().millisecondsSinceEpoch,
        },
      );
      if (encodedFile.length > _maxFileBytes) {
        throw StateError('图片文件 ${entry.key} 超过 10MB 限制');
      }
      final response = await _client
          .put(
            _roomFileUri(roomId, entry.key),
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Length': '${encodedFile.length}',
              'Cache-Control': 'public, max-age=31536000',
            },
            body: encodedFile,
          )
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Upload file ${entry.key} failed: HTTP ${response.statusCode}',
        );
      }
      alreadyUploadedFileIds?.add(entry.key);
    }
  }

  @override
  Future<Map<String, ImageFile>> loadMissingFiles({
    required String roomId,
    required String roomKey,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) async {
    final loaded = <String, ImageFile>{};
    for (final fileId in fileIds.toSet()) {
      if (existingFileIds.contains(fileId)) {
        continue;
      }
      final response = await _client
          .get(_roomFileUri(roomId, fileId))
          .timeout(_requestTimeout);
      if (response.statusCode == 404) {
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Load file $fileId failed: HTTP ${response.statusCode}',
        );
      }
      final decoded = await _binaryCodec.decompressData(
        buffer: Uint8List.fromList(response.bodyBytes),
        decryptionKey: roomKey,
      );
      final dataUrl = utf8.decode(decoded.data);
      final comma = dataUrl.indexOf(',');
      if (comma < 0) {
        continue;
      }
      final media = dataUrl.substring(0, comma);
      final mimeType =
          decoded.metadata?['mimeType'] as String? ??
          (media.startsWith('data:')
              ? media.substring(5).split(';').first
              : 'application/octet-stream');
      loaded[fileId] = ImageFile(
        mimeType: mimeType,
        bytes: Uint8List.fromList(base64Decode(dataUrl.substring(comma + 1))),
      );
    }
    return loaded;
  }

  Uri _roomFileUri(String roomId, String fileId) {
    return _serverUri.replace(
      path: _joinPath(_serverUri.path, '/api/rooms/$roomId/files/$fileId'),
    );
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$suffix';
  }
}
