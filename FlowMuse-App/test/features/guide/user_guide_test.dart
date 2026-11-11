import 'package:flow_muse/app/app_router.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/social_overlay.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/guide/models/guide_topic.dart';
import 'package:flow_muse/features/guide/view_models/guide_welcome_view_model.dart';
import 'package:flow_muse/features/guide/views/user_guide_page.dart';
import 'package:flow_muse/features/guide/widgets/guide_welcome_card.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/views/library_home_page.dart';
import 'package:flow_muse/features/settings/views/settings_page.dart';
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flow_muse/features/whiteboard/view_models/editor_preferences_view_model.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/test_library_index_notifier.dart';
import '../../support/test_local_settings_repository.dart';

class GuideEmptyLibrary extends TestLibraryIndexNotifier {
  @override
  Future<LibraryIndex> build() async => const LibraryIndex();
}

class GuideGuest extends AccountViewModel {
  @override
  AccountState build() => const AccountState(status: AccountStatus.guest);
}

class GuideShell extends ShellLayoutViewModel {
  @override
  bool build() => false;
}

class GuidePreferences extends EditorPreferencesViewModel {
  @override
  Future<EditorPreferences> build() async => EditorPreferences();
}

class _GuideInbox extends SocialInboxPresenter {
  bool opened = false;
  @override
  Future<void> Function()? get openInboxFromWhiteboard => () async {
    opened = true;
  };
}

ProviderContainer guideContainer(
  TestLocalSettingsRepository settings, {
  bool existing = false,
  AppThemeId theme = AppThemeId.day,
  SocialInboxPresenter? inbox,
}) => ProviderContainer(
  overrides: [
    guideSettingsRepositoryProvider.overrideWithValue(settings),
    libraryIndexProvider.overrideWith(
      existing ? TestLibraryIndexNotifier.new : GuideEmptyLibrary.new,
    ),
    initialThemePresetProvider.overrideWithValue(appThemePresetById(theme)),
    accountViewModelProvider.overrideWith(GuideGuest.new),
    shellLayoutViewModelProvider.overrideWith(GuideShell.new),
    editorPreferencesProvider.overrideWith(GuidePreferences.new),
    if (inbox != null) socialInboxPresenterProvider.overrideWithValue(inbox),
  ],
);

Widget guideApp(
  ProviderContainer container,
  GoRouter router, {
  double scale = 1,
  AppThemeId theme = AppThemeId.day,
  bool reduceMotion = false,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.fromPreset(appThemePresetById(theme)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
    routerConfig: router,
  ),
);

GoRouter guideRouter({String initial = '/guide/start'}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('保留的原页面')),
    ),
    GoRoute(path: '/guide', redirect: (_, _) => '/guide/start'),
    GoRoute(
      path: '/guide/:topic',
      builder: (_, state) => UserGuidePage(
        topic: GuideTopic.fromSlug(state.pathParameters['topic'])!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsPage(initialSection: 'other'),
    ),
    GoRoute(
      path: '/library',
      builder: (_, _) => const AppShell(
        section: ShellSection.library,
        child: LibraryHomePage(),
      ),
    ),
    GoRoute(
      path: '/create-note',
      builder: (_, _) => const Scaffold(body: Text('新建笔记入口')),
    ),
  ],
);

