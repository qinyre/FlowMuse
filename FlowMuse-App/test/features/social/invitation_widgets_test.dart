import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/repositories/invitation_device_store.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';
import 'package:flow_muse/features/social/view_models/invitation_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flow_muse/features/social/widgets/device_security_dialog.dart';
import 'package:flow_muse/features/social/widgets/invitation_actions.dart';
import 'package:flow_muse/features/social/widgets/invitation_card.dart';
import 'social_widgets_test.dart' show TestInbox, testPerson;
import 'invitation_flow_test.dart' show deviceJson;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('粘贴安全卡不会自动信任，必须确认完整指纹', (tester) async {
    final store = InvitationDeviceStore(
      serverUrl: 'https://test.example',
      userId: 'A',
    );
    final peerStore = InvitationDeviceStore(
      serverUrl: 'https://test.example',
      userId: 'B',
    );
    final peer = (await peerStore.current()).device;
    final card = await peerStore.securityCard(testPerson.friendCode);
    final repo = SocialRepository(
      serverUrl: 'https://test.example',
      token: 'test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'keysetVersion': '1',
            'items': [deviceJson(peer)],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final controller = InvitationController(repo, store);
    addTearDown(() {
      controller.close();
      repo.close();
      peerStore.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invitationControllerProvider.overrideWithValue(controller),
          socialViewModelProvider.overrideWith(
            () => TestInbox(const SocialState(status: SocialStatus.ready)),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: DeviceSecurityDialog(peer: testPerson)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), card);
    await tester.tap(find.text('核对安全卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认好友设备'), findsOneWidget);
    expect(await store.isTrusted(peer), isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await store.isTrusted(peer), isFalse);
    await tester.tap(find.text('核对安全卡'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('已核对，信任此设备'));
    await tester.pumpAndSettle();
    expect(await store.isTrusted(peer), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字体邀请卡区分接受与加入，拒绝时使用版本并更新卡片', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = <String, dynamic>{
      'id': 'i',
      'roomId': 'r',
      'senderId': 'B',
      'recipientId': 'A',
      'conversationId': 'c',
      'status': 'accepted',
      'version': '2',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    };
    String? opened;
    final repo = SocialRepository(
      serverUrl: 'https://test.example',
      token: 'test',
      client: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, '/api/social/invitations/i/decline');
          expect(jsonDecode(r.body), {'expectedVersion': '2'});
          data['status'] = 'declined';
          data['version'] = '3';
        }
        return http.Response(jsonEncode(data), 200);
      }),
    );
    addTearDown(repo.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialSessionProvider.overrideWithValue((userId: 'A', token: 'test')),
          socialRepositoryProvider.overrideWithValue(repo),
          socialViewModelProvider.overrideWith(
            () => TestInbox(const SocialState(status: SocialStatus.ready)),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: Scaffold(
            body: InvitationActions(
              open: (id) async {
                opened = id;
              },
              send: (_, _) async {},
              child: Center(
                child: InvitationCard(
                  invitation: SocialInvitation.fromJson(data),
                  peer: testPerson,
                  canInteract: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已接受，尚未加入'), findsOneWidget);
    await tester.tap(find.text('查看并加入'));
    expect(opened, 'i');
    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();
    expect(find.text('已拒绝'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '查看并加入'))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
