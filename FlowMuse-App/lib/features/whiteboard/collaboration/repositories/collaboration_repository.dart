import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../models/collaboration_message.dart';
import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/excalidraw_scene.dart';
import '../models/room_collaborator.dart';
import 'collaboration_owner_key_store.dart';
import '../services/collaboration_crypto.dart';
import '../services/collaboration_debug_log.dart';
import '../services/collaboration_file_manager.dart';
import '../services/collaboration_file_store.dart';
import '../services/encrypted_scene_store.dart';
import '../services/realtime_transport.dart';
import '../services/scene_reconciler.dart';

class _VersionRecord {
  const _VersionRecord(this.version, this.versionNonce);
  final int version;
  final int versionNonce;
}

class CollaborationRepository {
  CollaborationRepository({
    RealtimeTransport? transport,
    EncryptedSceneStore? sceneStore,
    CollaborationFileStore? fileStore,
    CollaborationOwnerKeyStore? ownerKeyStore,
    CollaborationCrypto? crypto,
    SceneReconciler? reconciler,
  }) : _transport = transport ?? const DisconnectedRealtimeTransport(),
       _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
       _fileStore = fileStore,
       _ownerKeyStore = ownerKeyStore ?? CollaborationOwnerKeyStore(),
       _crypto = crypto ?? CollaborationCrypto(),
       _reconciler = reconciler ?? SceneReconciler();

  static const Duration fullSceneSyncInterval = Duration(seconds: 20);
  static const Duration fileUploadTimeout = Duration(milliseconds: 300);

  final RealtimeTransport _transport;
  final EncryptedSceneStore _sceneStore;
  final CollaborationFileStore? _fileStore;
  final CollaborationOwnerKeyStore _ownerKeyStore;
  final CollaborationCrypto _crypto;
  final SceneReconciler _reconciler;
  final CollaborationFileManager _fileManager = CollaborationFileManager();
  final math.Random _random = math.Random();
  final Map<String, _VersionRecord> _broadcastedElementVersions = {};
  final StreamController<String> _repositoryErrors =
      StreamController<String>.broadcast();
  final StreamController<CollaborationMessage> _messages =
      StreamController<CollaborationMessage>.broadcast();
  final StreamController<ExcalidrawScene> _fileStatusScenes =
      StreamController<ExcalidrawScene>.broadcast();
  final List<CollaborationMessage> _messageBacklog = [];

  Timer? _fullSceneSyncTimer;
  Timer? _fileUploadTimer;
  StreamSubscription<EncryptedPayload>? _transportMessageSubscription;
  StreamSubscription<String>? _newUserSubscription;
  Future<void> _messageDecodeQueue = Future<void>.value();
  CollaborationRoom? _activeRoom;
  ExcalidrawScene _latestScene = ExcalidrawScene.empty();
  int _lastBroadcastedOrReceivedSceneVersion = 0;

  String get socketId => _transport.socketId ?? 'local-client';

  Stream<String> get newUsers => _transport.newUsers;

  Stream<List<RoomCollaborator>> get roomUsers => _transport.roomUsers;

  Stream<CollaborationRoomMetadata> get roomEnded => _transport.roomEnded;

  Stream<void> get firstInRoom => _transport.firstInRoom;

  Stream<String> get errors {
    return Stream.multi((controller) {
      final transportErrors = _transport.errors.listen(controller.add);
      final repositoryErrors = _repositoryErrors.stream.listen(controller.add);
      controller.onCancel = () async {
        await transportErrors.cancel();
        await repositoryErrors.cancel();
      };
    });
  }

  Stream<RealtimeConnectionStatus> get connectionStatus =>
      _transport.connectionStatus;

