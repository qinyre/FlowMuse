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
