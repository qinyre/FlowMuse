import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/room_collaborator.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/received_live_ink_frame.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('远端合并不会吞掉本地尚未发送的元素', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = _scene([_element('local', 1), _element('remote', 1)]);
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'repository',
    );
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'peer');
    final repository = CollaborationRepository(
      transport: repositoryTransport,
      sceneStore: store,
      crypto: crypto,
    );

    await peerTransport.connect(room.roomId);
    await repository.joinRoom(room: room, localScene: initial);
    final received = <CollaborationMessage>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      received.add(CollaborationMessage.fromBytes(bytes));
    });

    final localChanged = _scene([_element('local', 2), _element('remote', 1)]);
    await repository.broadcastScene(room: room, scene: localChanged);
    final remoteChanges = repository.reconcileRemoteElements(
      remoteElements: [_element('remote', 2)],
    );
    expect(remoteChanges.single['id'], 'remote');
    expect(remoteChanges.single['version'], 2);

    await Future<void>.delayed(const Duration(milliseconds: 150));

    final updates = received
        .where(
          (message) => message.type == CollaborationMessageType.sceneUpdate,
        )
        .toList();
    expect(updates, hasLength(1));
    expect(updates.single.elements.map((e) => e['id']), contains('local'));

    await subscription.cancel();
    await repository.stop();
    await peerTransport.disconnect();
  });

  test('增量广播只发送指定元素', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = _scene([
      for (var i = 0; i < 200; i++) _element('element-$i', 1),
    ]);
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'peer');
    final repository = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'repository'),
      sceneStore: store,
      crypto: crypto,
    );
    await peerTransport.connect(room.roomId);
    await repository.joinRoom(room: room, localScene: initial);

    final received = <CollaborationMessage>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      received.add(CollaborationMessage.fromBytes(bytes));
    });

    await repository.broadcastElements(
      room: room,
      elements: [_element('element-99', 2)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final updates = received
        .where(
          (message) => message.type == CollaborationMessageType.sceneUpdate,
        )
        .toList();
    expect(updates, hasLength(1));
    expect(updates.single.elements, hasLength(1));
    expect(updates.single.elements.single['id'], 'element-99');

    await subscription.cancel();
    await repository.stop();
    await peerTransport.disconnect();
  });

  test('实时笔迹发送阻塞时只保留最新帧且不丢最终帧', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = _scene([_element('stroke', 1)]);
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryTransport = _GatedMemoryRealtimeTransport(
      hub: hub,
      socketId: 'repository',
    );
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'peer');
    final repository = CollaborationRepository(
      transport: repositoryTransport,
      sceneStore: store,
      crypto: crypto,
    );
    await peerTransport.connect(room.roomId);
    await repository.joinRoom(room: room, localScene: initial);

    final receivedVersions = <int>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: room.roomKey,
        encryptedPayload: payload,
      );
      final message = CollaborationMessage.fromBytes(bytes);
      if (message.type == CollaborationMessageType.sceneUpdate) {
        receivedVersions.add(
          (message.elements.single['version'] as num).toInt(),
        );
      }
    });

    repositoryTransport.blockNextSend();
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 2)],
      latestOnly: true,
    );
    await repositoryTransport.waitForBlockedSend();
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 3)],
      latestOnly: true,
    );
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 4)],
      latestOnly: true,
    );
    repositoryTransport.releaseSend();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    repositoryTransport.blockNextSend();
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 5)],
      latestOnly: true,
    );
    await repositoryTransport.waitForBlockedSend();
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 6)],
      latestOnly: true,
    );
    await repository.broadcastElements(
      room: room,
      elements: [_element('stroke', 7)],
    );
    repositoryTransport.releaseSend();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(receivedVersions, [2, 4, 5, 7]);

    await subscription.cancel();
    await repository.stop();
    await peerTransport.disconnect();
  });

  test('stop 返回前取消房间订阅并断开 transport', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = _scene([_element('element', 1)]);
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');
    final transport = _LifecycleTransport();
    final repository = CollaborationRepository(
      transport: transport,
      sceneStore: store,
      crypto: crypto,
    );

    await repository.joinRoom(room: room, localScene: initial);
    expect(transport.messagesController.hasListener, isTrue);
    expect(transport.newUsersController.hasListener, isTrue);

    await repository.stop();

    expect(transport.messagesController.hasListener, isFalse);
    expect(transport.newUsersController.hasListener, isFalse);
    expect(transport.disconnectCount, 1);
    await transport.close();
  });

  test('换房期间完成的旧房解密不会进入新房消息流', () async {
    final crypto = _GatedDecryptCrypto();
    final roomA = CollaborationRoom.newRoom(crypto: crypto);
    final roomB = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    await store.createRoom(
      room: roomA,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'a',
    );
    await store.createRoom(
      room: roomB,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'b',
    );
    final transport = _LifecycleTransport();
    final repository = CollaborationRepository(
      transport: transport,
      sceneStore: store,
      crypto: crypto,
    );
    await repository.joinRoom(room: roomA, localScene: ExcalidrawScene.empty());
    final payload = await CollaborationCrypto().encrypt(
      roomKey: roomA.roomKey,
      plainBytes: CollaborationMessage.sceneUpdate(
        elements: [_element('old-room', 1)],
      ).toBytes(),
    );
    crypto.blockNextDecrypt();
    transport.messagesController.add(payload);
    await crypto.decryptStarted;

    await repository.joinRoom(room: roomB, localScene: ExcalidrawScene.empty());
    final received = <CollaborationMessage>[];
    final subscription = repository
        .encryptedMessages(roomB)
        .listen(received.add);
    crypto.releaseDecrypt();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await subscription.cancel();
    await repository.stop();
    await transport.close();
  });
}

