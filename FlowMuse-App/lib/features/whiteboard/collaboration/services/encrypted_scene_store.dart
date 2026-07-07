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

  Future<void> createRoom({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  });
}

class StaleSceneSnapshotException implements Exception {
  const StaleSceneSnapshotException(this.message);

  final String message;

  @override
  String toString() => message;
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

  @override
  Future<void> createRoom({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) {
    return saveScene(room: room, scene: scene);
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
  final Map<String, _SceneSnapshotMeta> _snapshotMetaByRoom = {};
  static const Duration _requestTimeout = Duration(seconds: 15);

  @override
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room) async {
    final response = await _client
        .get(_roomSceneUri(room.roomId))
        .timeout(_requestTimeout);
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('加载协作房间失败：HTTP ${response.statusCode}');
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
    _snapshotMetaByRoom[room.roomId] = _SceneSnapshotMeta(
      sceneVersion: (json['sceneVersion']! as num).toInt(),
      sceneHash: json['sceneHash']! as String,
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
    final response = await _client
        .put(
          _roomSceneUri(room.roomId),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sceneVersion': _reconciler.getSceneVersion(scene.elements),
            'sceneHash': scene.collaborationHash(),
            if (_snapshotMetaByRoom[room.roomId] case final meta?)
              'baseSceneVersion': meta.sceneVersion,
            if (_snapshotMetaByRoom[room.roomId] case final meta?)
              'baseSceneHash': meta.sceneHash,
            'encryptedBuffer': base64Encode(payload.encryptedBuffer),
            'iv': base64Encode(payload.iv),
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode == 409) {
      throw const StaleSceneSnapshotException('远端场景版本已更新');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('保存协作场景失败：HTTP ${response.statusCode}');
    }
    _snapshotMetaByRoom[room.roomId] = _SceneSnapshotMeta(
      sceneVersion: _reconciler.getSceneVersion(scene.elements),
      sceneHash: scene.collaborationHash(),
    );
  }

  @override
  Future<void> createRoom({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    final payload = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: utf8.encode(scene.toCollaborationContent()),
    );
    final response = await _client
        .post(
          _roomSceneUri(room.roomId),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'sceneVersion': _reconciler.getSceneVersion(scene.elements),
            'sceneHash': scene.collaborationHash(),
            'encryptedBuffer': base64Encode(payload.encryptedBuffer),
            'iv': base64Encode(payload.iv),
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('创建协作房间失败：HTTP ${response.statusCode}');
    }
    _snapshotMetaByRoom[room.roomId] = _SceneSnapshotMeta(
      sceneVersion: _reconciler.getSceneVersion(scene.elements),
      sceneHash: scene.collaborationHash(),
    );
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

class _SceneSnapshotMeta {
  const _SceneSnapshotMeta({
    required this.sceneVersion,
    required this.sceneHash,
  });

  final int sceneVersion;
  final String sceneHash;
}
