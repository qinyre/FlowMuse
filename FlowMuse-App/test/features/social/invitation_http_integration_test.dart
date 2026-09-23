import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:http/http.dart' as http;
import 'package:flow_muse/features/social/repositories/invitation_device_store.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';
import 'package:flow_muse/features/social/view_models/invitation_view_model.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/collaboration_room.dart';
import 'package:flow_muse/features/whiteboard/collaboration/models/excalidraw_scene.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/collaboration_crypto.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/encrypted_scene_store.dart';
import 'package:flow_muse/features/whiteboard/collaboration/services/socket_io_realtime_transport.dart';
import 'package:flow_muse/features/account/models/collaboration_identity.dart';

// Requires the disposable preview backend and the two reserved fixture accounts.
// Never point this test at production: only loopback endpoints are accepted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('FLOWMUSE_SOCIAL_TEST_URL');
  test(
    '真实 HTTP/Socket/数据库：定向邀请加入、补发新设备、撤销',
    () async {
      final uri = Uri.parse(url);
      expect(uri.host == '127.0.0.1' || uri.host == 'localhost', isTrue);
      final previousHttpOverride = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previousHttpOverride);
      FlutterSecureStorage.setMockInitialValues({});
      final client = http.Client();
      addTearDown(client.close);
      Future<Map<String, dynamic>> login(String letter) async {
        final r = await client.post(
          uri.resolve('/api/auth/login'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'email': 'invite-$letter@example.test',
            'password': 'PreviewInvite26!',
          }),
        );
        expect(r.statusCode, 200); // Never include response bodies or tokens.
        return jsonDecode(r.body) as Map<String, dynamic>;
      }

      final a = await login('a'), b = await login('b');
      final ar = SocialRepository(serverUrl: url, token: a['token']);
      final br = SocialRepository(serverUrl: url, token: b['token']);
      addTearDown(ar.close);
      addTearDown(br.close);
      final am = await ar.me(), bm = await br.me();
      final ac = InvitationController(
        ar,
        InvitationDeviceStore(serverUrl: url, userId: am.person.id),
      );
      final bc = InvitationController(
        br,
        InvitationDeviceStore(serverUrl: url, userId: bm.person.id),
      );
      addTearDown(ac.close);
      addTearDown(bc.close);
      final ad = await ac.register(), bd = await bc.register();
      addTearDown(() async {
        await ar.revokeDevice(ad.device.id);
        await br.revokeDevice(bd.device.id);
      });
      await ac.devices.trust(
        await ac.checkCard(
          await bc.devices.securityCard(bm.person.friendCode),
          bm.person,
        ),
      );
      await bc.devices.trust(
        await bc.checkCard(
          await ac.devices.securityCard(am.person.friendCode),
          am.person,
        ),
      );

      final crypto = CollaborationCrypto();
      final room = CollaborationRoom.newRoom(crypto: crypto);
      final ownerKey = crypto.generateRoomKey();
      final scenes = HttpEncryptedSceneStore(
        serverUrl: url,
        crypto: crypto,
        authToken: a['token'],
        client: client,
      );
      await scenes.createRoom(
        room: room,
        scene: ExcalidrawScene.empty(),
        ownerKeyHash: crypto.hashOwnerKey(
          roomId: room.roomId,
          ownerKey: ownerKey,
        ),
      );
      addTearDown(() => scenes.endRoom(room, ownerKey: ownerKey));
      final i = await ac.send(
        roomId: room.roomId,
        roomKey: room.roomKey,
        recipientId: bm.person.id,
        stillCurrent: () => true,
      );
      final accepted = await bc.accept(i.id);
      expect(accepted.roomKey == room.roomKey, isTrue);
      expect(accepted.invitation.joinedAt, 0);
      final joined = CollaborationRepository(
        sceneStore: HttpEncryptedSceneStore(
          serverUrl: url,
          crypto: crypto,
          authToken: b['token'],
          client: client,
        ),
        transport: SocketIoRealtimeTransport(
          serverUrl: url,
          identity: CollaborationIdentity(
            isGuest: false,
            userId: bm.person.id,
            username: 'Test B',
            token: b['token'],
          ),
        ),
      );
      addTearDown(joined.stop);
      final result = await joined.joinRoom(
        room: CollaborationRoom(roomId: i.roomId, roomKey: accepted.roomKey),
        localScene: ExcalidrawScene.empty(),
      );
      expect(result.metadata.isOwner, isFalse);
      await br.invitationJoined(i.id);
      expect((await ar.invitation(i.id)).joinedAt, greaterThan(0));

      await bc.devices.removeLocal(bd.device);
      final newer = await bc.register();
      addTearDown(() => br.revokeDevice(newer.device.id));
      await expectLater(
        bc.accept(i.id),
        throwsA(
          isA<SocialException>().having(
            (e) => e.code,
            'code',
            'device_envelope_missing',
          ),
        ),
      );
      await ac.devices.trust(
        await ac.checkCard(
          await bc.devices.securityCard(bm.person.friendCode),
          bm.person,
        ),
      );
      final updated = await ac.send(
        roomId: room.roomId,
        roomKey: room.roomKey,
        recipientId: bm.person.id,
        stillCurrent: () => true,
        supplement: await ar.invitation(i.id),
        target: newer.device,
      );
      expect(updated.id, i.id);
      expect((await bc.accept(i.id)).roomKey == room.roomKey, isTrue);
      final messages = await ar.messages(i.conversationId);
      expect(messages.items.where((m) => m.invitation?.id == i.id).length, 1);
      await ar.invitationAction(await ar.invitation(i.id), 'revoke');
      await expectLater(
        bc.accept(i.id),
        throwsA(
          isA<SocialException>().having(
            (e) => e.code,
            'code',
            'invitation_unavailable',
          ),
        ),
      );
    },
    skip: url.isEmpty ? 'Opt in with disposable loopback backend' : false,
  );
}
