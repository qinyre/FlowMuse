import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
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
    repository.reconcileRemoteScene(
      localScene: localChanged,
      remoteElements: [_element('remote', 2)],
    );

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
  test('停止协作会取消尚未刷新的增量广播', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = _scene([_element('local', 1)]);
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
      elements: [_element('local', 2)],
    );
    await repository.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      received.where(
        (message) => message.type == CollaborationMessageType.sceneUpdate,
      ),
      isEmpty,
    );

    await subscription.cancel();
    await peerTransport.disconnect();
  });

  test('旧会话停止完成后不会清空新会话', () async {
    final crypto = CollaborationCrypto();
    final firstRoom = CollaborationRoom.newRoom(crypto: crypto);
    final nextRoom = CollaborationRoom.newRoom(crypto: crypto);
    final store = _BlockingSceneStore();
    final firstScene = _scene([_element('first', 1)]);
    final nextScene = _scene([_element('next', 1)]);
    await store.createRoom(
      room: firstRoom,
      scene: firstScene,
      ownerKeyHash: 'test',
    );
    await store.createRoom(
      room: nextRoom,
      scene: nextScene,
      ownerKeyHash: 'test',
    );

    final hub = MemoryRealtimeRoomHub();
    final peerTransport = MemoryRealtimeTransport(hub: hub, socketId: 'peer');
    final repository = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'repository'),
      sceneStore: store,
      crypto: crypto,
    );
    await repository.joinRoom(room: firstRoom, localScene: firstScene);
    await repository.broadcastScene(
      room: firstRoom,
      scene: _scene([_element('first', 2)]),
      syncAll: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    store.blockRoomId = firstRoom.roomId;
    final stopping = repository.stop();
    await store.saveStarted.future;

    await peerTransport.connect(nextRoom.roomId);
    await repository.joinRoom(room: nextRoom, localScene: nextScene);
    store.releaseSave();
    await stopping;

    final received = <CollaborationMessage>[];
    final subscription = peerTransport.messages.listen((payload) async {
      final bytes = await crypto.decrypt(
        roomKey: nextRoom.roomKey,
        encryptedPayload: payload,
      );
      received.add(CollaborationMessage.fromBytes(bytes));
    });
    await repository.broadcastElements(
      room: nextRoom,
      elements: [_element('next', 2)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      received.where(
        (message) => message.type == CollaborationMessageType.sceneUpdate,
      ),
      isNotEmpty,
    );

    await subscription.cancel();
    await repository.stop();
    await peerTransport.disconnect();
  });
}

class _BlockingSceneStore extends MemoryEncryptedSceneStore {
  final saveStarted = Completer<void>();
  final _saveReleased = Completer<void>();
  String? blockRoomId;

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    if (room.roomId == blockRoomId && !saveStarted.isCompleted) {
      saveStarted.complete();
      await _saveReleased.future;
    }
    await super.saveScene(room: room, scene: scene);
  }

  void releaseSave() {
    if (!_saveReleased.isCompleted) {
      _saveReleased.complete();
    }
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
