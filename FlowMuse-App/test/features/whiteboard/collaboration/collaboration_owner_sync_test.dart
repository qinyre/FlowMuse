import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_creator_identity.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/views/collaboration_focus_target.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ownedElement(
  String id,
  String creatorKey, {
  int version = 1,
}) {
  return <String, Object?>{
    'id': id,
    'type': 'rectangle',
    'version': version,
    'versionNonce': 1,
    'updated': DateTime.now().millisecondsSinceEpoch,
    'isDeleted': false,
    'x': 0,
    'y': 0,
    'width': 100,
    'height': 100,
    'index': 'a$id',
    'customData': {
      'flowMuse': {
        'collaborationOwner': {
          'version': 1,
          'creatorKey': creatorKey,
          'displayName': creatorKey,
          'isGuest': false,
        },
      },
    },
  };
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待协作消息超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('A Repository 广播的元素经加密通道进入 B Repository 且 owner 保留', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = ExcalidrawScene.empty();
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryA = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'a'),
      sceneStore: store,
      crypto: crypto,
    );
    final repositoryB = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'b'),
      sceneStore: store,
      crypto: crypto,
    );
    addTearDown(() async {
      await repositoryA.stop();
      await repositoryB.stop();
    });

    await repositoryA.joinRoom(room: room, localScene: initial);
    await repositoryB.joinRoom(room: room, localScene: initial);
    final received = <CollaborationMessage>[];
    final subscription = repositoryB
        .encryptedMessages(room)
        .listen(received.add);
    addTearDown(subscription.cancel);

    final owned = _ownedElement('e1', 'user:a', version: 2);
    await repositoryA.broadcastElements(room: room, elements: [owned]);
    await _waitUntil(
      () => received.any(
        (message) =>
            message.type == CollaborationMessageType.sceneUpdate &&
            message.elements.any((element) => element['id'] == 'e1'),
      ),
    );

    final remote = received
        .where(
          (message) => message.type == CollaborationMessageType.sceneUpdate,
        )
        .expand((message) => message.elements)
        .singleWhere((element) => element['id'] == 'e1');
    final owner =
        (((remote['customData'] as Map)['flowMuse']
                as Map)['collaborationOwner']
            as Map);
    expect(owner['creatorKey'], 'user:a');
  });

  test('A 更换 socket 重连后，B 收到的新旧 presence creatorKey 一致', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = ExcalidrawScene.empty();
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');

    final hub = MemoryRealtimeRoomHub();
    final repositoryB = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'b'),
      sceneStore: store,
      crypto: crypto,
    );
    late CollaborationRepository repositoryA;
    var repositoryAStopped = false;
    addTearDown(() async {
      if (!repositoryAStopped) await repositoryA.stop();
      await repositoryB.stop();
    });

    await repositoryB.joinRoom(room: room, localScene: initial);
    final idles = <CollaborationMessage>[];
    final subscription = repositoryB.encryptedMessages(room).listen((message) {
      if (message.type == CollaborationMessageType.idleStatus)
        idles.add(message);
    });
    addTearDown(subscription.cancel);

    final creatorKey = creatorKeyForGuest(room.roomId, 'uuid-1');
    repositoryA = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'a-before'),
      sceneStore: store,
      crypto: crypto,
    );
    await repositoryA.joinRoom(room: room, localScene: initial);
    await repositoryA.broadcastIdleStatus(
      room: room,
      userState: 'active',
      username: '张三',
      creatorKey: creatorKey,
    );
    await _waitUntil(() => idles.length == 1);

    await repositoryA.stop();
    repositoryAStopped = true;
    repositoryA = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'a-after'),
      sceneStore: store,
      crypto: crypto,
    );
    repositoryAStopped = false;
    await repositoryA.joinRoom(room: room, localScene: initial);
    await repositoryA.broadcastIdleStatus(
      room: room,
      userState: 'active',
      username: '张三',
      creatorKey: creatorKey,
    );
    await _waitUntil(() => idles.length == 2);

    expect(idles.first.payload['socketId'], 'a-before');
    expect(idles.last.payload['socketId'], 'a-after');
    expect(
      idles.last.payload['creatorKey'],
      idles.first.payload['creatorKey'],
      reason: '同一房间会话 UUID 经真实断连/换 socket 后仍派生同一 creatorKey',
    );
  });

  test('已连接双端中执行 focus 纯状态转换不产生协作消息', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    final initial = ExcalidrawScene.empty();
    await store.createRoom(room: room, scene: initial, ownerKeyHash: 'test');
    final hub = MemoryRealtimeRoomHub();
    final repositoryA = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'a'),
      sceneStore: store,
      crypto: crypto,
    );
    final repositoryB = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'b'),
      sceneStore: store,
      crypto: crypto,
    );
    addTearDown(() async {
      await repositoryA.stop();
      await repositoryB.stop();
    });
    await repositoryA.joinRoom(room: room, localScene: initial);
    await repositoryB.joinRoom(room: room, localScene: initial);
    final received = <CollaborationMessage>[];
    final subscription = repositoryB
        .encryptedMessages(room)
        .listen(received.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    received.clear();

    final target = toggleCollaborationCreatorFocus(
      null,
      creatorKey: 'user:a',
      labelSnapshot: '张三',
      isGuest: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(target, isA<CreatorFocus>());
    expect(
      received,
      isEmpty,
      reason: 'focus 转换不进入 repository；WhiteboardPage 委托关系由 Task 9 源码边界门禁锁定',
    );
  });
}
