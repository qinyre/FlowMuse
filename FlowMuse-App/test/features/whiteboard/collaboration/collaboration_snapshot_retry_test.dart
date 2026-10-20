import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

void main() {
  for (final fail in [false, true]) {
    test('保存中退出协作：上传${fail ? '失败' : '成功'}也能释放等待并断开', () async {
      final store = _SnapshotStore();
      final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
      await store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'fixture',
      );
      final transport = MemoryRealtimeTransport(
        hub: MemoryRealtimeRoomHub(),
        socketId: 'fixture',
      );
      final repository = CollaborationRepository(
        sceneStore: store,
        transport: transport,
      );
      final statuses = <RealtimeConnectionStatus>[];
      final errors = <String>[];
      final statusSubscription = repository.connectionStatus.listen(
        statuses.add,
      );
      final errorSubscription = repository.errors.listen(errors.add);
      addTearDown(statusSubscription.cancel);
      addTearDown(errorSubscription.cancel);
      await repository.joinRoom(
        room: room,
        localScene: ExcalidrawScene.empty(),
      );
      await repository.broadcastElements(
        room: room,
        elements: _scene(1).elements,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      store.gate = Completer<void>();
      store.fail = fail;
      final flushing = repository.forceFlushSnapshot();
      await Future<void>.delayed(Duration.zero);
      final stopping = repository.stop();
      store.gate!.complete();
      await Future.wait([
        flushing,
        stopping,
      ]).timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(statuses.last, RealtimeConnectionStatus.disconnected);
      if (fail) {
        expect(errors, isNotEmpty, reason: '失败仍通过原错误通道上报');
      } else {
        expect((await store.loadScene(room))!.elements.single['version'], 1);
        expect(errors, isEmpty);
      }
      await repository.stop();
    });
  }

  testWidgets('快照失败退避不被新编辑绕过，恢复后保存最新内容', (tester) async {
    final store = _SnapshotStore();
    final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    await store.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'fixture',
    );
    final repository = CollaborationRepository(
      sceneStore: store,
      transport: MemoryRealtimeTransport(
        hub: MemoryRealtimeRoomHub(),
        socketId: 'fixture',
      ),
    );
    await repository.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    store.attempts = 0;
    store.fail = true;
    final errors = <String>[];
    final subscription = repository.errors.listen(errors.add);
    addTearDown(subscription.cancel);
    addTearDown(repository.stop);

    await repository.broadcastElements(
      room: room,
      elements: _scene(1).elements,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(store.attempts, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(store.attempts, 2);
    await repository.broadcastElements(
      room: room,
      elements: _scene(2).elements,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(store.attempts, 2, reason: '第二次失败后等待 4 秒，编辑不绕过退避');
    await tester.pump(const Duration(seconds: 2));
    expect(store.attempts, 3);
    for (final delay in [8, 16, 30]) {
      final attempts = store.attempts;
      await tester.pump(Duration(seconds: delay - 1));
      expect(store.attempts, attempts);
      await tester.pump(const Duration(seconds: 1));
      expect(store.attempts, attempts + 1);
    }
    store.fail = false;
    await tester.pump(const Duration(seconds: 29));
    expect(store.attempts, 6, reason: '达到 30 秒上限后仍保持退避');
    await tester.pump(const Duration(seconds: 1));
    expect(store.attempts, 7);
    expect((await store.loadScene(room))!.elements.single['version'], 2);
    expect(errors, hasLength(6));

    await repository.broadcastElements(
      room: room,
      elements: _scene(3).elements,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(store.attempts, 8, reason: '成功后恢复空闲保存');
    expect((await store.loadScene(room))!.elements.single['version'], 3);
    await tester.runAsync(repository.stop);
  });

  test('显式刷新跳过退避且旧房失败不污染新房快照', () async {
    final store = _SnapshotStore();
    final roomA = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    final roomB = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    for (final room in [roomA, roomB]) {
      await store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'fixture',
      );
    }
    final repository = CollaborationRepository(
      sceneStore: store,
      transport: MemoryRealtimeTransport(
        hub: MemoryRealtimeRoomHub(),
        socketId: 'fixture',
      ),
    );
    addTearDown(repository.stop);
    final errors = <String>[];
    final subscription = repository.errors.listen(errors.add);
    addTearDown(subscription.cancel);
    await repository.joinRoom(room: roomA, localScene: ExcalidrawScene.empty());
    store.attempts = 0;
    store.fail = true;
    await repository.broadcastElements(
      room: roomA,
      elements: _scene(1).elements,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await repository.forceFlushSnapshot();
    expect(store.attempts, 1);
    store.fail = false;
    await repository.forceFlushSnapshot();
    expect(store.attempts, 2);

    final gate = Completer<void>();
    store.gate = gate;
    store.fail = true;
    await repository.broadcastElements(
      room: roomA,
      elements: _scene(2).elements,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final flushing = repository.forceFlushSnapshot();
    await Future<void>.delayed(Duration.zero);
    expect(store.attempts, 3);
    await repository.joinRoom(room: roomB, localScene: ExcalidrawScene.empty());
    gate.complete();
    await flushing;
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1), reason: '只保留显式刷新失败，旧房异步失败不得再发布');
    store.gate = null;
    store.fail = false;
    await repository.forceFlushSnapshot();
    expect(store.attempts, 3, reason: '旧房失败不得使新房 dirty');
    await repository.broadcastElements(
      room: roomB,
      elements: _scene(9).elements,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await repository.forceFlushSnapshot();
    expect((await store.loadScene(roomB))!.elements.single['version'], 9);
    expect(store.attempts, 4, reason: '新房只需保存一次，无旧房重试');
    await repository.stop();
  });
}

class _SnapshotStore extends MemoryEncryptedSceneStore {
  int attempts = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    attempts++;
    final shouldFail = fail;
    if (gate != null) await gate!.future;
    if (shouldFail) throw StateError('fixture snapshot unavailable');
    await super.saveScene(room: room, scene: scene);
  }
}

ExcalidrawScene _scene(int version) => ExcalidrawScene.empty().copyWith(
  elements: [
    {
      'id': 'fixture',
      'type': 'rectangle',
      'version': version,
      'versionNonce': 10,
      'updated': 1,
      'isDeleted': false,
      'index': 'a0',
      'x': version,
      'y': 0,
      'width': 10,
      'height': 10,
    },
  ],
);
