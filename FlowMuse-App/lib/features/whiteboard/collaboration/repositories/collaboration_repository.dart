import 'dart:async';
import 'dart:convert';

import '../models/collaboration_message.dart';
import '../models/collaboration_room.dart';
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

  Timer? _fullSceneSyncTimer;
  CollaborationRoom? _activeRoom;
  List<Map<String, Object?>> _latestElements = const [];
  Map<String, Object?> _latestFiles = const {};
  int _lastBroadcastedOrReceivedSceneVersion = -1;

  String get socketId => _transport.socketId ?? 'local-client';

  Stream<String> get newUsers => _transport.newUsers;

  Stream<List<String>> get roomUsers => _transport.roomUsers;

  Stream<void> get firstInRoom => _transport.firstInRoom;

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
    required List<Map<String, Object?>> initialElements,
    Map<String, Object?> files = const {},
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    await _transport.connect(room.roomId);
    _activeRoom = room;
    await broadcastScene(
      room: room,
      elements: initialElements,
      files: files,
      initial: true,
    );
    _startFullSceneSync();
    return room;
  }

  Future<List<Map<String, Object?>>> joinRoom({
    required CollaborationRoom room,
    required List<Map<String, Object?>> localElements,
    Map<String, Object?> files = const {},
  }) async {
    await _transport.connect(room.roomId);
    _activeRoom = room;
    await _fileStore?.uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: files,
    );
    final storedElements = await _sceneStore.loadScene(room);
    if (storedElements == null) {
      _latestElements = _reconciler.getSyncableElements(localElements);
      _latestFiles = files;
      _startFullSceneSync();
      return localElements;
    }
    final reconciled = _reconciler.reconcile(
      localElements: localElements,
      remoteElements: storedElements,
    );
    _latestElements = reconciled;
    _latestFiles = files;
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      reconciled,
    );
    _startFullSceneSync();
    return reconciled;
  }

  Future<void> broadcastScene({
    required CollaborationRoom room,
    required List<Map<String, Object?>> elements,
    Map<String, Object?> files = const {},
    bool initial = false,
    bool syncAll = false,
  }) async {
    final syncableElements = _reconciler.getSyncableElements(elements);
    _latestElements = syncableElements;
    _latestFiles = files;
    await _fileStore?.uploadFiles(
      roomId: room.roomId,
      roomKey: room.roomKey,
      filesJson: files,
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

    await _sceneStore.saveScene(room: room, elements: syncableElements);
    final message = initial
        ? CollaborationMessage.sceneInit(elements: elementsToBroadcast)
        : CollaborationMessage.sceneUpdate(elements: elementsToBroadcast);
    await _send(room: room, message: message);
    _rememberBroadcasted(elementsToBroadcast);
    _lastBroadcastedOrReceivedSceneVersion = sceneVersion;
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

  List<Map<String, Object?>> reconcileRemoteElements({
    required List<Map<String, Object?>> localElements,
    required List<Map<String, Object?>> remoteElements,
    Set<String> protectedElementIds = const {},
  }) {
    final reconciled = _reconciler.reconcile(
      localElements: localElements,
      remoteElements: remoteElements,
      protectedElementIds: protectedElementIds,
    );
    _latestElements = _reconciler.getSyncableElements(reconciled);
    _lastBroadcastedOrReceivedSceneVersion = _reconciler.getSceneVersion(
      reconciled,
    );
    return reconciled;
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
      if (room == null || _latestElements.isEmpty) {
        return;
      }
      unawaited(
        broadcastScene(
          room: room,
          elements: _latestElements,
          files: _latestFiles,
          syncAll: true,
        ),
      );
    });
  }

  String _id(Map<String, Object?> element) => element['id']! as String;

  int _version(Map<String, Object?> element) =>
      (element['version']! as num).toInt();

  Future<void> stop() async {
    _fullSceneSyncTimer?.cancel();
    _fullSceneSyncTimer = null;
    _activeRoom = null;
    _latestElements = const [];
    _latestFiles = const {};
    _broadcastedElementVersions.clear();
    _lastBroadcastedOrReceivedSceneVersion = -1;
    await _transport.disconnect();
  }
}
