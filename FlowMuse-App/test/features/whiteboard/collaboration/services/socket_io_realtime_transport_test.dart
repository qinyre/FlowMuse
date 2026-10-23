import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
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
  test('移出清理取消后续快照，已收到的画布对象保持可保存', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final client = _ConnectedSocket(
      io.io(
        'http://removed-repo.invalid:1',
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    final transport = SocketIoRealtimeTransport(
      serverUrl: 'http://removed-repo.invalid:1',
      identity: CollaborationIdentity.guest('fixture'),
      socketFactory: (_, _) => client,
    );
    final store = _EndingSceneStore();
    final repository = CollaborationRepository(
      transport: transport,
      sceneStore: store,
    );
    addTearDown(repository.stop);
    final scene = ExcalidrawScene.empty().copyWith(
      elements: const [
        {
          'id': 'fixture-element',
          'type': 'rectangle',
          'version': 1,
          'versionNonce': 1,
          'isDeleted': false,
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
          'index': 'a',
          'updated': 1,
        },
      ],
    );
    final room = await repository.startNewRoom(
      initialScene: scene,
      maxParticipants: 2,
    );
    final localCopy = await store.loadScene(room);
    expect(localCopy!.elements, hasLength(1));
    await repository.broadcastScene(room: room, scene: scene);
    final removed = repository.roomRemoved.first;
    client.emitEvent([
      'room-removed',
      {'roomId': room.roomId},
    ]);
    await removed;
    final saves = store.saves;
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(store.saves, saves);
    expect(localCopy.elements.single['id'], 'fixture-element');
    expect(repository.roomMembers, isEmpty);
    expect(transport.socketId, isNull);
  });
  test('被移出后停止连接和自动入房，忽略其他房间的移出通知', () async {
    final client = _ConnectedSocket(
      io.io(
        'http://removed-fixture.invalid:1',
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    final transport = SocketIoRealtimeTransport(
      serverUrl: 'http://removed-fixture.invalid:1',
      identity: CollaborationIdentity.guest('fixture'),
      socketFactory: (_, _) => client,
    );
    addTearDown(transport.disconnect);
    await transport.connect('fixture-room', ownerKey: 'synthetic-owner');
    final join =
        client.packets.firstWhere(
              (p) => (p['data'] as List).first == 'join-room',
            )['data']
            as List;
    expect(join[1], 'fixture-room');
    expect((join[2] as Map).containsKey('ownerKey'), isTrue);
    client.emitEvent([
      'room-removed',
      {'roomId': 'other-room'},
    ]);
    expect(transport.socketId, isNotNull);
    final removed = transport.roomRemoved.first;
    client.emitEvent([
      'room-removed',
      {'roomId': 'fixture-room'},
    ]);
    expect(await removed, 'fixture-room');
    expect(transport.socketId, isNull);
    expect(client.connected, isFalse);
    client.packets.clear();
    client.emitEvent(['init-room', null]);
    expect(client.packets, isEmpty);
    await expectLater(
      transport.send(
        EncryptedPayload(encryptedBuffer: [1], iv: List.filled(12, 0)),
      ),
      throwsStateError,
    );
  });
  test('确认丢失只重发同一密文，下一次确认后停止重试', () async {
    final client = _ConnectedSocket(
      io.io(
        'http://retry-fixture.invalid:1',
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    final transport = SocketIoRealtimeTransport(
      serverUrl: 'http://retry-fixture.invalid:1',
      identity: CollaborationIdentity.guest('fixture'),
      socketFactory: (_, _) => client,
    );
    addTearDown(transport.disconnect);
    await transport.connect('room');
    client.emitEvent([
      'live-ink-ready',
      {'roomId': 'room', 'liveInkProtocolVersion': 2, 'reliableAck': true},
    ]);
    final attempts = <Map>[];
    client.onPacket = (packet) {
      attempts.add(packet);
      if (attempts.length == 2) {
        scheduleMicrotask(
          () => client.onack({
            'id': packet['id'],
            'data': [
              {'accepted': true},
            ],
          }),
        );
      }
    };
    await transport.send(
      EncryptedPayload(encryptedBuffer: [1], iv: List.filled(12, 0)),
    );
    expect(attempts, hasLength(2));
    expect(attempts[0]['data'], attempts[1]['data']);
    expect(transport.reliableRetryCount, 1);
    expect(client.acks, isEmpty);
  });
  for (final accepted in [true, false]) {
    test('正式消息等待服务端确认，accepted=$accepted', () async {
      final client = _ConnectedSocket(
        io.io(
          'http://ack-fixture.invalid:1',
          io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
        ),
      );
      final transport = SocketIoRealtimeTransport(
        serverUrl: 'http://ack-fixture.invalid:1',
        identity: CollaborationIdentity.guest('fixture'),
        socketFactory: (_, _) => client,
      );
      addTearDown(transport.disconnect);
      await transport.connect('room');
      client.emitEvent([
        'live-ink-ready',
        {'roomId': 'room', 'liveInkProtocolVersion': 2, 'reliableAck': true},
      ]);
      Map? pending;
      client.onPacket = (packet) {
        pending = packet;
      };
      var completed = false;
      final sending = transport
          .send(EncryptedPayload(encryptedBuffer: [1], iv: List.filled(12, 0)))
          .then((_) {
            completed = true;
          });
      final expectation = accepted
          ? expectLater(sending, completes)
          : expectLater(sending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(pending?['id'], isNotNull);
      client.onack({
        'id': pending!['id'],
        'data': [
          {'accepted': accepted},
        ],
      });
      await expectation;
      expect(completed, accepted);
    });
  }
  for (final authenticated in [true, false]) {
    test('重建协作连接不复用旧登录凭据，当前登录=$authenticated', () async {
      const url = 'https://socket-auth-fixture.invalid';
      final previous = io.io(
        url,
        io.OptionBuilder()
            .disableAutoConnect()
            .setAuth({'token': 'fixture-previous'})
            .setExtraHeaders({'Authorization': 'Bearer fixture-previous'})
            .build(),
      );
      previous.dispose();
      final identity = authenticated
          ? const CollaborationIdentity(
              username: 'fixture',
              isGuest: false,
              token: 'fixture-current',
            )
          : CollaborationIdentity.guest('fixture');
      final transport = SocketIoRealtimeTransport(
        serverUrl: url,
        identity: identity,
        socketFactory: (serverUrl, options) {
          final selected = io.io(serverUrl, options);
          expect(
            authenticated
                ? selected.auth is Map &&
                      selected.auth['token'] == identity.token
                : selected.auth == null,
            isTrue,
            reason: '登录更新或退出后必须使用当前身份',
          );
          expect(identical(selected.io, previous.io), isFalse);
          return _ConnectedSocket(selected);
        },
      );
      addTearDown(() async {
        await transport.disconnect();
        previous.dispose();
        io.cache.remove('$url:443');
      });
      await transport.connect('fixture-room');
    });
  }

  for (final localEnd in [false, true]) {
    test('结束通知停止同步，主动结束=$localEnd 时不重复提示', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final url = 'http://room-ended-$localEnd.invalid:1';
      final client = _ConnectedSocket(
        io.io(
          url,
          io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
        ),
      );
      final store = _EndingSceneStore();
      final repository = CollaborationRepository(
        transport: SocketIoRealtimeTransport(
          serverUrl: url,
          identity: CollaborationIdentity.guest('fixture'),
          socketFactory: (_, _) => client,
        ),
        sceneStore: store,
      );
      final notifications = <CollaborationRoomMetadata>[];
      final subscription = repository.roomEnded.listen(notifications.add);
      addTearDown(() async {
        await subscription.cancel();
        await repository.stop();
      });
      final room = await repository.startNewRoom(
        initialScene: ExcalidrawScene.empty(),
      );
      client.emitEvent([
        'room-ended',
        {'roomId': 'old-room', 'ended': true},
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, isEmpty);
      expect(client.connected, isTrue, reason: '旧房间结束不能断开当前房间');
      final element = <String, Object?>{
        'id': 'end-fixture',
        'type': 'rectangle',
        'version': 1,
        'versionNonce': 1,
        'updated': DateTime.now().millisecondsSinceEpoch,
        'isDeleted': false,
        'index': 'a0',
        'x': 0,
        'y': 0,
        'width': 1,
        'height': 1,
      };
      await repository.broadcastElements(room: room, elements: [element]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        client.packets.any(
          (p) => (p['data'] as List).first == 'server-broadcast',
        ),
        isTrue,
      );
      final saves = store.saves;
      client.packets.clear();
      void notifyEnd() {
        for (var i = 0; i < 2; i++) {
          client.emitEvent([
            'room-ended',
            {'roomId': room.roomId, 'ended': true},
          ]);
        }
      }

      if (localEnd) {
        store.onEnd = notifyEnd;
        expect((await repository.endRoom()).ended, isTrue);
      } else {
        notifyEnd();
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifications.length, localEnd ? 0 : 1);
      expect(client.connected, isFalse);
      final packets = client.packets.length;
      await repository.forceFlushSnapshot();
      await repository.broadcastElements(
        room: room,
        elements: [
          {...element, 'version': 2},
        ],
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.saves, saves, reason: '结束后不再写入快照');
      expect(client.packets.length, packets, reason: '结束后不再发送场景');
    });
  }

  test('快速长笔预览不进入拥堵网络队列，完整笔画和取消仍可靠发送', () async {
    const url = 'http://long-stroke-fixture.invalid:1';
    final client = _ConnectedSocket(
      io.io(
        url,
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
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
        socketFactory: (_, _) => client,
      ),
      sceneStore: store,
      crypto: crypto,
    );
    addTearDown(() async {
      client.onPacket = null;
      await repository.stop();
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
    final transport = SocketIoRealtimeTransport(
      serverUrl: url,
      identity: CollaborationIdentity.guest('fixture'),
      socketFactory: (_, _) => client,
    );
    addTearDown(() async {
      await transport.disconnect();
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
    final client = _ConnectedSocket(
      io.io(
        url,
        io.OptionBuilder().disableAutoConnect().enableForceNew().build(),
      ),
    );
    final transport = SocketIoRealtimeTransport(
      serverUrl: url,
      identity: CollaborationIdentity.guest('fixture'),
      socketFactory: (_, _) => client,
    );
    addTearDown(() async {
      await transport.disconnect();
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

class _EndingSceneStore extends MemoryEncryptedSceneStore {
  void Function()? onEnd;
  var saves = 0;

  @override
  Future<CollaborationRoomMetadata> endRoom(
    CollaborationRoom room, {
    String? ownerKey,
  }) async {
    final metadata = await super.endRoom(room, ownerKey: ownerKey);
    onEnd?.call();
    // Match the server: Socket.IO notification may precede the HTTP response.
    await Future<void>.delayed(Duration.zero);
    return metadata;
  }

  @override
  Future<void> saveScene({
    required CollaborationRoom room,
    required ExcalidrawScene scene,
  }) async {
    saves++;
    await super.saveScene(room: room, scene: scene);
  }
}
