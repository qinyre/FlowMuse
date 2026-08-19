import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/config/live_ink_flags.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
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
    expect(negotiation.accept(const {}), isFalse);
    negotiation.reset();
    expect(negotiation.version, 0);
  });

  test('Memory transport 将 live 与可靠消息分流', () async {
    final hub = MemoryRealtimeRoomHub();
    final sender = MemoryRealtimeTransport(hub: hub, socketId: 'sender');
    final receiver = MemoryRealtimeTransport(hub: hub, socketId: 'receiver');
    await sender.connect('room');
    await receiver.connect('room');
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
}