void main() {
  test('首次空库展示，关闭后下次不再展示，已有资料库不被介绍打扰', () async {
    final settings = TestLocalSettingsRepository();
    final first = guideContainer(settings);
    expect(await first.read(guideWelcomeProvider.future), isTrue);
    await first.read(guideWelcomeProvider.notifier).dismiss();
    expect(first.read(guideWelcomeProvider).asData!.value, isFalse);
    first.dispose();
    final next = guideContainer(settings);
    expect(await next.read(guideWelcomeProvider.future), isFalse);
    next.dispose();
    final oldSettings = TestLocalSettingsRepository();
    final old = guideContainer(oldSettings, existing: true);
    expect(await old.read(guideWelcomeProvider.future), isFalse);
    expect(
      await oldSettings.readBool(GuideWelcomeViewModel.storageKey),
      isTrue,
    );
    old.dispose();
  });

  test('引导偏好读取失败跳过介绍，关闭时写入失败也不阻止继续使用', () async {
    final settings = TestLocalSettingsRepository()..failRead = true;
    final container = guideContainer(settings);
    expect(await container.read(guideWelcomeProvider.future), isFalse);
    settings.failWrite = true;
    await container.read(guideWelcomeProvider.notifier).dismiss();
    expect(container.read(guideWelcomeProvider).asData!.value, isFalse);
    container.dispose();
  });

  for (final (width, scale, mode) in [
    (1280.0, 1.0, AppThemeId.day),
    (390.0, 1.0, AppThemeId.night),
    (360.0, 1.8, AppThemeId.day),
  ]) {
    testWidgets('指南 ${width}px ${scale}x 八章切换、目录与返回可用且无布局异常', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = guideContainer(
        TestLocalSettingsRepository(),
        theme: mode,
      );
      addTearDown(container.dispose);
      final router = guideRouter(initial: '/');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        guideApp(
          container,
          router,
          scale: scale,
          theme: mode,
          reduceMotion: scale > 1,
        ),
      );
      await tester.pumpAndSettle();
      router.push('/guide/start');
      await tester.pumpAndSettle();
      for (final topic in GuideTopic.values) {
        if (width < 1000) {
          await tester.tap(find.byTooltip('指南目录'));
          await tester.pumpAndSettle();
          final directory = find.byType(BottomSheet);
          final item = find.descendant(
            of: directory,
            matching: find.widgetWithText(ListTile, topic.label),
          );
          await tester.scrollUntilVisible(
            item,
            160,
            scrollable: find
                .descendant(of: directory, matching: find.byType(Scrollable))
                .first,
          );
          await tester.tap(item);
        } else {
          await tester.tap(find.text(topic.label).first);
        }
        await tester.pump(const Duration(milliseconds: 35));
        expect(find.text(topic.headline), findsOneWidget);
        await tester.pumpAndSettle();
        expect(
          GoRouterState.of(tester.element(find.byType(UserGuidePage))).uri.path,
          '/guide/${topic.name}',
        );
        expect(find.text(topic.headline), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('返回应用'));
      await tester.pumpAndSettle();
      expect(find.text('保留的原页面'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('设置 ${width}px 的常驻指南入口能进入独立页面', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = guideContainer(TestLocalSettingsRepository());
      addTearDown(container.dispose);
      final router = guideRouter(initial: '/settings');
      addTearDown(router.dispose);
      await tester.pumpWidget(guideApp(container, router));
      await tester.pumpAndSettle();
      if (width < 1000) {
        await tester.tap(find.byTooltip('设置分类'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('使用指南'));
      await tester.tap(find.text('使用指南'));
      await tester.pumpAndSettle();
      expect(find.byType(UserGuidePage), findsOneWidget);
      expect(
        GoRouterState.of(tester.element(find.byType(UserGuidePage))).uri.path,
        '/guide/start',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('首次首页卡片可在大字号滚动使用，直接开始进入新建且返回不重弹', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = TestLocalSettingsRepository();
    final container = guideContainer(settings);
    addTearDown(container.dispose);
    final router = guideRouter(initial: '/library');
    addTearDown(router.dispose);
    await tester.pumpWidget(guideApp(container, router, scale: 1.8));
    await tester.pumpAndSettle();
    expect(find.byType(GuideWelcomeCard), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(find.text('直接开始'));
    await tester.tap(find.text('直接开始'));
    await tester.pumpAndSettle();
    expect(find.text('新建笔记入口'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(GuideWelcomeCard), findsNothing);
    expect(await settings.readBool(GuideWelcomeViewModel.storageKey), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('首页了解功能使用可刷新的章节地址，返回后不再显示欢迎卡', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = guideContainer(TestLocalSettingsRepository());
    addTearDown(container.dispose);
    final router = guideRouter(initial: '/library');
    addTearDown(router.dispose);
    await tester.pumpWidget(guideApp(container, router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('了解功能'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/guide/start');
    await tester.tap(find.text('实时协作').first);
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '/guide/collaboration',
    );
    await tester.tap(find.byTooltip('返回应用'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryHomePage), findsOneWidget);
    expect(find.byType(GuideWelcomeCard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('指南标准入口及无效章节正确回退，不改变协作或通知的直达路由', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final router = createAppRouter();
    addTearDown(router.dispose);
    final context = tester.element(find.byType(SizedBox));
    for (final (input, expected) in [
      ('/guide', '/guide/start'),
      ('/guide/missing', '/guide/start'),
      ('/guide/pdf', '/guide/pdf'),
      ('/social/invitations/test-invite', '/social/invitations/test-invite'),
    ]) {
      final matches = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            RouteInformation(uri: Uri.parse(input)),
            context,
          );
      expect(matches.isError, isFalse);
      expect(matches.uri.path, expected);
    }
  });

  testWidgets('从已有白板进入指南再打开消息时复用原白板的邀请保存守卫', (tester) async {
    final inbox = _GuideInbox();
    final container = guideContainer(
      TestLocalSettingsRepository(),
      inbox: inbox,
    );
    addTearDown(container.dispose);
    final router = guideRouter(initial: '/guide/messages');
    addTearDown(router.dispose);
    await tester.pumpWidget(guideApp(container, router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('打开好友与消息'));
    await tester.tap(find.text('打开好友与消息'));
    await tester.pumpAndSettle();
    expect(inbox.opened, isTrue);
    expect(find.byType(UserGuidePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