  Stream<CollaborationMessage> encryptedMessages(CollaborationRoom room) {
    return Stream.multi((controller) {
      if (_activeRoom?.roomId != room.roomId) {
        controller.close();
        return;
      }
      final pending = List<CollaborationMessage>.of(_messageBacklog);
      _messageBacklog.clear();
      for (final message in pending) {
        controller.add(message);
      }
      final subscription = _messages.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  Stream<ExcalidrawScene> get fileStatusScenes => _fileStatusScenes.stream;

  Future<CollaborationRoom> startNewRoom({
    required ExcalidrawScene initialScene,
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    final ownerKey = _crypto.generateRoomKey();
    final ownerKeyHash = _crypto.hashOwnerKey(
      roomId: room.roomId,
      ownerKey: ownerKey,
    );
    final roomScene = _markSavedImagesPending(initialScene);
    final syncableScene = roomScene.copyWith(
      elements: _reconciler.getSyncableElements(roomScene.elements),
    );
    await _sceneStore.createRoom(
      room: room,
      scene: syncableScene.copyWith(files: const {}),
      ownerKeyHash: ownerKeyHash,
    );
    await _ownerKeyStore.writeOwnerKey(room.roomId, ownerKey);
    _activeRoom = room;
    _latestScene = syncableScene;
    _rememberBroadcasted(syncableScene.elements);
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      syncableScene.elements,
    );
    CollaborationDebugLog.write('repo', 'start_room', {
      'room': _shortRoomId(room.roomId),
      'elements': syncableScene.elements.length,
      'sceneVersion': _reconciler.getSceneVersion(syncableScene.elements),
      'summary': CollaborationDebugLog.elementSummary(syncableScene.elements),
    });
    _startRoomSession(room);
    try {
      await _transport.connect(room.roomId);
    } catch (_) {
      _resetLocalState();
      rethrow;
    }
    await _send(
      room: room,
      message: CollaborationMessage.sceneInit(elements: syncableScene.elements),
    );
    _scheduleFileUpload(room);
    _startFullSceneSync();
    return room;
  }

  Future<CollaborationRoomMetadata> loadMetadata(CollaborationRoom room) {
    return _sceneStore.loadMetadata(room);
  }

  Future<CollaborationJoinResult> joinRoom({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
  }) async {
    final storedScene = await _sceneStore.loadScene(room);
    if (storedScene == null) {
      throw StateError('房间不存在或尚未创建');
    }
    final metadata = await _sceneStore.joinRoom(room);
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(storedScene.elements),
    );
    _latestScene = nextScene;
    _rememberBroadcasted(nextScene.elements);
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      nextScene.elements,
    );
    _activeRoom = room;
    CollaborationDebugLog.write('repo', 'join_room', {
      'room': _shortRoomId(room.roomId),
      'localElements': localScene.elements.length,
      'storedElements': storedScene.elements.length,
      'mergedElements': 0,
      'joinedElements': nextScene.elements.length,
      'sceneVersion': _reconciler.getSceneVersion(nextScene.elements),
      'summary': CollaborationDebugLog.elementSummary(nextScene.elements),
    });
    _startRoomSession(room);
    try {
      await _transport.connect(room.roomId);
    } catch (_) {
      _resetLocalState();
      rethrow;
    }
    _startFullSceneSync();
    return CollaborationJoinResult(scene: nextScene, metadata: metadata);
  }

  Future<CollaborationRoomMetadata> endRoom() async {
    final room = _activeRoom;
    if (room == null) {
      throw StateError('协作连接未建立');
    }
    final ownerKey = await _ownerKeyStore.readOwnerKey(room.roomId);
    if (ownerKey == null || ownerKey.isEmpty) {
      throw StateError('本机缺少房主密钥，无法结束协作');
    }
    final metadata = await _sceneStore.endRoom(room, ownerKey: ownerKey);
    try {
      await _transport.endRoom(ownerKey: ownerKey);
    } catch (_) {}
    await _ownerKeyStore.clearOwnerKey(room.roomId);
    _resetLocalState();
    return metadata;
  }

  Future<ExcalidrawScene?> refreshFromSnapshot({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
  }) async {
    final storedScene = await _sceneStore.loadScene(room);
    if (storedScene == null) {
      return null;
    }
    final reconciledElements = _reconciler.reconcile(
      localElements: localScene.elements,
      remoteElements: storedScene.elements,
    );
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(reconciledElements),
      files: {...localScene.files, ...storedScene.files},
    );
    _latestScene = nextScene;
    _rememberBroadcasted(nextScene.elements);
    return nextScene;
  }

