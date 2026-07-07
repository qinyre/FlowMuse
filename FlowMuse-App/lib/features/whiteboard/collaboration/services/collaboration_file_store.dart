import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../editor_core/flow_muse_whiteboard_editor.dart' show ImageFile;

abstract interface class CollaborationFileStore {
  Future<void> uploadFiles({
    required String roomId,
    required Map<String, Object?> filesJson,
  });

  Future<Map<String, ImageFile>> loadMissingFiles({
    required String roomId,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  });
}

class HttpCollaborationFileStore implements CollaborationFileStore {
  HttpCollaborationFileStore({required String serverUrl, http.Client? client})
    : _serverUri = Uri.parse(serverUrl),
      _client = client ?? http.Client();

  final Uri _serverUri;
  final http.Client _client;

  @override
  Future<void> uploadFiles({
    required String roomId,
    required Map<String, Object?> filesJson,
  }) async {
    for (final entry in filesJson.entries) {
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
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      final response = await _client.put(
        _roomFileUri(roomId, entry.key),
        headers: {'Content-Type': mimeType, 'Content-Length': '${bytes.length}'},
        body: bytes,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Upload file ${entry.key} failed: HTTP ${response.statusCode}',
        );
      }
    }
  }

  @override
  Future<Map<String, ImageFile>> loadMissingFiles({
    required String roomId,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) async {
    final loaded = <String, ImageFile>{};
    for (final fileId in fileIds.toSet()) {
      if (existingFileIds.contains(fileId)) {
        continue;
      }
      final response = await _client.get(_roomFileUri(roomId, fileId));
      if (response.statusCode == 404) {
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Load file $fileId failed: HTTP ${response.statusCode}');
      }
      loaded[fileId] = ImageFile(
        mimeType: response.headers['content-type'] ?? 'application/octet-stream',
        bytes: Uint8List.fromList(response.bodyBytes),
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
