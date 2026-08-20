import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/received_live_ink_frame.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/live_ink_receive_scheduler.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

void main() {
  test('单 sender 解密中只保留最新 ciphertext', () async {
    final firstDone = Completer<void>();
    final decodedIds = <int>[];
    final scheduler = LiveInkReceiveScheduler(
      decode: (frame) async {
        final id = frame.payload.iv.single;
        if (id == 0) await firstDone.future;
        decodedIds.add(id);
        return _chunk(id);
      },
    );
    addTearDown(scheduler.close);
    final output = <DecodedLiveInkChunk>[];
    final subscription = scheduler.chunks.listen(output.add);
    addTearDown(subscription.cancel);

    scheduler.add(_frame('sender', 0));
    await _flush();
    scheduler.add(_frame('sender', 1));
    scheduler.add(_frame('sender', 2));
    expect(scheduler.pendingSenderCount, 1);

    firstDone.complete();
    await _flush(4);

    expect(decodedIds, [0, 2]);
    expect(output.map((item) => item.chunk.points.single.x), [0, 2]);
    expect(scheduler.decodeAttempts, 2);
    expect(scheduler.decodeSuccesses, 2);
    expect(scheduler.decodeErrors, 0);
  });

  test('高频 sender 排到其他 sender 后且不覆盖其 latest', () async {
    final firstDone = Completer<void>();
    final scheduler = LiveInkReceiveScheduler(
      decode: (frame) async {
        final id = frame.payload.iv.single;
        if (id == 0) await firstDone.future;
        return _chunk(id);
      },
    );
    addTearDown(scheduler.close);
    final senders = <String>[];
    final ids = <double>[];
    final subscription = scheduler.chunks.listen((item) {
      senders.add(item.senderSocketId);
      ids.add(item.chunk.points.single.x);
    });
    addTearDown(subscription.cancel);

    scheduler.add(_frame('hot', 0));
    await _flush();
    scheduler.add(_frame('hot', 1));
    for (var sender = 1; sender <= 4; sender++) {
      scheduler.add(_frame('sender-$sender', sender + 10));
    }
    scheduler.add(_frame('hot', 2));
    firstDone.complete();
    await _flush(10);

    expect(senders, [
      'hot',
      'sender-1',
      'sender-2',
      'sender-3',
      'sender-4',
      'hot',
    ]);
    expect(ids.last, 2);
  });

  test('允许 1 个 in-flight 加 8 个 pending sender 并拒绝第 10 个', () async {
    final firstDone = Completer<void>();
    final scheduler = LiveInkReceiveScheduler(
      decode: (frame) async {
        final id = frame.payload.iv.single;
        if (id == 0) await firstDone.future;
        return _chunk(id);
      },
    );
    addTearDown(scheduler.close);
    final output = <DecodedLiveInkChunk>[];
    final subscription = scheduler.chunks.listen(output.add);
    addTearDown(subscription.cancel);

    scheduler.add(_frame('sender-0', 0));
    await _flush();
    for (var sender = 1; sender <= 9; sender++) {
      scheduler.add(_frame('sender-$sender', sender));
    }

    expect(scheduler.inFlight, isTrue);
    expect(scheduler.pendingSenderCount, 8);
    expect(scheduler.senderLimitDrops, 1);

    firstDone.complete();
    await _flush(16);
    expect(output, hasLength(9));
    expect(
      output.map((item) => item.senderSocketId),
      isNot(contains('sender-9')),
    );
  });

  test('坏密文只计数并继续调度下一个 sender', () async {
    final scheduler = LiveInkReceiveScheduler(
      decode: (frame) async {
        final id = frame.payload.iv.single;
        if (id == 0) throw const FormatException('bad ciphertext');
        return _chunk(id);
      },
    );
    addTearDown(scheduler.close);
    final output = <DecodedLiveInkChunk>[];
    final subscription = scheduler.chunks.listen(output.add);
    addTearDown(subscription.cancel);

    scheduler.add(_frame('bad', 0));
    scheduler.add(_frame('good', 1));
    await _flush(5);

    expect(scheduler.decodeErrors, 1);
    expect(scheduler.decodeAttempts, 2);
    expect(scheduler.decodeSuccesses, 1);
    expect(output.single.senderSocketId, 'good');
  });

  test('live 慢解密不阻塞可靠 Scene 解密队列', () async {
    final liveGate = Completer<void>();
    final crypto = _ControlledDecryptCrypto(liveGate);
    final hub = MemoryRealtimeRoomHub();
    final receiverTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'receiver',
    );
    final senderTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'sender',
    );
    final sceneStore = MemoryEncryptedSceneStore();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    await sceneStore.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'unused',
    );
    final repository = CollaborationRepository(
      transport: receiverTransport,
      crypto: crypto,
      sceneStore: sceneStore,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    await repository.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    await senderTransport.connect(room.roomId);
    addTearDown(() async {
      if (!liveGate.isCompleted) liveGate.complete();
      await repository.stop();
      await senderTransport.disconnect();
    });

    final reliableFuture = repository.encryptedMessages(room).first;
    var liveCompleted = false;
    final liveFuture = repository.liveInkChunks.first.then((value) {
      liveCompleted = true;
      return value;
    });
    await senderTransport.sendLiveInk(_payload(1));
    await _flush();
    await senderTransport.send(_payload(2));

    final reliable = await reliableFuture.timeout(const Duration(seconds: 1));
    expect(reliable.type, CollaborationMessageType.sceneUpdate);
    expect(liveCompleted, isFalse);

    liveGate.complete();
    final live = await liveFuture.timeout(const Duration(seconds: 1));
    expect(live.senderSocketId, 'sender');
    expect(live.chunk.strokeId, 'stroke-1');
  });
}

ReceivedLiveInkFrame _frame(String sender, int id) {
  return ReceivedLiveInkFrame(senderSocketId: sender, payload: _payload(id));
}

EncryptedPayload _payload(int marker) {
  return EncryptedPayload(encryptedBuffer: [marker], iv: [marker]);
}

LiveInkChunk _chunk(int id) {
  return LiveInkChunk(
    strokeId: 'stroke-$id',
    startIndex: 0,
    points: [LiveInkPoint(x: id.toDouble(), y: id.toDouble())],
    style: const LiveInkStyle(
      brushType: 'fountainPen',
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
      opacity: 100,
    ),
  );
}

Future<void> _flush([int turns = 2]) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledDecryptCrypto extends CollaborationCrypto {
  _ControlledDecryptCrypto(this.liveGate);

  final Completer<void> liveGate;

  @override
  Future<List<int>> decrypt({
    required String roomKey,
    required EncryptedPayload encryptedPayload,
  }) async {
    switch (encryptedPayload.iv.single) {
      case 1:
        await liveGate.future;
        return CollaborationMessage.inkChunk(_chunk(1)).toBytes();
      case 2:
        return CollaborationMessage.sceneUpdate(elements: const []).toBytes();
      default:
        throw const FormatException('unknown payload');
    }
  }
}
