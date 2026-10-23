import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('创建上限写入元数据，旧服务端忽略限制时拒绝静默降级', () async {
    var supported = true;
    var sceneWrites = 0;
    final store = HttpEncryptedSceneStore(
      serverUrl: 'https://fixture.invalid',
      crypto: CollaborationCrypto(),
      client: MockClient((request) async {
        if (request.url.path == '/api/rooms') {
          expect((jsonDecode(request.body) as Map)['maxParticipants'], 4);
          return http.Response(supported ? '{"maxParticipants":4}' : '{}', 201);
        }
        sceneWrites++;
        return http.Response('', 201);
      }),
    );
    final room = CollaborationRoom.newRoom();
    await store.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'fixture',
      maxParticipants: 4,
    );
    expect(sceneWrites, 1);
    supported = false;
    await expectLater(
      store.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: 'fixture',
        maxParticipants: 4,
      ),
      throwsStateError,
    );
    expect(sceneWrites, 1);
  });

  test('移出走房主鉴权接口，权限失败不会报告成功', () async {
    var status = 204;
    final store = HttpEncryptedSceneStore(
      serverUrl: 'https://fixture.invalid',
      crypto: CollaborationCrypto(),
      authToken: 'synthetic-account',
      client: MockClient((request) async {
        expect(request.url.path.endsWith('/remove-member'), isTrue);
        expect(request.headers.containsKey('Authorization'), isTrue);
        final data = jsonDecode(request.body) as Map;
        expect(data['socketId'], 'fixture-member');
        expect(data.containsKey('ownerKey'), isTrue);
        return http.Response('', status);
      }),
    );
    final room = CollaborationRoom.newRoom();
    await store.removeMember(
      room,
      'fixture-member',
      ownerKey: 'synthetic-owner',
    );
    status = 403;
    await expectLater(
      store.removeMember(room, 'fixture-member', ownerKey: 'synthetic-owner'),
      throwsStateError,
    );
  });
  test('加载场景超时后断开长连接重试', () async {
    var attempts = 0;
    final store = HttpEncryptedSceneStore(
      serverUrl: 'http://localhost',
      crypto: CollaborationCrypto(),
      client: MockClient((request) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('stale connection');
        expect(request.headers['connection'], 'close');
        return http.Response('', 404);
      }),
    );

    final room = CollaborationRoom.newRoom(crypto: CollaborationCrypto());
    expect(await store.loadScene(room), isNull);
    expect(attempts, 2);
  });

  test('创建场景超时后重试并接受已创建的409', () async {
    var sceneAttempts = 0;
    final store = HttpEncryptedSceneStore(
      serverUrl: 'http://localhost',
      crypto: CollaborationCrypto(),
      client: MockClient((request) async {
        if (request.url.path == '/api/rooms') {
          return http.Response('{}', 201);
        }
        sceneAttempts++;
        if (sceneAttempts == 1) throw TimeoutException('stale connection');
        expect(request.headers['connection'], 'close');
        return http.Response('', 409);
      }),
    );

    final crypto = CollaborationCrypto();
    await store.createRoom(
      room: CollaborationRoom.newRoom(crypto: crypto),
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: 'owner',
    );
    expect(sceneAttempts, 2);
  });
}
