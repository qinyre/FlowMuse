import 'dart:async';
import 'dart:convert';

import '../models/collaboration_message.dart';
import '../models/collaboration_room.dart';
import '../models/encrypted_payload.dart';
import '../models/excalidraw_scene.dart';
import '../models/room_collaborator.dart';
import 'collaboration_owner_key_store.dart';
import '../services/collaboration_crypto.dart';
import '../services/collaboration_file_store.dart';
import '../services/encrypted_scene_store.dart';
import '../services/realtime_transport.dart';
import '../services/scene_reconciler.dart';

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

  final RealtimeTransport _transport;
  final EncryptedSceneStore _sceneStore;
  final CollaborationFileStore? _fileStore;
  final CollaborationOwnerKeyStore _ownerKeyStore;
  final CollaborationCrypto _crypto;
  final SceneReconciler _reconciler;
  final Map<String, int> _broadcastedElementVersions = {};
  final Set<String> _uploadedFileIds = {};
  final StreamController<String> _repositoryErrors =
      StreamController<String>.broadcast();
  final StreamController<CollaborationMessage> _messages =
      StreamController<CollaborationMessage>.broadcast();
  final List<CollaborationMessage> _messageBacklog = [];

  Timer? _fullSceneSyncTimer;
  StreamSubscription<EncryptedPayload>? _transportMessageSubscription;
  StreamSubscription<String>? _newUserSubscription;
  Future<void> _messageDecodeQueue = Future<void>.value();
  CollaborationRoom? _activeRoom;
  ExcalidrawScene _latestScene = ExcalidrawScene.empty();
  int _lastBroadcastedOrReceivedSceneVersion = -1;

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

  Future<CollaborationRoom> startNewRoom({
    required ExcalidrawScene initialScene,
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    final ownerKey = _crypto.generateRoomKey();
    final ownerKeyHash = _crypto.hashOwnerKey(
      roomId: room.roomId,
      ownerKey: ownerKey,
    );
    final syncableScene = initialScene.copyWith(
      elements: _reconciler.getSyncableElements(initialScene.elements),
    );
    await _uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: syncableScene.files,
    );
    await _sceneStore.createRoom(
      room: room,
      scene: syncableScene,
      ownerKeyHash: ownerKeyHash,
    );
    await _ownerKeyStore.writeOwnerKey(room.roomId, ownerKey);
    _activeRoom = room;
    _latestScene = syncableScene;
    final sceneVersion = _reconciler.getSceneVersion(syncableScene.elements);
    _lastBroadcastedOrReceivedSceneVersion = sceneVersion;
    _rememberBroadcasted(syncableScene.elements);
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
    final reconciledElements = _reconciler.reconcile(
      localElements: localScene.elements,
      remoteElements: storedScene.elements,
    );
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(reconciledElements),
      files: {...localScene.files, ...storedScene.files},
    );
    _latestScene = nextScene;
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      nextScene.elements,
    );
    _rememberBroadcasted(nextScene.elements);
    _activeRoom = room;
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
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      nextScene.elements,
    );
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
    await _uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: scene.files,
      reportOnly: true,
    );

    final sceneVersion = _reconciler.getSceneVersion(syncableElements);
    if (!initial &&
        !syncAll &&
        sceneVersion <= _lastBroadcastedOrReceivedSceneVersion) {
      return;
    }

    final elementsToBroadcast = initial || syncAll
        ? syncableElements
        : _changedElements(syncableElements);
    if (elementsToBroadcast.isEmpty && !initial) {
      return;
    }

    final message = initial
        ? CollaborationMessage.sceneInit(elements: elementsToBroadcast)
        : CollaborationMessage.sceneUpdate(elements: elementsToBroadcast);
    await _send(room: room, message: message);
    _rememberBroadcasted(elementsToBroadcast);
    _latestScene = syncableScene;
    _lastBroadcastedOrReceivedSceneVersion = sceneVersion;
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
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      reconciled,
    );
    return nextScene.copyWith(elements: reconciled);
  }

  Future<Map<String, dynamic>> loadMissingFiles({
    required CollaborationRoom room,
    required Iterable<String> fileIds,
    required Set<String> existingFileIds,
  }) async {
    final files = await _fileStore?.loadMissingFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      fileIds: fileIds,
      existingFileIds: existingFileIds,
    );
    if (files == null || files.isEmpty) {
      return const {};
    }
    final encoded = <String, dynamic>{};
    for (final entry in files.entries) {
      encoded[entry.key] = {
        'mimeType': entry.value.mimeType,
        'id': entry.key,
        'dataURL':
            'data:${entry.value.mimeType};base64,${base64Encode(entry.value.bytes)}',
        'created': DateTime.now().millisecondsSinceEpoch,
      };
    }
    return encoded;
  }

  void _startRoomSession(CollaborationRoom room) {
    _stopRoomSession();
    _messageBacklog.clear();
    _messageDecodeQueue = Future<void>.value();
    _transportMessageSubscription = _transport.messages.listen(
      (payload) {
        _messageDecodeQueue = _messageDecodeQueue
            .then((_) => _handleEncryptedPayload(room, payload))
            .catchError((Object error) {
              _addRepositoryError('协作消息处理失败：$error');
            });
      },
      onError: (Object error) {
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
      if (_messages.hasListener) {
        _messages.add(message);
      } else {
        _messageBacklog.add(message);
      }
    } catch (error) {
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
    await _transport.send(encrypted, volatile: volatile);
  }

  Future<void> _uploadFiles({
    required String roomId,
    required String roomKey,
    required Map<String, Object?> filesJson,
    bool reportOnly = false,
  }) async {
    try {
      await _fileStore?.uploadFiles(
        roomId: roomId,
        roomKey: roomKey,
        filesJson: filesJson,
        alreadyUploadedFileIds: _uploadedFileIds,
      );
    } catch (error) {
      final message = '图片文件同步失败，图形和文字会继续同步：$error';
      if (!_repositoryErrors.isClosed) {
        _repositoryErrors.add(message);
      }
      if (!reportOnly) {
        rethrow;
      }
    }
  }

  Future<ExcalidrawScene> _saveSceneResolvingConflict({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    try {
      await _sceneStore.saveScene(room: room, scene: scene);
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
        files: {...storedScene.files, ...scene.files},
      );
      await _sceneStore.saveScene(room: room, scene: mergedScene);
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

  List<Map<String, Object?>> _changedElements(
    List<Map<String, Object?>> elements,
  ) {
    return [
      for (final element in elements)
        if (!_broadcastedElementVersions.containsKey(_id(element)) ||
            _version(element) > _broadcastedElementVersions[_id(element)]!)
          element,
    ];
  }

  void _rememberBroadcasted(List<Map<String, Object?>> elements) {
    for (final element in elements) {
      _broadcastedElementVersions[_id(element)] = _version(element);
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

  Future<void> stop() async {
    _resetLocalState();
    await _transport.disconnect();
  }

  void _resetLocalState() {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = null;
    _stopRoomSession();
    _activeRoom = null;
    _latestScene = ExcalidrawScene.empty();
    _broadcastedElementVersions.clear();
    _uploadedFileIds.clear();
    _lastBroadcastedOrReceivedSceneVersion = -1;
  }
}

class CollaborationJoinResult {
  const CollaborationJoinResult({required this.scene, required this.metadata});

  final ExcalidrawScene scene;
  final CollaborationRoomMetadata metadata;
}
