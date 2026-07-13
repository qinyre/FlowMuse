import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/excalidraw_scene.dart';
import 'collaboration_debug_log.dart';
import 'collaboration_crypto.dart';
import 'scene_reconciler.dart';

abstract interface class EncryptedSceneStore {
  Future<CollaborationRoomMetadata> loadMetadata(CollaborationRoom room);

  Future<CollaborationRoomMetadata> joinRoom(CollaborationRoom room);

  Future<CollaborationRoomMetadata> endRoom(
    CollaborationRoom room, {
    String? ownerKey,
  });

  Future<ExcalidrawScene?> loadScene(CollaborationRoom room);

  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  });

  Future<void> createRoom({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
    required String ownerKeyHash,
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
  final Set<String> _endedRooms = {};

  @override
  Future<CollaborationRoomMetadata> loadMetadata(CollaborationRoom room) async {
    return CollaborationRoomMetadata(
      roomId: room.roomId,
      role: CollaborationRoomRole.owner,
      ended: _endedRooms.contains(room.roomId),
    );
  }

  @override
  Future<CollaborationRoomMetadata> joinRoom(CollaborationRoom room) {
    return loadMetadata(room);
  }

  @override
  Future<CollaborationRoomMetadata> endRoom(
    CollaborationRoom room, {
    String? ownerKey,
  }) async {
    _endedRooms.add(room.roomId);
    return loadMetadata(room);
  }

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
    required String ownerKeyHash,
  }) {
    return saveScene(room: room, scene: scene);
  }
}

class HttpEncryptedSceneStore implements EncryptedSceneStore {
  HttpEncryptedSceneStore({
    required String serverUrl,
    required CollaborationCrypto crypto,
    String? authToken,
    http.Client? client,
    SceneReconciler? reconciler,
  }) : _serverUri = Uri.parse(serverUrl),
       _crypto = crypto,
       _authToken = authToken,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _reconciler = reconciler ?? SceneReconciler();

  final Uri _serverUri;
  final CollaborationCrypto _crypto;
  final String? _authToken;
  http.Client _client;
  final bool _ownsClient;
  final SceneReconciler _reconciler;
  final Map<String, _SceneSnapshotMeta> _snapshotMetaByRoom = {};
  static const Duration _requestTimeout = Duration(seconds: 15);

  @override
  Future<CollaborationRoomMetadata> loadMetadata(CollaborationRoom room) async {
    final response = await _requestWithRetry(
      stage: 'load_metadata',
      request: (headers) =>
          _client.get(_roomAccessUri(room.roomId), headers: headers),
    );
    if (response.statusCode == 410) {
      throw StateError('协作房间已结束');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('加载协作房间信息失败：HTTP ${response.statusCode}');
    }
    return CollaborationRoomMetadata.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  @override
  Future<CollaborationRoomMetadata> joinRoom(CollaborationRoom room) async {
    final response = await _requestWithRetry(
      stage: 'join_room',
      request: (headers) =>
          _client.post(_roomJoinUri(room.roomId), headers: headers),
    );
    if (response.statusCode == 410) {
      throw StateError('协作房间已结束');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('加入协作房间失败：HTTP ${response.statusCode}');
    }
    return CollaborationRoomMetadata.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  @override
  Future<CollaborationRoomMetadata> endRoom(
    CollaborationRoom room, {
    String? ownerKey,
  }) async {
    final response = await _requestWithRetry(
      stage: 'end_room',
      request: (headers) => _client.post(
        _roomEndUri(room.roomId),
        headers: headers,
        body: jsonEncode({'ownerKey': ?ownerKey}),
      ),
    );
    if (response.statusCode == 401) {
      throw StateError('结束协作未授权：HTTP 401 ${_responseMessage(response)}');
    }
    if (response.statusCode == 403) {
      throw StateError('只有房主可以结束协作：${_responseMessage(response)}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '结束协作房间失败：HTTP ${response.statusCode} ${_responseMessage(response)}',
      );
    }
    return CollaborationRoomMetadata.fromJson(
      jsonDecode(response.body) as Map<String, Object?>,
    );
  }

  @override
  Future<ExcalidrawScene?> loadScene(CollaborationRoom room) async {
    final response = await _requestWithRetry(
      stage: 'load_scene',
      request: (headers) =>
          _client.get(_roomSceneUri(room.roomId), headers: headers),
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode == 410) {
      throw StateError('协作房间已结束');
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
    final response = await _requestWithRetry(
      stage: 'save_scene',
      request: (headers) => _client.put(
        _roomSceneUri(room.roomId),
        headers: headers,
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
      ),
    );
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
    required String ownerKeyHash,
  }) async {
    final payload = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: utf8.encode(scene.toCollaborationContent()),
    );
    await _createRoomMetadata(room.roomId, ownerKeyHash: ownerKeyHash);
    final response = await _requestWithRetry(
      stage: 'create_scene',
      request: (headers) => _client.post(
        _roomSceneUri(room.roomId),
        headers: headers,
        body: jsonEncode({
          'sceneVersion': _reconciler.getSceneVersion(scene.elements),
          'sceneHash': scene.collaborationHash(),
          'ownerKeyHash': ownerKeyHash,
          'encryptedBuffer': base64Encode(payload.encryptedBuffer),
          'iv': base64Encode(payload.iv),
        }),
      ),
    );
    if (response.statusCode == 409) {
      _snapshotMetaByRoom[room.roomId] = _SceneSnapshotMeta(
        sceneVersion: _reconciler.getSceneVersion(scene.elements),
        sceneHash: scene.collaborationHash(),
      );
      return;
    }
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

  Uri _roomJoinUri(String roomId) {
    return _serverUri.replace(
      path: _joinPath(_serverUri.path, '/api/rooms/$roomId/join'),
    );
  }

  Uri _roomAccessUri(String roomId) {
    return _serverUri.replace(
      path: _joinPath(_serverUri.path, '/api/rooms/$roomId/access'),
    );
  }

  Uri _roomEndUri(String roomId) {
    return _serverUri.replace(
      path: _joinPath(_serverUri.path, '/api/rooms/$roomId/end'),
    );
  }

  Future<void> _createRoomMetadata(
    String roomId, {
    required String ownerKeyHash,
  }) async {
    final response = await _requestWithRetry(
      stage: 'create_metadata',
      request: (headers) => _client.post(
        _serverUri.replace(path: _joinPath(_serverUri.path, '/api/rooms')),
        headers: headers,
        body: jsonEncode({'roomId': roomId, 'ownerKeyHash': ownerKeyHash}),
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('创建协作房间元数据失败：HTTP ${response.statusCode}');
    }
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_authToken != null && _authToken.isNotEmpty)
        'Authorization': 'Bearer $_authToken',
    };
  }

  Future<http.Response> _requestWithRetry({
    required String stage,
    required Future<http.Response> Function(Map<String, String> headers)
    request,
  }) async {
    Future<http.Response> send({bool closeConnection = false}) {
      return request({
        ..._headers(),
        if (closeConnection) 'Connection': 'close',
      }).timeout(_requestTimeout);
    }

    try {
      return await send();
    } on TimeoutException {
      CollaborationDebugLog.write('http', 'request_timeout_retry', {
        'stage': stage,
        'authenticated': _authToken?.isNotEmpty == true,
      });
      if (_ownsClient) {
        _client.close();
        _client = http.Client();
      }
      return send(closeConnection: true);
    }
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase$suffix';
  }

  String _responseMessage(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) {
      return '无响应正文';
    }
    return body;
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
