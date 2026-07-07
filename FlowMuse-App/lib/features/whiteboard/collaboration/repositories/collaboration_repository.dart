import 'dart:async';
import 'dart:convert';

import '../models/collaboration_message.dart';
import '../models/collaboration_room.dart';
import '../models/excalidraw_scene.dart';
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
    CollaborationCrypto? crypto,
    SceneReconciler? reconciler,
  }) : _transport = transport ?? const DisconnectedRealtimeTransport(),
       _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
       _fileStore = fileStore,
       _crypto = crypto ?? CollaborationCrypto(),
       _reconciler = reconciler ?? SceneReconciler();

  static const Duration fullSceneSyncInterval = Duration(seconds: 20);

  final RealtimeTransport _transport;
  final EncryptedSceneStore _sceneStore;
  final CollaborationFileStore? _fileStore;
  final CollaborationCrypto _crypto;
  final SceneReconciler _reconciler;
  final Map<String, int> _broadcastedElementVersions = {};
  final Set<String> _uploadedFileIds = {};

  Timer? _fullSceneSyncTimer;
  CollaborationRoom? _activeRoom;
  ExcalidrawScene _latestScene = ExcalidrawScene.empty();
  int _lastBroadcastedOrReceivedSceneVersion = -1;

  String get socketId => _transport.socketId ?? 'local-client';

  Stream<String> get newUsers => _transport.newUsers;

  Stream<List<String>> get roomUsers => _transport.roomUsers;

  Stream<void> get firstInRoom => _transport.firstInRoom;

  Stream<String> get errors => _transport.errors;

  Stream<CollaborationMessage> encryptedMessages(CollaborationRoom room) {
    return _transport.messages.asyncMap((payload) async {
      final bytes = await _crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      return CollaborationMessage.fromBytes(bytes);
    });
  }

  Future<CollaborationRoom> startNewRoom({
    required ExcalidrawScene initialScene,
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    final syncableScene = initialScene.copyWith(
      elements: _reconciler.getSyncableElements(initialScene.elements),
    );
    await _fileStore?.uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: syncableScene.files,
      alreadyUploadedFileIds: _uploadedFileIds,
    );
    await _sceneStore.createRoom(room: room, scene: syncableScene);
    await _transport.connect(room.roomId);
    _activeRoom = room;
    _latestScene = syncableScene;
    final sceneVersion = _reconciler.getSceneVersion(syncableScene.elements);
    _lastBroadcastedOrReceivedSceneVersion = sceneVersion;
    _rememberBroadcasted(syncableScene.elements);
    await _send(
      room: room,
      message: CollaborationMessage.sceneInit(elements: syncableScene.elements),
    );
    _startFullSceneSync();
    return room;
  }

  Future<ExcalidrawScene> joinRoom({
    required CollaborationRoom room,
    required ExcalidrawScene localScene,
  }) async {
    final storedScene = await _sceneStore.loadScene(room);
    if (storedScene == null) {
      throw StateError('房间不存在或尚未创建');
    }
    await _transport.connect(room.roomId);
    _activeRoom = room;
    final nextScene = storedScene.copyWith(
      elements: _reconciler.getSyncableElements(storedScene.elements),
    );
    _latestScene = nextScene;
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      nextScene.elements,
    );
    _rememberBroadcasted(nextScene.elements);
    _startFullSceneSync();
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
    await _fileStore?.uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: scene.files,
      alreadyUploadedFileIds: _uploadedFileIds,
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

    final sceneToBroadcast = await _saveSceneResolvingConflict(
      room: room,
      scene: syncableScene,
    );
    final elementsForMessage = identical(sceneToBroadcast, syncableScene)
        ? elementsToBroadcast
        : sceneToBroadcast.elements;
    final message = initial
        ? CollaborationMessage.sceneInit(elements: elementsForMessage)
        : CollaborationMessage.sceneUpdate(elements: elementsForMessage);
    await _send(room: room, message: message);
    _rememberBroadcasted(elementsForMessage);
    _latestScene = sceneToBroadcast;
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      sceneToBroadcast.elements,
    );
  }

  Future<void> broadcastMouseLocation({
    required CollaborationRoom room,
    required Map<String, Object?> pointer,
    required String button,
    required Map<String, bool> selectedElementIds,
    required String username,
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
      ),
    );
  }

  Future<void> broadcastIdleStatus({
    required CollaborationRoom room,
    required String userState,
    required String username,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.idleStatus(
        socketId: socketId,
        userState: userState,
        username: username,
      ),
    );
  }

  Future<void> broadcastVisibleSceneBounds({
    required CollaborationRoom room,
    required String username,
    required Map<String, Object?> sceneBounds,
  }) {
    return _send(
      room: room,
      volatile: true,
      message: CollaborationMessage.userVisibleSceneBounds(
        socketId: socketId,
        username: username,
        sceneBounds: sceneBounds,
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
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = null;
    _activeRoom = null;
    _latestScene = ExcalidrawScene.empty();
    _broadcastedElementVersions.clear();
    _uploadedFileIds.clear();
    _lastBroadcastedOrReceivedSceneVersion = -1;
    await _transport.disconnect();
  }
}
