import 'dart:convert';

import 'package:flow_muse/app/social_notice_host.dart';
import 'package:flow_muse/app/social_overlay.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/models/social_notice.dart';
import 'package:flow_muse/features/social/view_models/social_notice_preferences.dart';
import 'package:flow_muse/features/social/view_models/social_notice_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flow_muse/features/social/view_models/conversation_view_model.dart';
import 'package:flow_muse/features/social/view_models/invitation_view_model.dart';
import 'package:flow_muse/features/social/widgets/conversation_panel.dart';
import 'package:flow_muse/features/social/widgets/social_notice_settings.dart';
import 'package:flow_muse/shared/storage/local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'social_widgets_test.dart' show TestInbox, TestChat;

const peer = SocialPerson(id: 'B', name: '协作伙伴');

Finder noticeOpenTarget() => find
    .descendant(
      of: find.byType(SocialNoticeBanner),
      matching: find.byType(InkWell),
    )
    .first;

class NoticeMemorySettings extends LocalSettingsRepository {
  NoticeMemorySettings()
    : super(() => throw StateError('must not open database'));
  String? value;
  bool failWrite = false;
  @override
  Future<String?> readString(String key) async => value;
  @override
  Future<void> writeString(String key, String value) async {
    if (failWrite) throw StateError('write failed');
    this.value = value;
  }
}

class InviteTestChat extends TestChat {
  InviteTestChat() : super('chat');
  @override
  ConversationState build() => ConversationState(
    loading: false,
    messages: [chat(1, invite: invitation()).lastMessage!],
  );
}

SocialConversation chat(
  int seq, {
  String id = 'chat',
  String sender = 'B',
  int read = 0,
  SocialInvitation? invite,
}) => SocialConversation(
  id: id,
  person: peer,
  canSend: true,
  lastSeq: BigInt.from(seq),
  readSeq: BigInt.from(read),
  unreadCount: seq - read,
  updatedAt: seq,
  lastMessage: seq == 0
      ? null
      : SocialMessage(
          id: '$id-$seq',
          conversationId: id,
          seq: BigInt.from(seq),
          senderId: sender,
          clientMessageId: '$seq',
          text: '一起记录新的灵感 $seq',
          createdAt: DateTime(2026, 10, 29),
          invitation: invite,
        ),
);

SocialInvitation invitation({String status = 'pending', int? expiresAt}) =>
    SocialInvitation(
      id: 'invite',
      roomId: 'room',
      senderId: 'B',
      recipientId: 'A',
      conversationId: 'chat',
      status: status,
      version: BigInt.one,
      expiresAt:
          expiresAt ??
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
    );

SocialState snapshot(
  int revision, {
  List<SocialConversation> conversations = const [],
  bool foreground = true,
  bool connected = true,
  String user = 'A',
  List<SocialRelationship> requests = const [],
}) => SocialState(
  status: SocialStatus.ready,
  revision: revision,
  foreground: foreground,
  connected: connected,
  conversations: conversations,
  friends: [
    for (final c in conversations)
      SocialRelationship(
        id: 'friend-${c.id}',
        person: c.person,
        requesterId: 'B',
        clientRequestId: c.id,
        status: 'accepted',
        version: BigInt.one,
        conversationId: c.id,
      ),
  ],
  requests: requests,
  me: SocialMe(
    person: SocialPerson(id: user, name: user),
    unreadCount: conversations.fold(0, (n, c) => n + c.unreadCount),
    pendingRequestCount: requests.length,
    textMessages: true,
    invitations: true,
  ),
);

