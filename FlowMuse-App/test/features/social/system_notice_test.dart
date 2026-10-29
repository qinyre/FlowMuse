import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/social/models/system_notice.dart';
import 'package:flow_muse/features/social/models/social_notice.dart';
import 'package:flow_muse/app/social_notice_host.dart';
import 'package:flow_muse/app/social_overlay.dart';
import 'package:flow_muse/features/social/widgets/social_notice_settings.dart';
import 'package:flow_muse/features/social/services/system_notice_native.dart';
import 'package:flow_muse/features/social/services/system_notice_service.dart';
import 'package:flow_muse/features/social/view_models/social_notice_preferences.dart';
import 'package:flow_muse/features/social/view_models/social_notice_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flow_muse/features/social/view_models/system_notice_view_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'social_notice_test.dart'
    show NoticeMemorySettings, snapshot, chat, request, invitation;
import 'social_widgets_test.dart' show TestInbox;

class FakeSystemNotice implements SystemNoticeService {
  SystemNoticePermission status = SystemNoticePermission.granted;
  final shown = <SystemNoticeMessage>[];
  final cancelled = <String>[];
  int clears = 0;
  Completer<SystemNoticePermission>? permissionGate;
  Completer<void>? showGate;
  void Function(SystemNoticeTarget)? tap;
  @override
  Future<SystemNoticePermission> permission({bool request = false}) async =>
      permissionGate == null ? status : permissionGate!.future;
  @override
  Future<void> initialize(void Function(SystemNoticeTarget) onTap) async {
    tap = onTap;
  }

  @override
  Future<void> show(SystemNoticeMessage notice) async {
    shown.add(notice);
    await showGate?.future;
  }

  @override
  Future<void> cancel(String tag) async {
    cancelled.add(tag);
  }

  @override
  Future<void> clear() async {
    clears++;
  }

  @override
  void dispose() {}
}

class NoticeTestPresenter extends SocialInboxPresenter {
  final opened = <SocialNotice>[];
  @override
  Future<void> Function(SocialNotice)? get openFromWhiteboard =>
      (notice) async {
        opened.add(notice);
      };
}

typedef TestSessionValue = ({String userId, String token});
final testSessionProvider = NotifierProvider<TestSession, TestSessionValue?>(
  TestSession.new,
);

class TestSession extends Notifier<TestSessionValue?> {
  @override
  TestSessionValue? build() => (userId: 'A', token: 'test');
  void logout() => state = null;
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late TestInbox inbox;
  late FakeSystemNotice service;
  late NoticeTestPresenter presenter;

  setUp(() async {
    inbox = TestInbox(snapshot(0));
    service = FakeSystemNotice();
    presenter = NoticeTestPresenter();
    container = ProviderContainer(
      overrides: [
        socialViewModelProvider.overrideWith(() => inbox),
        socialSessionProvider.overrideWith(
          (ref) => ref.watch(testSessionProvider),
        ),
        socialNoticeSettingsRepositoryProvider.overrideWithValue(
          NoticeMemorySettings(),
        ),
        systemNoticeServiceProvider.overrideWithValue(service),
        socialInboxPresenterProvider.overrideWithValue(presenter),
      ],
    );
    container.listen(systemNoticeProvider, (_, _) {});
    await container.read(socialNoticePreferencesProvider.future);
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(const SocialNoticePreferences(systemEnabled: true));
    await flush();
    inbox.update(snapshot(1, conversations: [chat(0)]));
  });
  tearDown(() => container.dispose());

