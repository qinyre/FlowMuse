import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/excalidraw_scene.dart';
import 'collaboration_crypto.dart';
import 'scene_reconciler.dart';

abstract interface class EncryptedSceneStore {
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room);

  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  });
}

class MemoryEncryptedSceneStore implements EncryptedSceneStore {
  final Map<String, ExcalidrawScene> _scenes = {};

  @override
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room) async {
    return _scenes[room.roomId];
  }

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    _scenes[room.roomId] = ExcalidrawScene.fromCollaborationPayload(
      scene.toCollaborationPayload(),
    );
  }
}

class HttpEncryptedSceneStore implements EncryptedSceneStore {
  HttpEncryptedSceneStore({
    required String serverUrl,
    required CollaborationCrypto crypto,
    http.Client? client,
    SceneReconciler? reconciler,
  }) : _serverUri = Uri.parse(serverUrl),
       _crypto = crypto,
       _client = client ?? http.Client(),
       _reconciler = reconciler ?? SceneReconciler();

  final Uri _serverUri;
  final CollaborationCrypto _crypto;
  final http.Client _client;
  final SceneReconciler _reconciler;

  @override
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room) async {
    final response = await _client.get(_roomSceneUri(room.roomId));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Load scene failed: HTTP ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final payload = EncryptedPayload.fromJson({
      'encryptedBuffer': base64Decode(json['encryptedBuffer']! as String),
      'iv': base64Decode(json['iv']! as String),
    });
    final bytes = await _crypto.decrypt(
      roomKey: room.roomKey,
      encryptedPayload: payload,
    );
    return ExcalidrawScene.fromCollaborationPayload(
      jsonDecode(utf8.decode(bytes)),
    );
  }

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    final payload = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: utf8.encode(scene.toCollaborationContent()),
    );
    final response = await _client.put(
      _roomSceneUri(room.roomId),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sceneVersion': _reconciler.getSceneVersion(scene.elements),
        'encryptedBuffer': base64Encode(payload.encryptedBuffer),
        'iv': base64Encode(payload.iv),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Save scene failed: HTTP ${response.statusCode}');
    }
  }

  Uri _roomSceneUri(String roomId) {
    return _serverUri.replace(
      path: _joinPath(_serverUri.path, '/api/rooms/$roomId/scene'),
    );
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$suffix';
  }
}