SocialRelationship request(String id, {String sender = 'B'}) =>
    SocialRelationship(
      id: id,
      person: peer,
      requesterId: sender,
      clientRequestId: id,
      status: 'pending',
      version: BigInt.one,
      message: '一起学习吧',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestInbox inbox;
  late ProviderContainer container;
  late NoticeMemorySettings settings;
  setUp(() async {
    inbox = TestInbox(const SocialState());
    settings = NoticeMemorySettings();
    container = ProviderContainer(
      overrides: [
        socialViewModelProvider.overrideWith(() => inbox),
        socialNoticeSettingsRepositoryProvider.overrideWithValue(settings),
        socialSessionProvider.overrideWithValue((userId: 'A', token: 'test')),
        conversationViewModelProvider(
          'chat',
        ).overrideWith(() => TestChat('chat')),
      ],
    );
    container.listen(socialNoticeProvider, (_, _) {});
    await container.read(socialNoticePreferencesProvider.future);
  });
  tearDown(() => container.dispose());

  test('首次加载静默，连续消息合并，关闭后补查不重弹，自己发送不提醒', () {
    inbox.update(snapshot(1, conversations: [chat(1)]));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(2, conversations: [chat(2)]));
    inbox.update(snapshot(3, conversations: [chat(3)]));
    expect(container.read(socialNoticeProvider).single.count, 3);
    container.read(socialNoticeProvider.notifier).dismiss('conversation:chat');
    inbox.update(snapshot(4, conversations: [chat(3)]));
    inbox.update(snapshot(5, conversations: [chat(4, sender: 'A')]));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(6, conversations: [chat(5)]));
    expect(container.read(socialNoticeProvider).single.seq, BigInt.from(5));
    inbox.update(snapshot(7, conversations: [chat(5, read: 5)]));
    expect(container.read(socialNoticeProvider), isEmpty);
  });

  test('后台、恢复前台、重连、切换账号均清理提醒并静默补历史', () {
    inbox.update(snapshot(1));
    inbox.update(snapshot(2, conversations: [chat(1)]));
    expect(container.read(socialNoticeProvider), hasLength(1));
    inbox.update(snapshot(2, foreground: false));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(2, connected: false));
    inbox.update(snapshot(3, conversations: [chat(4)], connected: false));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(3, conversations: [chat(4)]));
    inbox.update(snapshot(4, conversations: [chat(5)]));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(5, conversations: [chat(6)]));
    expect(container.read(socialNoticeProvider), hasLength(1));
    inbox.update(snapshot(6, user: 'C', conversations: [chat(9)]));
    expect(container.read(socialNoticeProvider), isEmpty);
  });

  test('当前会话不弹出，覆盖或退出会话后正常提醒，加载旧分页不误报', () {
    inbox.update(snapshot(1));
    final activity = container.read(socialNoticeActivityProvider);
    activity.conversations['panel'] = (id) => id == 'chat';
    inbox.update(snapshot(2, conversations: [chat(1)]));
    expect(container.read(socialNoticeProvider), isEmpty);
    activity.conversations.clear();
    inbox.update(snapshot(3, conversations: [chat(2)]));
    expect(container.read(socialNoticeProvider), hasLength(1));
    inbox.update(
      snapshot(
        3,
        conversations: [
          chat(2),
          chat(20, id: 'old'),
        ],
      ),
    );
    inbox.update(
      snapshot(
        4,
        conversations: [
          chat(2),
          chat(20, id: 'old'),
        ],
      ),
    );
    expect(container.read(socialNoticeProvider), hasLength(1));
  });

  test('有效协作邀请有专用提醒，撤销、过期及已读后移除', () {
    inbox.update(snapshot(1));
    inbox.update(snapshot(2, conversations: [chat(1, invite: invitation())]));
    expect(container.read(socialNoticeProvider).single.invitation, isTrue);
    inbox.update(
      snapshot(
        3,
        conversations: [chat(1, invite: invitation(status: 'revoked'))],
      ),
    );
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(
      snapshot(4, conversations: [chat(2, invite: invitation(expiresAt: 1))]),
    );
    expect(container.read(socialNoticeProvider), isEmpty);
  });

  test('好友申请去重、排除自己发起，突发提醒队列有界', () {
    inbox.update(snapshot(1));
    final requests = [request('one'), request('outgoing', sender: 'A')];
    inbox.update(snapshot(2, requests: requests));
    expect(container.read(socialNoticeProvider).single.friendRequest, isTrue);
    inbox.update(snapshot(3, requests: requests));
    expect(container.read(socialNoticeProvider), hasLength(1));
    inbox.update(
      snapshot(
        4,
        conversations: [for (var i = 0; i < 9; i++) chat(i + 1, id: 'c$i')],
      ),
    );
    expect(container.read(socialNoticeProvider), hasLength(5));
    expect(container.read(socialNoticeProvider).last.conversationId, 'c8');
  });

  test('免打扰及关闭提醒不影响未读，重新开启不重弹积压内容，保存失败保留旧值', () async {
    inbox.update(snapshot(1));
    final prefs = container.read(socialNoticePreferencesProvider.notifier);
    await prefs.save(const SocialNoticePreferences(doNotDisturb: true));
    inbox.update(snapshot(2, conversations: [chat(1)]));
    expect(container.read(socialNoticeProvider), isEmpty);
    expect(container.read(socialViewModelProvider).badgeCount, 1);
    await prefs.save(const SocialNoticePreferences());
    inbox.update(snapshot(3, conversations: [chat(1)]));
    expect(container.read(socialNoticeProvider), isEmpty);
    inbox.update(snapshot(4, conversations: [chat(2)]));
    await prefs.save(
      const SocialNoticePreferences(enabled: false, preview: false),
    );
    expect(container.read(socialNoticeProvider), isEmpty);
    expect(jsonDecode(settings.value!)['preview'], isFalse);
    settings.failWrite = true;
    await expectLater(
      prefs.save(const SocialNoticePreferences()),
      throwsStateError,
    );
    expect(
      container.read(socialNoticePreferencesProvider).asData!.value.enabled,
      isFalse,
    );
  });

  testWidgets('横幅窄屏、大字、深色及减少动画可用，预览隐藏正文，关闭与点击独立', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0, closed = 0;
    final notice = SocialNotice(
      key: 'n',
      userId: 'A',
      person: peer,
      summary: '私密消息正文',
      conversationId: 'chat',
    );
    for (final config in [
      (width: 1440.0, scale: 1.0, dark: false),
      (width: 375.0, scale: 1.0, dark: true),
      (width: 320.0, scale: 2.0, dark: true),
    ]) {
      tester.view.physicalSize = Size(config.width, 812);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(
              brightness: config.dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(config.scale),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SocialNoticeBanner(
                    notice: notice,
                    preview: false,
                    onOpen: () => opened++,
                    onDismiss: () => closed++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('私密消息正文'), findsNothing);
      if (config.scale == 1) {
        final size = tester.getSize(find.byType(SocialNoticeBanner));
        expect(size.width, lessThanOrEqualTo(360));
        expect(size.height, lessThanOrEqualTo(96), reason: '短消息不应撑成四行大卡片');
      }
      expect(tester.getSemantics(noticeOpenTarget()).label, contains('查看消息'));
      await tester.tap(noticeOpenTarget());
      final close = find.descendant(
        of: find.byType(SocialNoticeBanner),
        matching: find.byType(IconButton),
      );
      expect(tester.getSemantics(close).label, contains('关闭提醒'));
      await tester.tap(close);
      expect(tester.takeException(), isNull);
    }
    expect(opened, 3);
    expect(closed, 3);
    semantics.dispose();
  });

  testWidgets('横幅在安全区显示、自动收起且不重建底层页面；点击定位会话并保留页面', (tester) async {
    var builds = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            builds++;
            return const Scaffold(body: Text('原笔记页面'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) =>
              SocialNoticeHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    inbox.update(snapshot(1));
    inbox.update(snapshot(2, conversations: [chat(1)]));
    await tester.pumpAndSettle();
    expect(find.byType(SocialNoticeBanner), findsOneWidget);
    final before = builds;
    inbox.update(snapshot(3, conversations: [chat(2)]));
    await tester.pumpAndSettle();
    expect(builds, before);
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(find.byType(SocialNoticeBanner), findsNothing);
    inbox.update(snapshot(4, conversations: [chat(3)]));
    await tester.pumpAndSettle();
    // Use the real inbox while keeping its chat HTTP isolated.
    await tester.tap(noticeOpenTarget());
    await tester.pumpAndSettle();
    expect(find.byType(ConversationPanel), findsOneWidget);
    expect(find.text('原笔记页面'), findsOneWidget);
    inbox.update(
      snapshot(5, conversations: [chat(4)], requests: [request('new')]),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SocialNoticeBanner>(find.byType(SocialNoticeBanner))
          .notice
          .friendRequest,
      isTrue,
    );
    await tester.tap(noticeOpenTarget());
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('一起学习吧'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭消息'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationPanel), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('白板内查看邀请不退出，取消保存确认保留原画布，确认后才切换路由', (tester) async {
    var confirmed = false, guarded = 0;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) {
            container.read(socialInboxPresenterProvider).attach(
              'board',
              context,
              () async {
                guarded++;
                return confirmed;
              },
            );
            // The safety guard belongs to the board, even with its toolbar hidden.
            return const Scaffold(body: Text('仍在协作的画布'));
          },
        ),
        GoRoute(
          path: '/social/invitations/:id',
          builder: (_, _) => const Scaffold(body: Text('邀请详情')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(
      () => container.read(socialInboxPresenterProvider).detach('board'),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ProviderScope(
          overrides: [
            conversationViewModelProvider(
              'chat',
            ).overrideWith(InviteTestChat.new),
            socialInvitationProvider(
              'invite',
            ).overrideWith((ref) async => invitation()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) =>
                SocialNoticeHost(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    inbox.update(snapshot(1));
    inbox.update(snapshot(2, conversations: [chat(1, invite: invitation())]));
    await tester.pumpAndSettle();
    await tester.tap(noticeOpenTarget());
    await tester.pumpAndSettle();
    expect(guarded, 0);
    expect(find.text('仍在协作的画布'), findsOneWidget);
    await tester.tap(find.text('查看并加入'));
    await tester.pumpAndSettle();
    expect(guarded, 1);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(ConversationPanel), findsOneWidget);
    confirmed = true;
    await tester.tap(find.text('查看并加入'));
    await tester.pumpAndSettle();
    expect(guarded, 2);
    expect(
      router.routeInformationProvider.value.uri.path,
      '/social/invitations/invite',
    );
    expect(find.text('邀请详情'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('提醒设置可持久保存，失败时展示错误并保持原值', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SocialNoticeSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示消息预览'));
    await tester.pumpAndSettle();
    expect(jsonDecode(settings.value!)['preview'], isFalse);
    settings.failWrite = true;
    await tester.tap(find.text('免打扰'));
    await tester.pumpAndSettle();
    expect(find.text('未能保存提醒设置，请重试'), findsOneWidget);
    expect(
      container
          .read(socialNoticePreferencesProvider)
          .asData!
          .value
          .doNotDisturb,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('损坏的本地设置暂停提醒，避免意外恢复正文预览', () async {
    settings.value = '{invalid';
    container.invalidate(socialNoticePreferencesProvider);
    final value = await container.read(socialNoticePreferencesProvider.future);
    expect(value.enabled, isFalse);
    expect(value.preview, isFalse);
  });
}