  testWidgets('系统通知点击沿用白板消息入口，其他账号与过期点击不打开', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('仍在协作的画布')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              SocialNoticeHost(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    SystemNoticeTarget target(String user, int expires) => SystemNoticeTarget(
      userId: user,
      key: 'conversation:chat',
      conversationId: 'chat',
      expiresAt: expires,
    );
    final expiry = DateTime.now()
        .add(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    service.tap!(target('B', expiry));
    await tester.pumpAndSettle();
    expect(presenter.opened, isEmpty);
    service.tap!(target('A', 1));
    await tester.pumpAndSettle();
    expect(presenter.opened, isEmpty);
    service.tap!(target('A', expiry));
    await tester.pumpAndSettle();
    expect(presenter.opened.single.conversationId, 'chat');
    expect(find.text('仍在协作的画布'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('系统授权被拒不保存开启状态，允许后保留系统开关与预览设置', (tester) async {
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(const SocialNoticePreferences());
    service.status = SystemNoticePermission.denied;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SocialNoticeSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('系统提醒'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(socialNoticePreferencesProvider)
          .asData!
          .value
          .systemEnabled,
      isFalse,
    );
    expect(find.textContaining('通知未获授权'), findsOneWidget);
    service.status = SystemNoticePermission.granted;
    await tester.tap(find.text('系统提醒'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(socialNoticePreferencesProvider)
          .asData!
          .value
          .systemEnabled,
      isTrue,
    );
    await tester.tap(find.text('显示消息预览'));
    await tester.pumpAndSettle();
    final prefs = container.read(socialNoticePreferencesProvider).asData!.value;
    expect(prefs.systemEnabled, isTrue);
    expect(prefs.preview, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('前台使用横幅；后台当前聊天也通知，同会话合并，已读清除且恢复前台不重播', () async {
    container
        .read(socialNoticeActivityProvider)
        .conversations[Object()] = (_) =>
        true;
    inbox.update(snapshot(2, conversations: [chat(1)]));
    await flush();
    expect(service.shown, isEmpty);
    inbox.update(snapshot(2, foreground: false, conversations: [chat(1)]));
    inbox.update(snapshot(3, foreground: false, conversations: [chat(2)]));
    await flush();
    inbox.update(snapshot(4, foreground: false, conversations: [chat(3)]));
    await flush();
    expect(service.shown, hasLength(2));
    expect(service.shown.map((n) => n.tag).toSet(), {'A:conversation:chat'});
    inbox.update(snapshot(4, conversations: [chat(3)]));
    await flush();
    expect(container.read(socialNoticeProvider), isEmpty);
    expect(service.cancelled, contains('A:conversation:chat'));
    inbox.update(snapshot(5, conversations: [chat(3, read: 3)]));
    await flush();
    expect(service.shown, hasLength(2));
  });

  test('无授权、关闭系统提醒、免打扰均不显示，重新开启不重播历史', () async {
    service.status = SystemNoticePermission.denied;
    inbox.update(snapshot(2, foreground: false, conversations: [chat(1)]));
    await flush();
    expect(service.shown, isEmpty);
    service.status = SystemNoticePermission.granted;
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(
          const SocialNoticePreferences(
            systemEnabled: true,
            doNotDisturb: true,
          ),
        );
    inbox.update(snapshot(3, foreground: false, conversations: [chat(2)]));
    await flush();
    expect(service.shown, isEmpty);
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(const SocialNoticePreferences());
    inbox.update(snapshot(4, foreground: false, conversations: [chat(3)]));
    await flush();
    expect(service.shown, isEmpty);
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(const SocialNoticePreferences(systemEnabled: true));
    inbox.update(snapshot(5, foreground: false, conversations: [chat(3)]));
    await flush();
    expect(service.shown, isEmpty);
    inbox.update(snapshot(6, foreground: false, conversations: [chat(4)]));
    await flush();
    expect(service.shown, hasLength(1));
  });

  test('隐藏预览不泄露姓名正文，好友申请和邀请均支持，处理后取消', () async {
    await container
        .read(socialNoticePreferencesProvider.notifier)
        .save(
          const SocialNoticePreferences(systemEnabled: true, preview: false),
        );
    inbox.update(
      snapshot(
        2,
        foreground: false,
        requests: [request('friend')],
        conversations: [chat(1, invite: invitation())],
      ),
    );
    await flush();
    expect(service.shown, hasLength(2));
    expect(service.shown.map((n) => n.title).toSet(), {'FlowMuse'});
    expect(service.shown.map((n) => n.body).toSet(), {
      '你收到了一条好友申请',
      '你收到了一条协作邀请',
    });
    for (final notice in service.shown) {
      expect(notice.target.encode(), isNot(contains('一起学习')));
      expect(SystemNoticeTarget.parse(notice.target.encode()), isNotNull);
    }
    inbox.update(
      snapshot(
        3,
        foreground: false,
        conversations: [chat(1, invite: invitation(status: 'revoked'))],
      ),
    );
    await flush();
    expect(service.cancelled.toSet(), {
      'A:request:friend',
      'A:conversation:chat',
    });
  });

  test('授权结果跨退出账号失效，旧账号点击与过期/任意路由目标被拒绝', () async {
    service.permissionGate = Completer<SystemNoticePermission>();
    inbox.update(snapshot(2, foreground: false, conversations: [chat(1)]));
    await flush();
    container.read(testSessionProvider.notifier).logout();
    service.permissionGate!.complete(SystemNoticePermission.granted);
    await flush();
    expect(service.shown, isEmpty);
    final raw = {
      'version': 1,
      'userId': 'A',
      'key': 'conversation:chat',
      'conversationId': 'chat',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    };
    for (final mutation in [
      {'expiresAt': 1},
      {'conversationId': 'https://outside.test'},
      {'userId': ''},
      {'version': 99},
      {'key': 'request:other'},
    ]) {
      expect(
        SystemNoticeTarget.parse(jsonEncode({...raw, ...mutation})),
        isNull,
      );
    }
    expect(SystemNoticeTarget.parse(jsonEncode(raw)), isNotNull);
  });

  test('通知展示期间消息被已读也会取消，退出清除已提交的系统通知', () async {
    service.showGate = Completer<void>();
    inbox.update(snapshot(2, foreground: false, conversations: [chat(1)]));
    await flush();
    expect(service.shown, hasLength(1));
    inbox.update(
      snapshot(3, foreground: false, conversations: [chat(1, read: 1)]),
    );
    service.showGate!.complete();
    await flush();
    expect(service.cancelled, contains('A:conversation:chat'));
    final before = service.clears;
    container.read(testSessionProvider.notifier).logout();
    await flush();
    expect(service.clears, greaterThan(before));
  });

  test('没有原生 Channel 的旧安装包或桌面安全降级', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeSystemNoticeService.channel,
          (_) => throw MissingPluginException(),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeSystemNoticeService.channel, null),
    );
    final native = NativeSystemNoticeService();
    await native.initialize((_) => fail('No native click expected'));
    expect(await native.permission(), SystemNoticePermission.unsupported);
    await native.clear();
    native.dispose();
  });
}
