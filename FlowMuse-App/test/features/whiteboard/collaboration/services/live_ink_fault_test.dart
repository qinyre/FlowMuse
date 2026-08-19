import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_sender.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/remote_wet_ink_store.dart';

import 'fault_injecting_realtime_transport.dart';

const _style = LiveInkStyle(
  brushType: 'fountainPen',
  strokeColor: '#1e1e1e',
  strokeWidth: 2,
  opacity: 100,
);

void main() {
  test('固定 seed 的 drop/duplicate/reorder/delay 可复现且队列归零', () async {
    final first = await _runFaultSequence(20260820);
    final second = await _runFaultSequence(20260820);

    expect([...first.received]..sort(), [...second.received]..sort());
    expect(first.emitted, second.emitted);
    expect(first.dropped, second.dropped);
    expect(first.duplicated, second.duplicated);
    expect(first.pending, 0);
    expect(first.dropped, greaterThan(0));
    expect(first.duplicated, greaterThan(0));
    expect(first.received, isNot(orderedEquals([...first.received]..sort())));
  });

  test('disconnect 丢弃延迟 live 且 reconnect 后不补发', () async {
    final hub = MemoryRealtimeRoomHub();
    final base = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
    final transport = FaultInjectingRealtimeTransport(
      delegate: base,
      model: const LiveInkFaultModel(
        reorderWindow: 1,
        minDelay: Duration(milliseconds: 20),
        maxDelay: Duration(milliseconds: 20),
      ),
    );
    final received = <Object>[];
    await receiver.connect('room');
    await transport.connect('room');
    final subscription = receiver.liveInkFrames.listen(received.add);

    await transport.sendLiveInk(
      const EncryptedPayload(encryptedBuffer: [1], iv: [2]),
    );
    await transport.disconnect();
    await transport.connect('room');
    await transport.flushLiveInk();

    expect(received, isEmpty);
    expect(transport.droppedCount, 1);
    expect(transport.connectionGeneration, 2);
    await subscription.cancel();
    await transport.disconnect();
    await receiver.disconnect();
  });

  test('四种 flag 组合与 legacy 服务端只在 true/true/v2 发 live', () async {
    for (final layered in [false, true]) {
      for (final liveV2 in [false, true]) {
        final result = await _runFlagCase(
          layered: layered,
          liveV2: liveV2,
          serverVersion: 2,
        );
        final expected = layered && liveV2;
        expect(result.effective, expected);
        expect(result.emitted, expected ? 1 : 0);
      }
    }
    final legacy = await _runFlagCase(
      layered: true,
      liveV2: true,
      serverVersion: 1,
    );
    expect(legacy.effective, isFalse);
    expect(legacy.emitted, 0);
  });

  test('可靠 final 先到时清除湿墨，迟到与重复 live 不复活', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final sceneStore = MemoryEncryptedSceneStore();
    await sceneStore.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'fixture',
    );
    final hub = MemoryRealtimeRoomHub();
    final senderTransport = FaultInjectingRealtimeTransport(
      delegate: MemoryRealtimeTransport(hub: hub, socketId: 'sender'),
      model: const LiveInkFaultModel(
        duplicateRate: 1,
        reorderWindow: 5,
        minDelay: Duration(milliseconds: 5),
        maxDelay: Duration(milliseconds: 10),
      ),
    );
    final receiverTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'receiver',
    );
    final sender = CollaborationRepository(
      transport: senderTransport,
      sceneStore: sceneStore,
      crypto: crypto,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    final receiver = CollaborationRepository(
      transport: receiverTransport,
      sceneStore: sceneStore,
      crypto: crypto,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    final wetInk = RemoteWetInkStore(autoCleanup: false);
    final liveSubscription = receiver.liveInkChunks.listen(wetInk.apply);
    var receiverScene = ExcalidrawScene.empty();
    final finalApplied = Completer<void>();

    await sender.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    await receiver.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    final messageSubscription = receiver.encryptedMessages(room).listen((
      message,
    ) {
      if (message.type != CollaborationMessageType.sceneUpdate) return;
      wetInk.finalizeStrokes(
        message.elements
            .where((element) => element['type'] == 'freedraw')
            .map((element) => element['id'])
            .whereType<String>(),
      );
      receiverScene = receiver.reconcileRemoteScene(
        localScene: receiverScene,
        remoteElements: message.elements,
      );
      if (!finalApplied.isCompleted) finalApplied.complete();
    });

    await sender.sendLiveInkChunk(
      room: room,
      chunk: const LiveInkChunk(
        strokeId: 'stroke-final',
        startIndex: 0,
        points: [LiveInkPoint(x: 1, y: 2)],
        style: _style,
      ),
    );
    final finalScene = ExcalidrawScene.empty().copyWith(
      elements: [_freedrawElement('stroke-final')],
    );
    await sender.broadcastScene(room: room, scene: finalScene, syncAll: true);
    await finalApplied.future.timeout(const Duration(seconds: 2));
    await senderTransport.flushLiveInk();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(receiverScene.collaborationHash(), finalScene.collaborationHash());
    expect(wetInk.strokeCount, 0);
    expect(wetInk.isFinalized('stroke-final'), isTrue);
    expect(wetInk.dropCount(RemoteWetInkDropReason.finalized), greaterThan(0));
    expect(senderTransport.pendingCount, 0);

    await messageSubscription.cancel();
    await liveSubscription.cancel();
    wetInk.dispose();
    await sender.stop();
    await receiver.stop();
  });

  test('N 矩阵保持线性字节量且每个 accepted index 最多发送三次', () async {
    final results = <int, _SenderResult>{};
    for (final count in [250, 500, 1000, 2000]) {
      final result = await _runSender(count);
      results[count] = result;
      expect(result.pointEntries, lessThanOrEqualTo(3 * count));
      expect(result.maxRepeats, lessThanOrEqualTo(3));
    }
    for (final count in [250, 500, 1000]) {
      final ratio = results[count * 2]!.bytes / results[count]!.bytes;
      expect(ratio, inInclusiveRange(1.7, 2.3));
    }
  });

  test('5000 个 finalized ID 下 150 个 live 包均常数时间集合拒绝', () {
    final store = RemoteWetInkStore(autoCleanup: false);
    addTearDown(store.dispose);
    store.seedFinalizedStrokeIds([
      for (var index = 0; index < 5000; index++) 'stroke-$index',
    ]);

    for (var index = 0; index < 150; index++) {
      final result = store.apply(
        DecodedLiveInkChunk(
          senderSocketId: 'sender',
          chunk: LiveInkChunk(
            strokeId: 'stroke-${index % 5000}',
            startIndex: 0,
            points: const [LiveInkPoint(x: 1, y: 1)],
            style: _style,
          ),
        ),
      );
      expect(result.reason, RemoteWetInkDropReason.finalized);
    }
    expect(store.strokeCount, 0);
  });
}

