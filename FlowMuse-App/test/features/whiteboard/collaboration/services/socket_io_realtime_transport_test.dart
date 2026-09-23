import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/account/models/collaboration_identity.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_message.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/encrypted_payload.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

void main() {
  test('快速长笔预览不进入拥堵网络队列，完整笔画和取消仍可靠发送', () async {
    const url = 'http://long-stroke-fixture.invalid:1';
    final client = _ConnectedSocket(
      io.io(
        url,
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    io.cache[url] = client.io;
    client.io.nsps['/'] = client;
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    final store = MemoryEncryptedSceneStore();
    await store.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'fixture',
    );
    final repository = CollaborationRepository(
      transport: SocketIoRealtimeTransport(
        serverUrl: url,
        identity: CollaborationIdentity.guest('fixture'),
      ),
      sceneStore: store,
      crypto: crypto,
    );
    addTearDown(() async {
      client.onPacket = null;
      await repository.stop();
      io.cache.remove(url);
    });
    await repository.joinRoom(room: room, localScene: ExcalidrawScene.empty());
    client.packets.clear();
    Map<String, Object?> stroke(int version, int count) => {
      'id': 'long-stroke',
      'type': 'freedraw',
      'version': version,
      'versionNonce': 10,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'isDeleted': false,
      'index': 'a0',
      'x': 0,
      'y': 0,
      'width': 4096,
      'height': 17,
      'points': [
        for (var i = 0; i < count; i++) [i.toDouble(), (i % 17).toDouble()],
      ],
      'pressures': [for (var i = 0; i < count; i++) 0.25 + (i % 7) / 10],
      'customData': {'fixture': 'preserve'},
    };
    // Ordinary emit completes immediately even when the network cannot write.
    // Exercise the production repository, encryption and Socket.IO emit here.
    for (var version = 1; version <= 16; version++) {
      await repository.broadcastElements(
        room: room,
        elements: [stroke(version, version * 256)],
        latestOnly: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(client.packets.length, 0, reason: '旧预览不能交给拥堵的网络队列');
    expect(client.sendBuffer.length, 0);

    final finalStroke = stroke(16, 4096);
    for (final cancelled in [false, true]) {
      final next = cancelled
          ? {...finalStroke, 'version': 17, 'isDeleted': true}
          : finalStroke;
      final written = Completer<Map>();
      client.onPacket = written.complete;
      await repository.broadcastElements(
        room: room,
        elements: [next],
        latestOnly: cancelled,
      );
      final packet = await written.future.timeout(const Duration(seconds: 5));
      client.onPacket = null;
      final data = packet['data'] as List;
      expect(data.first, 'server-broadcast');
      final decoded = CollaborationMessage.fromBytes(
        await crypto.decrypt(
          roomKey: room.roomKey,
          encryptedPayload: EncryptedPayload.fromJson(
            Map<String, Object?>.from(data[2] as Map),
          ),
        ),
      );
      expect(decoded.elements.single['points'], finalStroke['points']);
      expect(decoded.elements.single['pressures'], finalStroke['pressures']);
      expect(decoded.elements.single['customData'], finalStroke['customData']);
      expect(decoded.elements.single['isDeleted'], cancelled);
    }
  });

  test('等待服务端 init-room 后才发送首次加入，避免登录身份查询期间丢包', () async {
    const url = 'http://join-barrier-fixture.invalid:1';
    final client = _ConnectedSocket(
      io.io(
        url,
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
      autoReady: false,
    );
    io.cache[url] = client.io;
    client.io.nsps['/'] = client;
    final transport = SocketIoRealtimeTransport(
      serverUrl: url,
      identity: CollaborationIdentity.guest('fixture'),
    );
    addTearDown(() async {
      await transport.disconnect();
      io.cache.remove(url);
    });
    final connected = transport.connect('room');
    await Future<void>.delayed(Duration.zero);
    expect(
      client.packets.where((p) => (p['data'] as List).first == 'join-room'),
      isEmpty,
    );
    client.emitEvent(['init-room', null]);
    client.emitEvent(['first-in-room', null]);
    await connected;
    expect(
      client.packets
          .where((p) => (p['data'] as List).first == 'join-room')
          .length,
      1,
    );
  });
  test('生产 send 在不可写时丢弃光标，随后正式内容仍交给 transport', () async {
    const url = 'http://collaboration-fixture.invalid:1';
    final previous = io.cache[url];
    final client = _ConnectedSocket(
      io.io(
        url,
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    io.cache[url] = client.io;
    client.io.nsps['/'] = client;
    final transport = SocketIoRealtimeTransport(
      serverUrl: url,
      identity: CollaborationIdentity.guest('fixture'),
    );
    addTearDown(() async {
      await transport.disconnect();
      if (previous == null) {
        io.cache.remove(url);
      } else {
        io.cache[url] = previous;
      }
    });
    await transport.connect('fixture-room');
    client.packets.clear();
    final payload = EncryptedPayload(
      encryptedBuffer: [1, 2, 3],
      iv: List.filled(12, 0),
    );
    for (var i = 0; i < 100; i++) {
      await transport.send(payload, volatile: true);
    }
    expect(client.packets, isEmpty);
    expect(client.sendBuffer, isEmpty);
    await transport.send(payload);
    expect(client.packets, hasLength(1));
    final data = client.packets.single['data'] as List;
    expect(data.first, 'server-broadcast');
    expect(data[1], 'fixture-room');
    expect((data[2] as Map)['encryptedBuffer'], payload.encryptedBuffer);
  });

  test('live ink 只在 writable 时调用 volatile channel', () {
    final channel = _RecordingVolatileChannel();

    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [1]),
      isFalse,
    );
    expect(channel.events, isEmpty);

    channel.writable = true;
    expect(
      emitLiveInkIfWritable(channel, 'server-live-ink', const [2]),
      isTrue,
    );
    expect(channel.events, ['server-live-ink']);
  });

  test('生产 Socket.IO adapter 的 volatile emit 不进入真实 sendBuffer', () {
    final socket = io.io(
      'http://127.0.0.1:1',
      io.OptionBuilder().disableAutoConnect().build(),
    );
    addTearDown(socket.dispose);
    final channel = SocketIoLiveInkVolatileChannel(socket);

    expect(channel.writable, isFalse);
    channel.emit('server-live-ink', const [1]);
    channel.emit('server-volatile-broadcast', const [2]);

    expect(socket.sendBuffer, isEmpty);
    socket.emit('server-broadcast', const [3]);
    expect(socket.sendBuffer, hasLength(1), reason: 'volatile 标志不能污染正式内容');
  });
}

// Keep the real Socket.emit/volatile implementation; replace only connection
// setup and the final wire write. This fixture never opens a network socket.
class _ConnectedSocket extends io.Socket {
  _ConnectedSocket(io.Socket seed, {this.autoReady = true})
    : super(seed.io, '/', {'autoConnect': false});

  final packets = <Map>[];
  final bool autoReady;
  void Function(Map)? onPacket;

  @override
  void packet(Map packet) {
    packets.add(packet);
    onPacket?.call(packet);
  }

  @override
  io.Socket connect() {
    onconnect('fixture-socket', null);
    if (autoReady) {
      emitEvent(['init-room', null]);
      emitEvent(['first-in-room', null]);
    }
    return this;
  }
}

class _RecordingVolatileChannel implements LiveInkVolatileChannel {
  @override
  bool writable = false;

  final List<String> events = [];

  @override
  void emit(String event, Object data) {
    events.add(event);
  }
}
