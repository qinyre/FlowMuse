import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/live_ink_chunk.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/realtime_transport.dart';

void main() {
  test('ready 仅在当前房间窗口内接受一次', () async {
    final negotiation = LiveInkNegotiation();
    negotiation.begin('room-a');
    negotiation.arm(timeout: const Duration(milliseconds: 10));

    expect(
      negotiation.accept({'roomId': 'room-b', 'liveInkProtocolVersion': 2}),
      isFalse,
    );
    expect(negotiation.version, 0);
    expect(
      negotiation.accept({'roomId': 'room-a', 'liveInkProtocolVersion': 2}),
      isFalse,
    );

    negotiation.begin('room-a');
    negotiation.arm(timeout: const Duration(milliseconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      negotiation.accept({'roomId': 'room-a', 'liveInkProtocolVersion': 2}),
      isFalse,
    );

    negotiation.begin('room-a');
    negotiation.arm();
    expect(
      negotiation.accept({'roomId': 'room-a', 'liveInkProtocolVersion': 2}),
      isTrue,
    );
    expect(negotiation.version, 2);
    expect(negotiation.negotiatedRoomId, 'room-a');
    expect(negotiation.accept(const {}), isFalse);
    negotiation.reset();
    expect(negotiation.version, 0);
    expect(negotiation.negotiatedRoomId, isNull);
  });

  test('Memory transport 将 live 与可靠消息分流', () async {
    final hub = MemoryRealtimeRoomHub();
    final sender = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
    await sender.connect('room');
    await receiver.connect('room');
    expect(sender.liveInkNegotiationGeneration, 1);
    expect(sender.liveInkNegotiatedRoomId, 'room');
    final liveFrames = <Object>[];
    final reliableFrames = <Object>[];
    final liveSubscription = receiver.liveInkFrames.listen(liveFrames.add);
    final reliableSubscription = receiver.messages.listen(reliableFrames.add);
    const payload = EncryptedPayload(encryptedBuffer: [1, 2], iv: [3, 4]);

    await sender.sendLiveInk(payload);
    await Future<void>.delayed(Duration.zero);

    expect(liveFrames, hasLength(1));
    expect(reliableFrames, isEmpty);
    await liveSubscription.cancel();
    await reliableSubscription.cancel();
    await sender.disconnect();
    await receiver.disconnect();
  });

  test('断线 live 立即丢弃且不在重连后补发', () async {
    final hub = MemoryRealtimeRoomHub();
    final sender = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
    await receiver.connect('room');
    final frames = <Object>[];
    final subscription = receiver.liveInkFrames.listen(frames.add);
    const payload = EncryptedPayload(encryptedBuffer: [1], iv: [2]);

    await sender.sendLiveInk(payload);
    expect(sender.liveInkTransportNotWritableDrops, 1);
    await sender.connect('room');
    await Future<void>.delayed(Duration.zero);

    expect(frames, isEmpty);
    await subscription.cancel();
    await sender.disconnect();
    await receiver.disconnect();
  });

  test('Repository effective 值跟随服务端版本且 legacy 不发送', () async {
    final legacyHub = MemoryRealtimeRoomHub(liveInkProtocolVersion: 1);
    final transport = MemoryRealtimeTransport(
      hub: legacyHub,
      socketId: 'sender',
    );
    final repository = CollaborationRepository(
      transport: transport,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    await transport.connect('room');

    expect(repository.effectiveLiveInk, isFalse);
    await repository.sendLiveInk(
      const EncryptedPayload(encryptedBuffer: [1], iv: [2]),
    );
    expect(transport.liveInkTransportNotWritableDrops, 0);
    await transport.disconnect();
  });

  test('Repository 将 INK_CHUNK 加密后只发到 live 通道', () async {
    final hub = MemoryRealtimeRoomHub();
    final senderTransport = MemoryRealtimeTransport(
      hub: hub,
      socketId: 'sender',
    );
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
    final crypto = CollaborationCrypto();
    final sceneStore = MemoryEncryptedSceneStore();
    final repository = CollaborationRepository(
      transport: senderTransport,
      crypto: crypto,
      sceneStore: sceneStore,
      flags: const LiveInkFlags(layeredWetInk: true, liveInkV2: true),
    );
    final room = CollaborationRoom.newRoom(crypto: crypto);
    await sceneStore.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'unused',
    );
    await repository.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    await receiver.connect(room.roomId);
    final frameFuture = receiver.liveInkFrames.first;
    const chunk = LiveInkChunk(
      strokeId: 'stroke-1',
      startIndex: 0,
      points: [LiveInkPoint(x: 1, y: 2)],
      style: LiveInkStyle(
        brushType: 'fountainPen',
        strokeColor: '#1e1e1e',
        strokeWidth: 2,
        opacity: 100,
      ),
    );

    await repository.sendLiveInkChunk(room: room, chunk: chunk);
    final frame = await frameFuture;
    final plainBytes = await crypto.decrypt(
      roomKey: room.roomKey,
      encryptedPayload: frame.payload,
    );
    final decoded = CollaborationMessage.fromBytes(plainBytes);

    expect(frame.senderSocketId, 'sender');
    expect(decoded.type, CollaborationMessageType.inkChunk);
    expect(decoded.liveInkChunk?.strokeId, chunk.strokeId);
    await repository.stop();
    await receiver.disconnect();
  });
}
