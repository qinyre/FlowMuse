import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
