import '../models/collaboration_message.dart';
import '../models/collaboration_room.dart';
import '../services/collaboration_crypto.dart';
import '../services/encrypted_scene_store.dart';
import '../services/realtime_transport.dart';
import '../services/scene_reconciler.dart';

class CollaborationRepository {
  CollaborationRepository({
    RealtimeTransport? transport,
    EncryptedSceneStore? sceneStore,
    CollaborationCrypto? crypto,
    SceneReconciler? reconciler,
  }) : _transport = transport ?? const DisconnectedRealtimeTransport(),
       _sceneStore = sceneStore ?? MemoryEncryptedSceneStore(),
       _crypto = crypto ?? CollaborationCrypto(),
       _reconciler = reconciler ?? SceneReconciler();

  final RealtimeTransport _transport;
  final EncryptedSceneStore _sceneStore;
  final CollaborationCrypto _crypto;
  final SceneReconciler _reconciler;

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
  }) async {
    final room = CollaborationRoom.newRoom(crypto: _crypto);
    await _transport.connect(room.roomId);
    await _sceneStore.saveScene(room: room, elements: initialElements);
    await broadcastScene(room: room, elements: initialElements, initial: true);
    return room;
  }

  Future<List<Map<String, Object?>>> joinRoom({
    required CollaborationRoom room,
    required List<Map<String, Object?>> localElements,
  }) async {
    await _transport.connect(room.roomId);
    final storedElements = await _sceneStore.loadScene(room);
    if (storedElements == null) {
      return localElements;
    }
    return _reconciler.reconcile(
      localElements: localElements,
      remoteElements: storedElements,
    );
  }

  Future<void> broadcastScene({
    required CollaborationRoom room,
    required List<Map<String, Object?>> elements,
    bool initial = false,
  }) async {
    final syncableElements = _reconciler.getSyncableElements(elements);
    await _sceneStore.saveScene(room: room, elements: syncableElements);
    final message = initial
        ? CollaborationMessage(
            type: CollaborationMessageType.sceneInit,
            payload: {'elements': syncableElements},
          )
        : CollaborationMessage.sceneUpdate(elements: syncableElements);
    final encrypted = await _crypto.encrypt(
      roomKey: room.roomKey,
      plainBytes: message.toBytes(),
    );
    await _transport.send(encrypted);
  }

  Future<void> stop() async {
    await _transport.disconnect();
  }
}
