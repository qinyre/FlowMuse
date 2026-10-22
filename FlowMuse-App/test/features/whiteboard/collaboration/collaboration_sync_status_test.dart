import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

void main() {
  test('初始化大场景分批且定向消息不泄漏到已有成员', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final elements = [
      for (var i = 0; i < 100; i++)
        {
          ..._element('init-$i', false),
          'points': [
            for (var p = 0; p < 80; p++) [p * 1.25, p * 2.5],
          ],
          'pressures': [for (var p = 0; p < 80; p++) p / 100],
        },
    ];
    await fixture.a.broadcastScene(
      room: fixture.room,
      scene: ExcalidrawScene.empty().copyWith(elements: elements),
      syncAll: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final existing = <CollaborationMessage>[];
    final oldSub = fixture.b
        .encryptedMessages(fixture.room)
        .listen(existing.add);
    addTearDown(oldSub.cancel);
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
    final messages = <CollaborationMessage>[];
    final sub = newcomer.encryptedMessages(fixture.room).listen(messages.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final sceneMessages = messages
        .where(
          (m) =>
              m.type == CollaborationMessageType.sceneInit ||
              m.type == CollaborationMessageType.sceneUpdate,
        )
        .toList();
    expect(sceneMessages.length, greaterThan(1));
    expect(
      sceneMessages
          .where((m) => m.type == CollaborationMessageType.sceneInit)
          .length,
      1,
    );
    expect(
      sceneMessages.every((m) => m.toBytes().length + 28 <= 16 * 1024),
      isTrue,
    );
    expect(
      sceneMessages
          .expand((m) => m.elements)
          .map((e) => e['id'])
          .toSet()
          .length,
      100,
    );
    expect(existing.where((m) => m.elements.isNotEmpty), isEmpty);
  });

  test('旧端兼容补偿只由一个新版成员提供，并限制重复发送频率', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    await fixture.a.broadcastElements(
      room: fixture.room,
      elements: [_element('legacy-ink', false)],
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final legacy = MemoryRealtimeTransport(
      hub: fixture.hub,
      socketId: 'legacy',
    );
    addTearDown(legacy.disconnect);
    final received = <CollaborationMessage>[];
    final crypto = CollaborationCrypto();
    final sub = legacy.messages.listen((payload) async {
      final message = CollaborationMessage.fromBytes(
        await crypto.decrypt(
          roomKey: fixture.room.roomKey,
          encryptedPayload: payload,
        ),
      );
      if (message.type == CollaborationMessageType.sceneUpdate) {
        received.add(message);
      }
    });
    addTearDown(sub.cancel);
    await legacy.connect(fixture.room.roomId);
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(received.length, 1);
    expect(received.single.elements.single['id'], 'legacy-ink');
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(received.length, 1);
  });

  test('同版本较小nonce的正式元素可以通过增量补偿恢复', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final initial = _element('nonce-ink', false);
    await fixture.a.broadcastElements(room: fixture.room, elements: [initial]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    fixture.transport.drop = true;
    await fixture.a.broadcastElements(
      room: fixture.room,
      elements: [
        {
          ...initial,
          'versionNonce': 1,
          'pressures': [0.2, 0.8],
        },
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    fixture.transport.drop = false;
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    final restored = fixture.elementsB.single;
    expect(restored['versionNonce'], 1);
    expect(restored['pressures'], [0.2, 0.8]);
  });

  test('迟到摘要不得让已收敛的历史场景重新广播全部元素', () async {
    final fixture = await _Fixture.open(reverseIds: true);
    addTearDown(fixture.close);
    final baseline = [for (var i = 0; i < 150; i++) _element('ink-$i', false)];
    await fixture.a.broadcastElements(room: fixture.room, elements: baseline);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(fixture.elementsB.length, 150);
    final observed = <CollaborationMessage>[];
    final sub = fixture.a.encryptedMessages(fixture.room).listen(observed.add);
    addTearDown(sub.cancel);
    fixture.transport.holdNext = true;
    await fixture.a.checkSynchronization();
    expect(fixture.transport.held != null, isTrue);
    await fixture.b.broadcastElements(
      room: fixture.room,
      elements: [
        {...baseline.first, 'version': 3},
      ],
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(observed.any((m) => m.elements.length == 1), isTrue);
    await fixture.transport.releaseHeld();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(observed.where((m) => m.elements.length > 1), isEmpty);
    expect(fixture.b.sceneRepairCount, 0);
  });

  test('历史场景漏收时只补新元素与删除墓碑，不重复发送已有元素', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final baseline = [
      for (var i = 0; i < 150; i++) _element('history-$i', false),
    ];
    await fixture.a.broadcastElements(room: fixture.room, elements: baseline);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    fixture.transport.drop = true;
    final missing = [_element('missing', false), _element('deleted', true)];
    await fixture.a.broadcastElements(room: fixture.room, elements: missing);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    fixture.transport.drop = false;
    final repaired = <CollaborationMessage>[];
    final sub = fixture.b.encryptedMessages(fixture.room).listen(repaired.add);
    addTearDown(sub.cancel);
    await fixture.a.checkSynchronization();
    await fixture.b.checkSynchronization();
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(fixture.elementsB.length, 152);
    final updates = repaired.where(
      (m) => m.type == CollaborationMessageType.sceneUpdate,
    );
    expect(updates, isNotEmpty);
    expect(
      updates.every(
        (m) => m.elements.every(
          (e) => e['id'] == 'missing' || e['id'] == 'deleted',
        ),
      ),
      isTrue,
    );
    expect(
      fixture.elementsB.firstWhere((e) => e['id'] == 'deleted')['isDeleted'],
      true,
    );
  });

  test('强制补偿把多元素大场景拆成小包且保留完整点压数据', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final elements = [
      for (var i = 0; i < 80; i++)
        {
          ..._element('large-$i', false),
          'points': [
            for (var p = 0; p < 100; p++) [p * 1.25, p * 2.5],
          ],
          'pressures': [for (var p = 0; p < 100; p++) p / 100],
        },
    ];
    final messages = <CollaborationMessage>[];
    final sub = fixture.b.encryptedMessages(fixture.room).listen(messages.add);
    addTearDown(sub.cancel);
    await fixture.a.broadcastScene(
      room: fixture.room,
      scene: ExcalidrawScene.empty().copyWith(elements: elements),
      syncAll: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final updates = messages
        .where((m) => m.type == CollaborationMessageType.sceneUpdate)
        .toList();
    expect(updates.length, greaterThan(1));
    expect(updates.every((m) => m.toBytes().length + 28 <= 16 * 1024), isTrue);
    final received = {
      for (final m in updates)
        for (final e in m.elements) e['id']: e,
    };
    expect(received.length, 80);
    expect(received['large-79']!['points'], elements.last['points']);
    expect(received['large-79']!['pressures'], elements.last['pressures']);
  });

  test('非法版本目录不触发补偿或回复', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final before = fixture.b.sceneRepairCount;
    final received = <CollaborationMessage>[];
    final sub = fixture.a.encryptedMessages(fixture.room).listen(received.add);
    addTearDown(sub.cancel);
    final crypto = CollaborationCrypto();
    for (final invalid in [
      [],
      {
        'id': [1],
      },
      {
        'id': [1, -1],
      },
      {
        'id': [1.5, 7],
      },
      {
        'id': ['2', 7],
      },
    ]) {
      await fixture.transport.send(
        await crypto.encrypt(
          roomKey: fixture.room.roomKey,
          plainBytes: CollaborationMessage(
            type: CollaborationMessageType.syncStatus,
            payload: {
              'protocol': 1,
              'socketId': 'a',
              'liveInkV2': true,
              'sceneHash': List.filled(64, '0').join(),
              'versionHash': List.filled(64, '0').join(),
              'elementVersions': invalid,
              'requestVersions': true,
            },
          ).toBytes(),
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(fixture.b.sceneRepairCount, before);
    expect(received, isEmpty);
  });

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
  _DropTransport({required super.hub, super.socketId = 'a'});
  bool drop = false;
  bool holdNext = false;
  EncryptedPayload? held;

  Future<void> releaseHeld() async {
    final payload = held!;
    held = null;
    await super.send(payload);
  }

  @override
  Future<void> send(EncryptedPayload payload, {bool volatile = false}) async {
    if (holdNext) {
      holdNext = false;
      held = payload;
      return;
    }
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
  static Future<_Fixture> open({bool reverseIds = false}) async {
    final hub = MemoryRealtimeRoomHub();
    final transport = _DropTransport(
      hub: hub,
      socketId: reverseIds ? 'z' : 'a',
    );
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
