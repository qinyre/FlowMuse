import 'dart:async';

import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('创建场景超时后重试且接受已创建的 409', () async {
    final crypto = CollaborationCrypto();
    final room = CollaborationRoom.newRoom(crypto: crypto);
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 1) return http.Response('{}', 201);
      if (requestCount == 2) throw TimeoutException('stale connection');
      expect(request.headers['connection'], 'close');
      return http.Response('', 409);
    });
    final store = HttpEncryptedSceneStore(
      serverUrl: 'http://example.test',
      crypto: crypto,
      client: client,
    );

    await store.createRoom(
      room: room,
      scene: ExcalidrawScene.empty(),
      ownerKeyHash: crypto.hashOwnerKey(
        roomId: room.roomId,
        ownerKey: 'owner-key',
      ),
    );

    expect(requestCount, 3);
  });
}
