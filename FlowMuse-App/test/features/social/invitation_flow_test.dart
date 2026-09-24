import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/repositories/invitation_device_store.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';
import 'package:flow_muse/features/social/view_models/invitation_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'social_widgets_test.dart' show TestInbox;

Map<String, dynamic> deviceJson(SocialDevice d) => {
  'id': d.id,
  'userId': d.userId,
  'keyId': d.keyId,
  'publicKey': d.publicKey,
  'fingerprint': d.fingerprint,
  'label': d.label,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('邀请功能可用后自动准备设备，普通消息刷新不重复登记', () async {
    final store = InvitationDeviceStore(
      serverUrl: 'https://test.example',
      userId: 'a',
    );
    final local = (await store.current()).device;
    var registrations = 0;
    final repo = SocialRepository(
      serverUrl: 'https://test.example',
      token: 'test',
      client: MockClient((request) async {
        expect(request.url.path, '/api/social/devices');
        expect(request.method, 'POST');
        registrations++;
        return http.Response(
          jsonEncode(deviceJson(local)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final controller = InvitationController(repo, store);
    final inbox = TestInbox(const SocialState());
    final container = ProviderContainer(
      overrides: [
        socialViewModelProvider.overrideWith(() => inbox),
        invitationControllerProvider.overrideWithValue(controller),
      ],
    );
    addTearDown(() {
      container.dispose();
      controller.close();
      repo.close();
    });
    container.listen(invitationDeviceRegistrationProvider, (_, _) {});
    await container.read(invitationDeviceRegistrationProvider.future);
    expect(registrations, 0);
    const ready = SocialState(
      status: SocialStatus.ready,
      me: SocialMe(
        person: SocialPerson(id: 'a', name: 'A', friendCode: 'ABCDEFGHJKLM'),
        unreadCount: 0,
        pendingRequestCount: 0,
        textMessages: true,
        invitations: true,
      ),
    );
    inbox.update(ready);
    await container.pump();
    await container.read(invitationDeviceRegistrationProvider.future);
    expect(registrations, 1);
    inbox.update(ready.copyWith(revision: 1));
    await container.pump();
    await container.read(invitationDeviceRegistrationProvider.future);
    expect(registrations, 1);
  });

  test('无需手工核验即可定向加密邀请，网络重试保持原请求', () async {
    final a = InvitationDeviceStore(
      serverUrl: 'https://test.example',
      userId: 'a',
    );
    final b = InvitationDeviceStore(
      serverUrl: 'https://test.example',
      userId: 'b',
    );
    final ad = (await a.current(label: 'test')).device,
        bd = (await b.current(label: 'test')).device;
    Map<String, dynamic>? sent;
    final bodies = <String>[];
    var failOnce = true;
    final roomKey = invitationBase64(List.generate(16, (i) => i));
    Map<String, dynamic> invite() => {
      'id': sent!['inviteId'],
      'roomId': sent!['roomId'],
      'senderId': 'a',
      'recipientId': 'b',
      'conversationId': 'c',
      'status': 'accepted',
      'version': '2',
      'expiresAt': sent!['expiresAt'],
    };
    SocialRepository repo(String user) => SocialRepository(
      serverUrl: 'https://test.example',
      token: user,
      client: MockClient((r) async {
        final path = r.url.path;
        if (path.endsWith('/devices') && r.method == 'POST') {
          return http.Response(
            jsonEncode(deviceJson(user == 'a' ? ad : bd)),
            200,
          );
        }
        if (path.contains('/friends/')) {
          return http.Response(
            jsonEncode({
              'keysetVersion': '2',
              'items': [deviceJson(user == 'a' ? bd : ad)],
            }),
            200,
          );
        }
        if (path.endsWith('/invitations')) {
          bodies.add(r.body);
          // Avoid printing secret values even on assertion failure.
          expect(r.body.contains(roomKey), isFalse);
          expect(r.body.contains('ownerKey'), isFalse);
          sent = jsonDecode(r.body);
          if (failOnce) {
            failOnce = false;
            throw http.ClientException('timeout');
          }
          return http.Response(jsonEncode(invite()), 200);
        }
        if (path.endsWith('/accept')) {
          return http.Response(
            jsonEncode({
              'invitation': invite(),
              'envelope': (sent!['envelopes'] as List).single,
            }),
            200,
          );
        }
        throw StateError('Unexpected request');
      }),
    );
    final ar = repo('a'), br = repo('b');
    final sender = InvitationController(ar, a),
        receiver = InvitationController(br, b);
    Future<SocialInvitation> send() => sender.send(
      roomId: 'room',
      roomKey: roomKey,
      recipientId: 'b',
      stillCurrent: () => true,
    );
    await expectLater(
      send(),
      throwsA(isA<SocialException>().having((e) => e.code, 'code', 'network')),
    );
    final result = await send();
    expect(bodies.length, 2);
    expect(bodies[0] == bodies[1], isTrue);
    final opened = await receiver.accept(result.id);
    expect(opened.roomKey == roomKey, isTrue);
    expect(opened.invitation.joinedAt, 0);
    // 目录提供可用公钥，不冒充用户完成了带外核验。
    expect(await a.isTrusted(bd), isFalse);
    expect(await b.isTrusted(ad), isFalse);
    sender.close();
    receiver.close();
    ar.close();
    br.close();
  });

  test('加密过程中退出白板或切换账号，禁止晚到请求发送', () async {
    for (final changeAccount in [false, true]) {
      final a = InvitationDeviceStore(
        serverUrl: 'https://test.example',
        userId: 'a',
      );
      final b = InvitationDeviceStore(
        serverUrl: 'https://test.example',
        userId: 'b',
      );
      final ad = (await a.current(label: 'test')).device,
          bd = (await b.current(label: 'test')).device;
      await a.trust(bd);
      final directory = Completer<http.Response>();
      final waiting = Completer<void>();
      var posts = 0, current = true;
      final repo = SocialRepository(
        serverUrl: 'https://test.example',
        token: 'a',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/devices') && r.method == 'POST') {
            return http.Response(jsonEncode(deviceJson(ad)), 200);
          }
          if (r.url.path.contains('/friends/')) {
            waiting.complete();
            return directory.future;
          }
          posts++;
          return http.Response('{}', 500);
        }),
      );
      final controller = InvitationController(repo, a);
      final send = controller.send(
        roomId: 'room',
        roomKey: invitationBase64(List.filled(16, 1)),
        recipientId: 'b',
        stillCurrent: () => current,
      );
      await waiting.future;
      if (changeAccount) {
        controller.close();
      } else {
        current = false;
      }
      directory.complete(
        http.Response(
          jsonEncode({
            'keysetVersion': '2',
            'items': [deviceJson(bd)],
          }),
          200,
        ),
      );
      await expectLater(send, throwsA(isA<SocialException>()));
      expect(posts, 0);
      controller.close();
      repo.close();
      b.close();
    }
  });
}
