import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

void main() {
  test('新版协商后使用 V2，旧端加入降级并在退出后恢复', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    expect(fixture.a.shouldUseLiveInkV2, isTrue);
    expect(fixture.b.shouldUseLiveInkV2, isTrue);
    final legacy = MemoryRealtimeTransport(
      hub: fixture.hub,
      socketId: 'legacy',
    );
    await legacy.connect(fixture.room.roomId);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fixture.a.shouldUseLiveInkV2, isFalse);
    expect(fixture.b.shouldUseLiveInkV2, isFalse);
    await legacy.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fixture.a.shouldUseLiveInkV2, isTrue);
    expect(fixture.b.shouldUseLiveInkV2, isTrue);
  });

  test('摘要一致不广播全量，漏收的正式元素与删除墓碑可自动修复', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final updates = <CollaborationMessage>[];
    final sub = fixture.b.encryptedMessages(fixture.room).listen(updates.add);
    addTearDown(sub.cancel);
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(updates, isEmpty);
    fixture.transport.drop = true;
    final elements = [_element('ink', false), _element('deleted', true)];
    await fixture.a.broadcastElements(room: fixture.room, elements: elements);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(fixture.elementsB, isEmpty);
    fixture.transport.drop = false;
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(fixture.elementsB.map((e) => e['id']).toSet(), {'ink', 'deleted'});
    expect(
      fixture.elementsB.firstWhere((e) => e['id'] == 'deleted')['isDeleted'],
      true,
    );
    expect(
      fixture.elementsB.firstWhere((e) => e['id'] == 'ink')['customData'],
      elements.first['customData'],
    );
    expect(
      fixture.elementsB.firstWhere((e) => e['id'] == 'ink')['pressures'],
      elements.first['pressures'],
    );
    expect(
      fixture.a.sceneRepairCount + fixture.b.sceneRepairCount,
      greaterThan(0),
    );
  });

  test('多人房间只由单个提供者初始化，新端目标过滤不会干扰既有端', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.a.broadcastElements(
      room: fixture.room,
      elements: [_element('ink', false)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final previous = <CollaborationMessage>[];
    final sub = fixture.b.encryptedMessages(fixture.room).listen(previous.add);
    addTearDown(sub.cancel);
    final newcomer = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: fixture.hub, socketId: 'c'),
      sceneStore: fixture.store,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    addTearDown(newcomer.stop);
    await newcomer.joinRoom(
      room: fixture.room,
      localScene: ExcalidrawScene.empty(),
    );
    final initial = <CollaborationMessage>[];
    final newSub = newcomer.encryptedMessages(fixture.room).listen(initial.add);
    addTearDown(newSub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      initial.where((m) => m.type == CollaborationMessageType.sceneInit),
      hasLength(1),
    );
    expect(initial.first.elements.single['id'], 'ink');
    expect(
      previous.where((m) => m.type == CollaborationMessageType.sceneInit),
      isEmpty,
    );
  });

  test('取消消息通过可靠加密通道到达，换房后不残留旧能力', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final received = fixture.b
        .encryptedMessages(fixture.room)
        .firstWhere(
          (message) => message.type == CollaborationMessageType.inkCancel,
        );
    await fixture.a.cancelLiveInk(room: fixture.room, strokeId: 'cancelled');
    expect((await received).payload['strokeId'], 'cancelled');
    await fixture.b.stop();
    expect(fixture.b.shouldUseLiveInkV2, isFalse);
  });
}

Map<String, Object?> _element(String id, bool deleted) => {
  'id': id,
  'type': 'freedraw',
  'version': 2,
  'versionNonce': 7,
  'updated': DateTime.now().millisecondsSinceEpoch,
  'isDeleted': deleted,
  'index': id,
  'x': 0,
  'y': 0,
  'width': 10,
  'height': 10,
  'points': [
    [0, 0],
    [10, 10],
  ],
  'pressures': [0.1, 0.9],
  'customData': {
    'unknown': {
      'retain': [3, 4],
    },
  },
};

class _DropTransport extends MemoryRealtimeTransport {
  _DropTransport({required super.hub}) : super(socketId: 'a');
  bool drop = false;
  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    if (!drop) await super.send(payload, volatile: volatile);
  }
}

class _Fixture {
  _Fixture(this.hub, this.transport, this.a, this.b, this.room, this.store);
  final MemoryRealtimeRoomHub hub;
  final _DropTransport transport;
  final CollaborationRepository a;
  final CollaborationRepository b;
  final CollaborationRoom room;
  final MemoryEncryptedSceneStore store;
  final subscriptions = <StreamSubscription<CollaborationMessage>>[];
  List<Map<String, Object?>> elementsB = [];
  static Future<_Fixture> open() async {
    final hub = MemoryRealtimeRoomHub();
    final transport = _DropTransport(hub: hub);
    final store = MemoryEncryptedSceneStore();
    const flags = LiveInkFlags(layeredWetInk: true, liveInkV2: true);
    final a = CollaborationRepository(
      transport: transport,
      sceneStore: store,
      flags: flags,
    );
    final b = CollaborationRepository(
      transport: MemoryRealtimeTransport(hub: hub, socketId: 'b'),
      sceneStore: store,
      flags: flags,
    );
    final room = CollaborationRoom.newRoom();
    await store.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'fixture',
    );
    await a.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    await b.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    final fixture = _Fixture(hub, transport, a, b, room, store);
    for (final repo in [a, b]) {
      fixture.subscriptions.add(
        repo.encryptedMessages(room).listen((message) {
          if (message.type == CollaborationMessageType.sceneInit ||
              message.type == CollaborationMessageType.sceneUpdate) {
            final changed = repo.reconcileRemoteElements(
              remoteElements: message.elements,
            );
            if (identical(repo, b)) {
              final byId = {for (final e in fixture.elementsB) e['id']: e};
              for (final e in changed) {
                byId[e['id']] = e;
              }
              fixture.elementsB = byId.values.toList();
            }
          }
        }),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return fixture;
  }

  Future<void> close() async {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await a.stop();
    await b.stop();
  }
}