class _LifecycleTransport implements RealtimeTransport {
  final messagesController = StreamController<EncryptedPayload>.broadcast();
  final newUsersController = StreamController<String>.broadcast();
  int disconnectCount = 0;

  @override
  Stream<EncryptedPayload> get messages => messagesController.stream;

  @override
  Stream<ReceivedLiveInkFrame> get liveInkFrames => const Stream.empty();

  @override
  Stream<String> get newUsers => newUsersController.stream;

  @override
  Stream<List<RoomCollaborator>> get roomUsers => const Stream.empty();

  @override
  Stream<CollaborationRoomMetadata> get roomEnded => const Stream.empty();

  @override
  Stream<void> get firstInRoom => const Stream.empty();

  @override
  Stream<String> get errors => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatus => const Stream.empty();

  @override
  String? get socketId => 'lifecycle';

  @override
  int get serverLiveInkProtocolVersion => 0;

  @override
  int get liveInkTransportNotWritableDrops => 0;

  @override
  Future<void> connect(String roomId) async {}

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {}

  @override
  Future<void> sendLiveInk(EncryptedPayload payload) async {}

  @override
  Future<void> endRoom({String? ownerKey}) async {}

  @override
  Future<void> disconnect() async {
    disconnectCount++;
  }

  Future<void> close() async {
    await messagesController.close();
    await newUsersController.close();
  }
}

class _GatedMemoryRealtimeTransport extends MemoryRealtimeTransport {
  _GatedMemoryRealtimeTransport({required super.hub, required super.socketId});

  Completer<void>? _sendGate;
  Completer<void>? _sendStarted;

  void blockNextSend() {
    _sendGate = Completer<void>();
    _sendStarted = Completer<void>();
  }

  Future<void> waitForBlockedSend() => _sendStarted!.future;

  void releaseSend() => _sendGate!.complete();

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    final gate = _sendGate;
    if (gate != null) {
      _sendStarted?.complete();
      await gate.future;
      if (identical(_sendGate, gate)) {
        _sendGate = null;
      }
    }
    await super.send(payload, volatile: volatile);
  }
}

class _GatedDecryptCrypto extends CollaborationCrypto {
  Completer<void>? _gate;
  Completer<void>? _started;

  Future<void> get decryptStarted => _started!.future;

  void blockNextDecrypt() {
    _gate = Completer<void>();
    _started = Completer<void>();
  }

  void releaseDecrypt() => _gate?.complete();

  @override
  Future<List<int>> decrypt({
    required String roomKey,
    required EncryptedPayload encryptedPayload,
  }) async {
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      _started!.complete();
      await gate.future;
    }
    return super.decrypt(roomKey: roomKey, encryptedPayload: encryptedPayload);
  }
}

ExcalidrawScene _scene(List<Map<String, Object?>> elements) {
  return ExcalidrawScene.empty().copyWith(elements: elements);
}

Map<String, Object?> _element(String id, int version) {
  return {
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': 10,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': false,
    'index': id,
    'x': 0,
    'y': 0,
    'width': 100,
    'height': 100,
  };
}