  Future<void> broadcastScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
    bool initial = false,
    bool syncAll = false,
  }) async {
    final syncableElements = _reconciler.getSyncableElements(scene.elements);
    final syncableScene = scene.copyWith(elements: syncableElements);
    _latestScene = syncableScene;
    final sceneVersion = _reconciler.getSceneVersion(syncableElements);
    if (!initial &&
        !syncAll &&
        sceneVersion <= _lastBroadcastedOrReceivedSceneVersion) {
      CollaborationDebugLog.write('scene', 'broadcast_gate_skipped', {
        'room': _shortRoomId(room.roomId),
        'sceneVersion': sceneVersion,
        'lastVersion': _lastBroadcastedOrReceivedSceneVersion,
      });
      _scheduleFileUpload(room);
      return;
    }

    final elementsToBroadcast = initial || syncAll
        ? syncableElements
        : _changedElements(syncableElements);
    CollaborationDebugLog.write('scene', 'broadcast_prepare', {
      'room': _shortRoomId(room.roomId),
      'initial': initial,
      'syncAll': syncAll,
      'syncable': syncableElements.length,
      'changed': elementsToBroadcast.length,
      'sceneVersion': sceneVersion,
      'summary': CollaborationDebugLog.elementSummary(elementsToBroadcast),
    });
    _scheduleFileUpload(room);
    if (elementsToBroadcast.isEmpty && !initial) {
      return;
    }

    final message = initial
        ? CollaborationMessage.sceneInit(elements: elementsToBroadcast)
        : CollaborationMessage.sceneUpdate(elements: elementsToBroadcast);
    await _send(room: room, message: message);
    _rememberBroadcasted(elementsToBroadcast);
    _lastBroadcastedOrReceivedSceneVersion = sceneVersion;
    _latestScene = syncableScene;
    unawaited(_saveSceneSnapshot(room: room, scene: syncableScene));
  }

  Future<void> broadcastMouseLocation({
    required CollaborationRoom room,
    required Map<String, Object?> pointer,
    required String button,
    required Map<String, bool> selectedElementIds,
    required String username,
    String? userId,
    String? avatarUrl,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.mouseLocation(
        socketId: socketId,
        pointer: pointer,
        button: button,
        selectedElementIds: selectedElementIds,
        username: username,
        userId: userId,
        avatarUrl: avatarUrl,
      ),
    );
  }

  Future<void> broadcastIdleStatus({
    required CollaborationRoom room,
    required String userState,
    required String username,
    String? userId,
    String? avatarUrl,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.idleStatus(
        socketId: socketId,
        userState: userState,
        username: username,
        userId: userId,
        avatarUrl: avatarUrl,
      ),
    );
  }

  Future<void> broadcastVisibleSceneBounds({
    required CollaborationRoom room,
    required String username,
    required Map<String, Object?> sceneBounds,
    String? userId,
    String? avatarUrl,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.userVisibleSceneBounds(
        socketId: socketId,
        username: username,
        sceneBounds: sceneBounds,
        userId: userId,
        avatarUrl: avatarUrl,
      ),
    );
  }

  ExcalidrawScene reconcileRemoteScene({
    required ExcalidrawScene localScene,
    required List<Map<String, Object?>> remoteElements,
    Set<String> protectedElementIds = const {},
  }) {
    final reconciled = _reconciler.reconcile(
      localElements: localScene.elements,
      remoteElements: remoteElements,
      protectedElementIds: protectedElementIds,
    );
    final nextScene = localScene.copyWith(
      elements: _reconciler.getSyncableElements(reconciled),
    );
    _latestScene = nextScene;
    _rememberBroadcasted(nextScene.elements);
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      nextScene.elements,
    );
    return nextScene.copyWith(elements: reconciled);
  }

  Future<CollaborationLoadedFilesResult> loadMissingFiles({
    required CollaborationRoom room,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) async {
    final ids = {
      for (final fileId in fileIds)
        if (!existingFileIds.contains(fileId) &&
            !_fileManager.isFileTracked(fileId))
          fileId,
    };
    final files = await _fileManager.getFiles(
      fileStore: _fileStore,
      roomId: room.roomId,
      roomKey: room.roomKey,
      fileIds: ids,
    );
    final encoded = <String, dynamic>{};
    for (final entry in files.loadedFiles.entries) {
      encoded[entry.key] = {
        'mimeType': entry.value.mimeType,
        'id': entry.key,
        'dataURL':
            'data:${entry.value.mimeType};base64,${base64Encode(entry.value.bytes)}',
        'created': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return CollaborationLoadedFilesResult(
      files: encoded,
      erroredFileIds: files.erroredFileIds,
    );
  }

  void _startRoomSession(CollaborationRoom room) {
    _stopRoomSession();
    _messageBacklog.clear();
    _messageDecodeQueue = Future<void>.value();
    _transportMessageSubscription = _transport.messages.listen(
      (payload) {
        CollaborationDebugLog.write('wire', 'payload_received', {
          'room': _shortRoomId(room.roomId),
          'encryptedBytes': payload.encryptedBuffer.length,
          'ivBytes': payload.iv.length,
        });
        _messageDecodeQueue = _messageDecodeQueue
            .then((_) => _handleEncryptedPayload(room, payload))
            .catchError((Object error) {
              CollaborationDebugLog.write('repo', 'message_queue_failed', {
                'error': error,
              });
              _addRepositoryError('协作消息处理失败：$error');
            });
      },
      onError: (Object error) {
        CollaborationDebugLog.write('repo', 'message_stream_failed', {
          'error': error,
        });
        _addRepositoryError('协作消息接收失败：$error');
      },
    );
    _newUserSubscription = _transport.newUsers.listen((_) {
      final activeRoom = _activeRoom;
      if (activeRoom == null ||
          activeRoom.roomId != room.roomId ||
          _latestScene.elements.isEmpty) {
        return;
      }
      unawaited(_sendSceneInitToNewUser(activeRoom));
    });
  }

  Future<void> _handleEncryptedPayload(
    CollaborationRoom room,
    EncryptedPayload payload,
  ) async {
    if (_activeRoom?.roomId != room.roomId) {
      return;
    }
    try {
      final bytes = await _crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      final message = CollaborationMessage.fromBytes(bytes);
      CollaborationDebugLog.write('crypto', 'decoded', {
        'room': _shortRoomId(room.roomId),
        'type': message.type.wireName,
        'elements': message.elements.length,
        'summary': CollaborationDebugLog.elementSummary(message.elements),
      });
      if (_messages.hasListener) {
        _messages.add(message);
      } else {
        CollaborationDebugLog.write('repo', 'message_backlogged', {
          'type': message.type.wireName,
        });
        _messageBacklog.add(message);
      }
    } catch (error) {
      CollaborationDebugLog.write('crypto', 'decrypt_failed', {
        'room': _shortRoomId(room.roomId),
        'error': error,
      });
      _addRepositoryError('协作消息解密失败：$error');
    }
  }

  Future<void> _sendSceneInitToNewUser(CollaborationRoom room) async {
    try {
      await broadcastScene(room: room, scene: _latestScene, initial: true);
    } catch (error) {
      _addRepositoryError('协作初始化同步失败：$error');
    }
  }

  void _stopRoomSession() {
    unawaited(_transportMessageSubscription?.cancel());
    _transportMessageSubscription = null;
    unawaited(_newUserSubscription?.cancel());
    _newUserSubscription = null;
    _messageDecodeQueue = Future<void>.value();
    _messageBacklog.clear();
  }

  void _addRepositoryError(String message) {
    if (!_repositoryErrors.isClosed) {
      _repositoryErrors.add(message);
    }
  }

  Future<void> _send({
    required CollaborationRoom room,
    required CollaborationMessage message,
    bool volatile = false,
  }) async {
    final encrypted = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: message.toBytes(),
    );
    CollaborationDebugLog.write('wire', 'send_message', {
      'room': _shortRoomId(room.roomId),
      'type': message.type.wireName,
      'volatile': volatile,
      'elements': message.elements.length,
      'encryptedBytes': encrypted.encryptedBuffer.length,
      'ivBytes': encrypted.iv.length,
      'summary': CollaborationDebugLog.elementSummary(message.elements),
    });
    await _transport.send(encrypted, volatile: volatile);
  }

  void _scheduleFileUpload(CollaborationRoom room) {
    if (_fileUploadTimer?.isActive ?? false) {
      return;
    }
    _fileUploadTimer = Timer(fileUploadTimeout, () {
      _fileUploadTimer = null;
      unawaited(_flushQueuedFileUpload(room));
    });
  }

  Future<void> _flushQueuedFileUpload(CollaborationRoom room) async {
    if (_activeRoom?.roomId != room.roomId) {
      return;
    }
    try {
      final result = await _fileManager.saveFiles(
        fileStore: _fileStore,
        roomId: room.roomId,
        roomKey: room.roomKey,
        elements: _latestScene.elements,
        filesJson: _latestScene.files,
      );
      if (result.savedFileIds.isEmpty && result.erroredFileIds.isEmpty) {
        return;
      }
      final nextScene = _updateImageStatuses(
        _latestScene,
        savedFileIds: result.savedFileIds,
        erroredFileIds: result.erroredFileIds,
      );
      if (identical(nextScene, _latestScene)) {
        return;
      }
      _latestScene = nextScene;
      if (!_fileStatusScenes.isClosed) {
        _fileStatusScenes.add(nextScene);
      }
      unawaited(broadcastScene(room: room, scene: nextScene));
    } catch (error) {
      _addRepositoryError('图片文件同步失败，图形和文字会继续同步：$error');
    }
  }

  Future<ExcalidrawScene> _saveSceneResolvingConflict({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    try {
      await _sceneStore.saveScene(
        room: room,
        scene: scene.copyWith(files: const {}),
      );
      return scene;
    } on StaleSceneSnapshotException {
      final storedScene = await _sceneStore.loadScene(room);
      if (storedScene == null) {
        rethrow;
      }
      final reconciledElements = _reconciler.reconcile(
        localElements: scene.elements,
        remoteElements: storedScene.elements,
      );
      final mergedScene = scene.copyWith(
        elements: _reconciler.getSyncableElements(reconciledElements),
      );
      await _sceneStore.saveScene(
        room: room,
        scene: mergedScene.copyWith(files: const {}),
      );
      return mergedScene;
    }
  }

  Future<void> _saveSceneSnapshot({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    try {
      final savedScene = await _saveSceneResolvingConflict(
        room: room,
        scene: scene,
      );
      _latestScene = savedScene;
    } catch (error) {
      if (!_repositoryErrors.isClosed) {
        _repositoryErrors.add('协作快照保存失败，实时协作会继续尝试同步：$error');
      }
    }
  }

  ExcalidrawScene _markSavedImagesPending(ExcalidrawScene scene) {
    var changed = false;
    final elements = <Map<String, Object?>>[];
    for (final element in scene.elements) {
      if (element['type'] == 'image' && element['status'] == 'saved') {
        changed = true;
        elements.add(_bumpElement({...element, 'status': 'pending'}));
      } else {
        elements.add(element);
      }
    }
    return changed ? scene.copyWith(elements: elements) : scene;
  }

  ExcalidrawScene _updateImageStatuses(
    ExcalidrawScene scene, {
    required Set<String> savedFileIds,
    required Set<String> erroredFileIds,
  }) {
    var changed = false;
    final elements = [
      for (final element in scene.elements)
        _updatedImageStatusElement(
          element,
          savedFileIds: savedFileIds,
          erroredFileIds: erroredFileIds,
          onChanged: () => changed = true,
        ),
    ];
    if (!changed) {
      return scene;
    }
    CollaborationDebugLog.write('file_manager', 'status_scene_updated', {
      'saved': savedFileIds.map(_shortFileId).toList(),
      'errored': erroredFileIds.map(_shortFileId).toList(),
      'sceneVersion': _reconciler.getSceneVersion(elements),
    });
    return scene.copyWith(elements: elements);
  }

  Map<String, Object?> _updatedImageStatusElement(
    Map<String, Object?> element, {
    required Set<String> savedFileIds,
    required Set<String> erroredFileIds,
    required void Function() onChanged,
  }) {
    if (element['type'] != 'image') {
      return element;
    }
    final fileId = element['fileId'];
    if (fileId is! String) {
      return element;
    }
    final nextStatus = savedFileIds.contains(fileId)
        ? 'saved'
        : erroredFileIds.contains(fileId)
        ? 'error'
        : null;
    if (nextStatus == null || element['status'] == nextStatus) {
      return element;
    }
    onChanged();
    return _bumpElement({...element, 'status': nextStatus});
  }

  Map<String, Object?> _bumpElement(Map<String, Object?> element) {
    final version = (element['version'] as num?)?.toInt() ?? 1;
    return {
      ...element,
      'version': version + 1,
      'versionNonce': _random.nextInt(1 << 31),
      'updated': DateTime.now().millisecondsSinceEpoch,
    };
  }

  List<Map<String, Object?>> _changedElements(
    List<Map<String, Object?>> elements,
  ) {
    return [
      for (final element in elements)
        if (!_broadcastedElementVersions.containsKey(_id(element)) ||
            _isNewerThanBroadcasted(element))
          element,
    ];
  }

  bool _isNewerThanBroadcasted(Map<String, Object?> element) {
    final record = _broadcastedElementVersions[_id(element)]!;
    final v = (element['version'] as num).toInt();
    final n = (element['versionNonce'] as num).toInt();
    if (v > record.version) return true;
    if (v < record.version) return false;
    return n < record.versionNonce; // 同版本 nonce 小者胜（对齐 _shouldKeepLocal）
  }

  void _rememberBroadcasted(List<Map<String, Object?>> elements) {
    for (final element in elements) {
      _broadcastedElementVersions[_id(element)] = _VersionRecord(
        (element['version'] as num).toInt(),
        (element['versionNonce'] as num).toInt(),
      );
    }
  }

  void _startFullSceneSync() {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = Timer.periodic(fullSceneSyncInterval, (_) {
      final room = _activeRoom;
      if (room == null || _latestScene.elements.isEmpty) {
        return;
      }
      unawaited(broadcastScene(room: room, scene: _latestScene, syncAll: true));
    });
  }

  String _id(Map<String, Object?> element) => element['id']! as String;

  int _version(Map<String, Object?> element) =>
      (element['version']! as num).toInt();

  String _shortRoomId(String roomId) =>
      roomId.length > 8 ? roomId.substring(0, 8) : roomId;

  String _shortFileId(String fileId) =>
      fileId.length > 8 ? fileId.substring(0, 8) : fileId;

  Future<void> stop() async {
    _resetLocalState();
    await _transport.disconnect();
  }

  void _resetLocalState() {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = null;
    _fileUploadTimer?.cancel();
    _fileUploadTimer = null;
    _stopRoomSession();
    _activeRoom = null;
    _latestScene = ExcalidrawScene.empty();
    _broadcastedElementVersions.clear();
    _lastBroadcastedOrReceivedSceneVersion = 0;
    _fileManager.reset();
  }
}

class CollaborationJoinResult {
  const CollaborationJoinResult({required this.scene, required this.metadata});

  final ExcalidrawScene scene;
  final CollaborationRoomMetadata metadata;
}

class CollaborationLoadedFilesResult {
  const CollaborationLoadedFilesResult({
    required this.files,
    required this.erroredFileIds,
  });

  final Map<String, dynamic> files;
  final Set<String> erroredFileIds;
}
