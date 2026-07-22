import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../editor_core/flow_muse_whiteboard_editor.dart' show ImageFile;
import '../../ink_recognition/native_http_client.dart';
import 'collaboration_debug_log.dart';
import 'excalidraw_binary_codec.dart';

abstract interface class CollaborationFileStore {
  Future<CollaborationFileUploadResult> uploadFiles({
    required String roomId,
    required String roomKey,
    required Map<String, Object?> filesJson,
    required Iterable<String> fileIds,
  });

  Future<CollaborationFileLoadResult> loadFiles({
    required String roomId,
    required String roomKey,
    required Iterable<String> fileIds,
  });
}

class CollaborationFileUploadResult {
  const CollaborationFileUploadResult({
    required this.savedFiles,
    required this.erroredFiles,
  });

  final Map<String, Map<String, Object?>> savedFiles;
  final Map<String, Map<String, Object?>> erroredFiles;
}

class CollaborationFileLoadResult {
  const CollaborationFileLoadResult({
    required this.loadedFiles,
    required this.erroredFileIds,
  });

  final Map<String, ImageFile> loadedFiles;
  final Set<String> erroredFileIds;
}

class HttpCollaborationFileStore implements CollaborationFileStore {
  HttpCollaborationFileStore({
    required String serverUrl,
    String? authToken,
    http.Client? client,
    ExcalidrawBinaryCodec? binaryCodec,
  }) : _serverUri = Uri.parse(serverUrl),
       _authToken = authToken,
       _client = client ?? HarmonyAwareHttpClient(readTimeoutMs: 20000),
       _binaryCodec = binaryCodec ?? ExcalidrawBinaryCodec();

  final Uri _serverUri;
  final String? _authToken;
  final http.Client _client;
  final ExcalidrawBinaryCodec _binaryCodec;
  static const int _maxFileBytes = 10 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 20);

  @override
  Future<CollaborationFileUploadResult> uploadFiles({
    required String roomId,
    required String roomKey,
    required Map<String, Object?> filesJson,
    required Iterable<String> fileIds,
  }) async {
    final saved = <String, Map<String, Object?>>{};
    final errored = <String, Map<String, Object?>>{};
    for (final fileId in fileIds.toSet()) {
      final file = filesJson[fileId];
      if (file is! Map) {
        continue;
      }
      final fileJson = Map<String, Object?>.from(file);
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
          'id': fileId,
          'mimeType': mimeType,
          'created': DateTime.now().millisecondsSinceEpoch,
          'lastRetrieved': DateTime.now().millisecondsSinceEpoch,
        },
      );
      CollaborationDebugLog.write('file', 'upload_prepare', {
        'room': _shortRoomId(roomId),
        'file': _shortFileId(fileId),
        'mimeType': mimeType,
        'dataUrlBytes': utf8.encode(dataUrl).length,
        'encodedBytes': encodedFile.length,
      });
      if (encodedFile.length > _maxFileBytes) {
        errored[fileId] = fileJson;
        CollaborationDebugLog.write('file', 'upload_too_big', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
          'encodedBytes': encodedFile.length,
        });
        continue;
      }
      try {
        final response = await _client
            .put(
              _roomFileUri(roomId, fileId),
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': '${encodedFile.length}',
                'Cache-Control': 'public, max-age=31536000',
                if (_authToken != null && _authToken.isNotEmpty)
                  'Authorization': 'Bearer $_authToken',
              },
              body: encodedFile,
            )
            .timeout(_requestTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          errored[fileId] = fileJson;
          CollaborationDebugLog.write('file', 'upload_failed', {
            'room': _shortRoomId(roomId),
            'file': _shortFileId(fileId),
            'statusCode': response.statusCode,
          });
          continue;
        }
        saved[fileId] = fileJson;
        CollaborationDebugLog.write('file', 'upload_ok', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
          'encodedBytes': encodedFile.length,
        });
      } catch (error) {
        errored[fileId] = fileJson;
        CollaborationDebugLog.write('file', 'upload_error', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
          'error': error,
        });
      }
    }
    return CollaborationFileUploadResult(
      savedFiles: saved,
      erroredFiles: errored,
    );
  }

  @override
  Future<CollaborationFileLoadResult> loadFiles({
    required String roomId,
    required String roomKey,
    required Iterable<String> fileIds,
  }) async {
    final loaded = <String, ImageFile>{};
    final errored = <String>{};
    for (final fileId in fileIds.toSet()) {
      try {
        CollaborationDebugLog.write('file', 'load_prepare', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
        });
        final response = await _client
            .get(_roomFileUri(roomId, fileId), headers: _headers())
            .timeout(_requestTimeout);
        if (response.statusCode >= 400) {
          errored.add(fileId);
          CollaborationDebugLog.write('file', 'load_failed', {
            'room': _shortRoomId(roomId),
            'file': _shortFileId(fileId),
            'statusCode': response.statusCode,
          });
          continue;
        }
        final decoded = await _binaryCodec.decompressData(
          buffer: Uint8List.fromList(response.bodyBytes),
          decryptionKey: roomKey,
        );
        final dataUrl = utf8.decode(decoded.data);
        final comma = dataUrl.indexOf(',');
        if (comma < 0) {
          errored.add(fileId);
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
        CollaborationDebugLog.write('file', 'load_ok', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
          'mimeType': mimeType,
        });
      } catch (error) {
        errored.add(fileId);
        CollaborationDebugLog.write('file', 'load_error', {
          'room': _shortRoomId(roomId),
          'file': _shortFileId(fileId),
          'error': error,
        });
      }
    }
    return CollaborationFileLoadResult(
      loadedFiles: loaded,
      erroredFileIds: errored,
    );
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

  Map<String, String> _headers() {
    return {
      if (_authToken != null && _authToken.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  String _shortRoomId(String roomId) =>
      roomId.length > 8 ? roomId.substring(0, 8) : roomId;

  String _shortFileId(String fileId) =>
      fileId.length > 8 ? fileId.substring(0, 8) : fileId;
}
