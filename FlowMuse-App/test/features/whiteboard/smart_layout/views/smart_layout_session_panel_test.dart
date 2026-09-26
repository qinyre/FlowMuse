import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_panel.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_view.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import '../recognition/fake_recognition_transport.dart';
import 'package:google_fonts/google_fonts.dart';

/// 真实入口宿主回归：生产结构 = 根 ProviderScope（app 级）内嵌面板。
/// Riverpod 3 把未声明 dependencies 的 provider 解析到根容器，嵌套
/// ProviderScope 的 overrides 不生效——曾致 deps 默认工厂抛
/// UnimplementedError 且错误态被根容器缓存，面板整块渲染成
/// ErrorWidget（release 灰框、点开始零反馈）。修复后面板以
/// UncontrolledProviderScope 手工容器承载 override，本测试固定该
/// 生产嵌套结构不回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pageId = 'page-1';

  MarkdrawController pagedController() => MarkdrawController(
    config: MarkdrawEditorConfig(
      initialLayout: CanvasLayout(
        type: CanvasLayoutType.paged,
        pages: const [
          CanvasPage(
            id: pageId,
            index: 0,
            bounds: Rect.fromLTWH(0, 0, 1200, 800),
            template: CanvasPageTemplate.blank,
          ),
        ],
      ),
    ),
  );

  Future<void> pumpProductionNesting(WidgetTester tester, Widget child) async {
    // 与生产一致：app 根 scope → 白板页 Stack → 面板（自带 scope）。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Stack(children: [child])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final (code, message) in [
    ('network', '无法连接识别服务'),
    ('providerTimeout', '识别处理超时'),
    ('unconfigured', '识别服务尚未配置'),
  ]) {
    testWidgets('$code 故障穿透到真实面板，部分保留、新操作重试、原稿不变', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.applyResult(
        AddElementResult(
          RectangleElement(
            id: const ElementId('frame'),
            x: 0,
            y: 0,
            width: 1200,
            height: 800,
            customData: const {
              'flowMuse': {'role': 'page', 'pageId': pageId},
            },
          ),
        ),
      );
      controller.applyResult(
        AddElementResult(
          TextElement(
            id: const ElementId('text'),
            x: 200,
            y: 200,
            width: 400,
            height: 30,
            text: '可用的原生正文',
            fontSize: 20,
            fontFamily: 'Excalifont',
            customData: const {
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
      controller.applyResult(
        AddElementResult(
          FreedrawElement(
            id: const ElementId('ink'),
            x: 200,
            y: 400,
            width: 60,
            height: 10,
            points: const [Point(0, 4), Point(30, 4), Point(60, 8)],
            isComplete: true,
            strokeWidth: 2,
            customData: const {
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
      final transport = FakeRecognitionTransport(
        errorFactory: code == 'network'
            ? (_) async => Exception('offline')
            : null,
        responder: (_) async =>
            (503, errorEnvelopeJson(code, 'test detail', false)),
      );
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        serverUri: Uri.parse('https://server.test'),
        pageId: pageId,
        post: transport.post,
      );
      addTearDown(scope.dispose);
      await pumpProductionNesting(
        tester,
        SmartLayoutSessionPanel(scope: scope, onClose: () {}),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SmartLayoutSessionView)),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier);
      final before = SceneFingerprint.of(controller.currentScene);
      await tester.runAsync(vm.startAnalysis);
      await tester.pumpAndSettle();
      final failed = container.read(smartLayoutSessionViewModelProvider);
      expect(failed.phase, SmartLayoutSessionPhase.reviewing);
      expect(failed.reviewContext?.recognitionFailure, isNotNull);
      expect(find.textContaining(message), findsOneWidget);
      expect(failed.canApply, isFalse, reason: '缺测时默认保留原稿，不能直接应用');
      expect(find.textContaining('分析信息不足'), findsOneWidget);
      expect(SceneFingerprint.of(controller.currentScene), before);
      final oldOperation = failed.activeTicket!.operationId;
      transport.errorFactory = null;
      transport.responder = (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return request['stage'] == 'structure'
            ? buildStructureResponseBody(request)
            : buildBatchResponseBody(request, textOf: (_) => '识别后的正文');
      };
      await tester.ensureVisible(find.text('重新分析'));
      await tester.runAsync(() async {
        await tester.tap(find.text('重新分析'));
      });
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (container.read(smartLayoutSessionViewModelProvider).phase !=
            SmartLayoutSessionPhase.analyzing) {
          break;
        }
      }
      await tester.pumpAndSettle();
      final recovered = container.read(smartLayoutSessionViewModelProvider);
      expect(recovered.phase, SmartLayoutSessionPhase.reviewing);
      expect(recovered.activeTicket!.operationId, isNot(oldOperation));
      expect(recovered.reviewContext?.recognitionFailure, isNull);
      expect(recovered.validatedCards, isNotEmpty);
      expect(find.textContaining(message), findsNothing);
      expect(SceneFingerprint.of(controller.currentScene), before);
      // 审阅过程中画布变化：应用走守卫拒绝，不覆盖新文字；可重新分析。
      controller.applyResult(
        AddElementResult(
          TextElement(
            id: const ElementId('late'),
            x: 200,
            y: 700,
            width: 200,
            height: 30,
            text: '新内容',
            fontSize: 20,
            fontFamily: 'Excalifont',
            customData: const {
              'flowMuse': {'pageId': pageId},
            },
          ),
        ),
      );
      final changed = SceneFingerprint.of(controller.currentScene);
      await tester.tap(find.text('应用所选排版'));
      await tester.pumpAndSettle();
      expect(find.textContaining('画布或当前页已变化'), findsOneWidget);
      expect(find.text('重新分析'), findsOneWidget);
      expect(SceneFingerprint.of(controller.currentScene), changed);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('根 scope 内嵌面板：deps override 生效，idle 面板完整渲染', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final controller = pagedController();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
    );
    addTearDown(scope.dispose);

    await pumpProductionNesting(
      tester,
      SmartLayoutSessionPanel(scope: scope, onClose: () {}),
    );

    expect(find.text('智能排版'), findsOneWidget);
    expect(find.text('开始智能排版'), findsOneWidget);
    expect(find.textContaining('整理当前页'), findsOneWidget);
  });

  testWidgets('根 scope 内嵌面板：开始可点且空页如实显示无候选', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final controller = pagedController();
    addTearDown(controller.dispose);
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://127.0.0.1:9'),
      pageId: pageId,
    );
    addTearDown(scope.dispose);

    await pumpProductionNesting(
      tester,
      SmartLayoutSessionPanel(scope: scope, onClose: () {}),
    );

    // V3 空页无需旧识别引擎或网络；完成分析后如实呈现空候选。
    await tester.tap(find.text('开始智能排版'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('本次分析没有可用的排版候选'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('面板卸载释放场景监听，重新打开建立独立会话', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final controller = pagedController();
    addTearDown(controller.dispose);
    final listenerCount = controller.sceneChangeListeners.length;
    final original = SceneFingerprint.of(controller.currentScene);

    for (var i = 0; i < 2; i++) {
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        serverUri: Uri.parse('http://127.0.0.1:9'),
        pageId: pageId,
      );
      addTearDown(scope.dispose);
      await pumpProductionNesting(
        tester,
        SmartLayoutSessionPanel(scope: scope, onClose: () {}),
      );
      expect(controller.sceneChangeListeners, hasLength(listenerCount + 1));
      expect(find.text('开始智能排版'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(scope.isDisposed, isTrue);
      expect(controller.sceneChangeListeners, hasLength(listenerCount));
      expect(SceneFingerprint.of(controller.currentScene), original);
    }
  });
}