Future<_FaultResult> _runFaultSequence(int seed) async {
  final hub = MemoryRealtimeRoomHub();
  final base = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
  final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
  final transport = FaultInjectingRealtimeTransport(
    delegate: base,
    model: LiveInkFaultModel(
      seed: seed,
      dropRate: 0.2,
      duplicateRate: 0.1,
      reorderWindow: 5,
      maxDelay: const Duration(milliseconds: 2),
    ),
  );
  final received = <int>[];
  await receiver.connect('room');
  await transport.connect('room');
  final subscription = receiver.liveInkFrames.listen(
    (frame) => received.add(frame.payload.encryptedBuffer.single),
  );
  for (var index = 0; index < 50; index++) {
    await transport.sendLiveInk(
      EncryptedPayload(encryptedBuffer: [index], iv: const [0]),
    );
  }
  await transport.flushLiveInk();
  await Future<void>.delayed(Duration.zero);
  final result = _FaultResult(
    received: received,
    emitted: transport.emittedCount,
    dropped: transport.droppedCount,
    duplicated: transport.duplicateCount,
    pending: transport.pendingCount,
  );
  await subscription.cancel();
  await transport.disconnect();
  await receiver.disconnect();
  return result;
}

Future<_FlagResult> _runFlagCase({
  required bool layered,
  required bool liveV2,
  required int serverVersion,
}) async {
  final hub = MemoryRealtimeRoomHub(liveInkProtocolVersion: serverVersion);
  final transport = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
  final repository = CollaborationRepository(
    transport: transport,
    flags: LiveInkFlags(layeredWetInk: layered, liveInkV2: liveV2),
  );
  final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
  var emitted = 0;
  await receiver.connect('room');
  final subscription = receiver.liveInkFrames.listen((_) => emitted++);
  await transport.connect('room');
  final effective = repository.effectiveLiveInk;
  await repository.sendLiveInk(
    const EncryptedPayload(encryptedBuffer: [1], iv: [2]),
  );
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  await transport.disconnect();
  await receiver.disconnect();
  return _FlagResult(effective, emitted);
}

Future<_SenderResult> _runSender(int count) async {
  final chunks = <LiveInkChunk>[];
  final sender = LiveInkSender(emit: (chunk) async => chunks.add(chunk));
  sender.start(strokeId: 'stroke', style: _style);
  final points = <LiveInkPoint>[];
  for (var index = 0; index < count; index++) {
    points.add(LiveInkPoint(x: index.toDouble(), y: (index % 10).toDouble()));
    if ((index + 1) % 8 == 0 || index + 1 == count) {
      final start = points.length > LiveInkChunk.maxPoints
          ? points.length - LiveInkChunk.maxPoints
          : 0;
      sender.offerTail(
        totalCount: points.length,
        startIndex: start,
        points: points.sublist(start),
      );
      while (sender.inFlight || sender.hasPending) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }
  final repeats = <int, int>{};
  var pointEntries = 0;
  var bytes = 0;
  for (final chunk in chunks) {
    pointEntries += chunk.points.length;
    bytes += utf8.encode(jsonEncode(chunk.toJson())).length;
    for (final point in chunk.indexedPoints) {
      repeats.update(point.index, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  return _SenderResult(
    pointEntries: pointEntries,
    maxRepeats: repeats.values.fold(
      0,
      (max, value) => value > max ? value : max,
    ),
    bytes: bytes,
  );
}

Map<String, Object?> _freedrawElement(String id) => {
  'id': id,
  'type': 'freedraw',
  'version': 1,
  'versionNonce': 1,
  'updated': 1700000000000,
  'isDeleted': false,
  'index': 'a0',
  'x': 0,
  'y': 0,
  'width': 1,
  'height': 2,
  'points': [
    [0, 0],
    [1, 2],
  ],
};

class _FaultResult {
  const _FaultResult({
    required this.received,
    required this.emitted,
    required this.dropped,
    required this.duplicated,
    required this.pending,
  });
  final List<int> received;
  final int emitted;
  final int dropped;
  final int duplicated;
  final int pending;
}

class _FlagResult {
  const _FlagResult(this.effective, this.emitted);
  final bool effective;
  final int emitted;
}

class _SenderResult {
  const _SenderResult({
    required this.pointEntries,
    required this.maxRepeats,
    required this.bytes,
  });
  final int pointEntries;
  final int maxRepeats;
  final int bytes;
}
