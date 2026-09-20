import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_panel.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/views/smart_layout_session_view.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../recognition/fake_recognition_transport.dart';

/// 原生文字 → 生产 V3 识别/语义/候选 → 真实面板纠错 → CAS 应用/撤销。
/// 不依赖服务与实机；截图是桌面 widget 渲染，不作为平板验收证据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    const fontPath = String.fromEnvironment('UX_TEST_FONT');
    if (fontPath.isNotEmpty) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
      for (final family in ['Ahem', 'Roboto', 'serif', 'Excalifont']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('审阅完整流程 ${width.toInt()}px：对照/纠错/保留/应用/一次撤销', (tester) async {
      final disabledShadows = debugDisableShadows;
      if (const bool.fromEnvironment('SMART_LAYOUT_UX_CAPTURE')) {
        // 截图保留真实阴影，避免测试替身把面板画成粗黑轮廓。
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = disabledShadows);
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.applyResult(
        AddElementResult(
          RectangleElement(
            id: const ElementId('page-frame'),
            x: 0,
            y: 0,
            width: 1200,
            height: 800,
            customData: const {
              'flowMuse': {'role': 'page', 'pageId': 'page-1'},
            },
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        controller.applyResult(
          AddElementResult(
            TextElement(
              id: ElementId('text-$i'),
              x: 200 + i * 30,
              y: 200 + i * 150,
              width: 360,
              height: 30,
              fontSize: 20,
              fontFamily: 'Excalifont',
              text: ['课堂笔记整理', '第一项：先核对内容，再调整结构。', '第二项：应用之后仍可继续编辑。'][i],
              customData: const {
                'flowMuse': {'pageId': 'page-1'},
              },
            ),
          ),
        );
      }
      final transport = FakeRecognitionTransport(
        responder: (body) async => buildStructureResponseBody(
          jsonDecode(body) as Map<String, Object?>,
        ),
      );
      final scope = SmartLayoutRealSessionScope.build(
        controller: controller,
        pageId: 'page-1',
        serverUri: Uri.parse('http://127.0.0.1:9'),
        post: transport.post,
      );
      addTearDown(scope.dispose);
      final boundary = GlobalKey();
      final appTheme = AppTheme.fromPreset(defaultThemePreset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme,
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
                          child: SmartLayoutSessionPanel(
                            scope: scope,
                            onClose: () {},
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SmartLayoutSessionView)),
      );
      final vm = container.read(smartLayoutSessionViewModelProvider.notifier);
      SmartLayoutSessionUiState state() =>
          container.read(smartLayoutSessionViewModelProvider);
      final before = SceneFingerprint.of(controller.currentScene);
      await tester.runAsync(vm.startAnalysis);
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pumpAndSettle();
      expect(state().phase, SmartLayoutSessionPhase.reviewing);
      expect(state().validatedCards, isNotEmpty);
      expect(state().reviewContext, isNotNull);
      expect(state().reviewContext!.recognitionFailure, isNull);
      expect(transport.decodedBodies('read'), isEmpty, reason: '原生文字不 OCR');
      expect(transport.decodedBodies('structure'), hasLength(1));
      final analyzedRequests = transport.requests.length;
      expect(
        Theme.of(
          tester.element(find.byType(SmartLayoutSessionView)),
        ).colorScheme,
        appTheme.colorScheme,
        reason: '截图与真实面板必须沿用应用主题，不能用 Flutter 默认紫色',
      );
      expect(
        tester
            .widget<Material>(
              find.descendant(
                of: find.widgetWithText(FilledButton, '应用所选排版'),
                matching: find.byType(Material),
              ),
            )
            .color,
        appTheme.colorScheme.primary,
        reason: '主要操作按钮使用应用主色',
      );
      final captured = state().reviewContext!.originalScene;
      final sourceBlock =
          state().reviewContext!.document.blocks[width > 720 ? 1 : 0];
      final targetRole = sourceBlock.role == SemanticRole.title
          ? SemanticRole.body
          : SemanticRole.title;
      final oldText = state()
          .selectedValidatedCandidate!
          .reduced
          .scene
          .activeElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == sourceBlock.text);

      expect(find.text('合并所选区域'), findsNothing);
      expect(find.textContaining('评分 '), findsNothing);
      if (width > 720) {
        await tester.tap(find.text('并排对照'));
        await tester.pump();
        expect(find.byType(RawImage), findsNWidgets(2));
      } else {
        expect(find.text('并排对照'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, '原稿'));
        await tester.pump();
        expect(find.text('分析时的原稿'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, '排版结果'));
        await tester.pump();
      }
      await tester.tap(find.byTooltip('放大预览'));
      await tester.pump();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.tap(find.byTooltip('适合页面'));
      await tester.pump();
      try {
        await _capture(tester, boundary, 'review-${width.toInt()}');
      } finally {
        debugDisableShadows = disabledShadows;
      }

      Future<void> openCorrections() async {
        if (find.byType(DropdownButton<String>).evaluate().isNotEmpty) return;
        await tester.ensureVisible(find.textContaining('调整内容块'));
        await tester.tap(find.textContaining('调整内容块'));
        await tester.pumpAndSettle();
      }

      await openCorrections();
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged!(sourceBlock.id);
      await tester.pump();
      final roleButton = find.text(
        targetRole == SemanticRole.title ? '作为标题' : '作为正文',
      );
      await tester.ensureVisible(roleButton);
      await tester.runAsync(() async {
        await tester.tap(roleButton);
      });
      for (var i = 0; i < 20 && state().isCorrecting; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(state().isCorrecting, isFalse);
      expect(state().correctionError, isNull);
      expect(
        state().reviewContext!.document.blocks
            .firstWhere((b) => b.id == sourceBlock.id)
            .role,
        targetRole,
      );
      final newText = state()
          .selectedValidatedCandidate!
          .reduced
          .scene
          .activeElements
          .whereType<TextElement>()
          .firstWhere((e) => e.text == sourceBlock.text);
      expect(newText.fontSize, isNot(oldText.fontSize), reason: '真实预览字号随角色改变');
      expect(state().reviewContext!.originalScene, same(captured));
      expect(SceneFingerprint.of(controller.currentScene), before);

      await openCorrections();
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        sourceBlock.id,
        reason: '重跑后仍选中同一块，不误操作第一页首块',
      );
      await tester.ensureVisible(find.text('保留原件'));
      await tester.runAsync(() async {
        await tester.tap(find.text('保留原件'));
      });
      for (var i = 0; i < 20 && state().isCorrecting; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(state().correctionError, isNull);
      final candidate = state().selectedValidatedCandidate!;
      for (final id in sourceBlock.sourceIds) {
        expect(
          candidate.patch.sourceCoverage.statusOf(id),
          SourceCoverageStatus.preserved,
        );
        expect(
          candidate.reduced.scene.activeElements.firstWhere(
            (e) => e.id.value == id,
          ),
          same(captured.activeElements.firstWhere((e) => e.id.value == id)),
        );
      }
      expect(SceneFingerprint.of(controller.currentScene), before);
      expect(
        transport.requests,
        hasLength(analyzedRequests),
        reason: '对照/角色/保留不重新请求识别或整页分析',
      );
      await tester.ensureVisible(find.text('应用所选排版'));
      expect(find.text('应用所选排版').hitTestable(), findsOneWidget);
      await tester.tap(find.text('应用所选排版'));
      await tester.pumpAndSettle();
      expect(state().phase, SmartLayoutSessionPhase.applied);
      controller.undo();
      expect(SceneFingerprint.of(controller.currentScene), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('大纸张少量内容：单一真实候选、自动定位、中心缩放、找回内容和窄屏重定位', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: const ElementId('large-page'),
          x: 800,
          y: 1200,
          width: 4096,
          height: 3072,
          customData: const {
            'flowMuse': {'role': 'page', 'pageId': 'page-1'},
          },
        ),
      ),
    );
    controller.applyResult(
      AddElementResult(
        TextElement(
          id: const ElementId('small-content'),
          x: 3600,
          y: 3400,
          width: 200,
          height: 25,
          text: '预览定位回归',
          fontSize: 20,
          fontFamily: 'Excalifont',
          customData: const {
            'flowMuse': {'pageId': 'page-1'},
          },
        ),
      ),
    );
    var requests = 0;
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      pageId: 'page-1',
      serverUri: Uri.parse('http://127.0.0.1:9'),
      post:
          ({
            required url,
            required body,
            headers = const {},
            connectTimeoutMs = 8000,
            readTimeoutMs = 15000,
            cancelToken,
          }) async {
            requests++;
            throw StateError('原生文本预览不得请求模型');
          },
    );
    addTearDown(scope.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.fromPreset(defaultThemePreset),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: SingleChildScrollView(
                child: SmartLayoutSessionPanel(scope: scope, onClose: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SmartLayoutSessionView)),
    );
    final vm = container.read(smartLayoutSessionViewModelProvider.notifier);
    SmartLayoutSessionUiState state() =>
        container.read(smartLayoutSessionViewModelProvider);
    final before = SceneFingerprint.of(controller.currentScene);
    await tester.runAsync(vm.startAnalysis);
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    expect(state().phase, SmartLayoutSessionPhase.reviewing);
    expect(state().validatedCards, isNotEmpty, reason: '${state().failure}');
    final candidate = state().selectedValidatedCandidate!;
    expect(
      candidate.snapshot.viewport.offset,
      isNot(Offset.zero),
      reason: '覆盖非零页面原点',
    );
    _expectContentCentered(tester, candidate);
    TransformationController transform() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final focused = Matrix4.copy(transform().value);
    expect(
      focused.getMaxScaleOnAxis(),
      greaterThan(6),
      reason: '整页六倍上限不足以看清稀疏小字',
    );

    await tester.drag(find.byType(InteractiveViewer), const Offset(100, 40));
    await tester.pumpAndSettle();
    final center = tester
        .getSize(find.byType(InteractiveViewer))
        .center(Offset.zero);
    final anchorBeforeZoom = transform().toScene(center);
    await tester.tap(find.byTooltip('放大预览'));
    await tester.pump();
    expect(
      (transform().toScene(center) - anchorBeforeZoom).distance,
      lessThan(1e-6),
      reason: '放大保留视图中心所指内容',
    );
    await tester.tap(find.byTooltip('缩小预览'));
    await tester.pump();
    expect(
      (transform().toScene(center) - anchorBeforeZoom).distance,
      lessThan(1e-6),
    );
    await tester.fling(
      find.byType(InteractiveViewer),
      const Offset(80, 30),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byTooltip('放大预览'));
    await tester.pump();
    final afterFlingZoom = Matrix4.copy(transform().value);
    await tester.pumpAndSettle();
    expect(transform().value, afterFlingZoom, reason: '旧惯性动画不得覆盖按钮设定的视角');
    await tester.tap(find.text('回到内容'));
    await tester.pump();
    expect(transform().value, focused);
    await tester.tap(find.text('查看整页'));
    await tester.pump();
    expect(transform().value, Matrix4.identity());
    await tester.tap(find.text('回到内容'));
    await tester.pump();
    _expectContentCentered(tester, candidate);
    await _capture(tester, boundary, 'preview-sparse-focused');

    // 同名/异名但布局等价的卡已合并；单段文字不能为了测试凑两张。
    // 多候选点击/键盘切换仍由 smart_layout_session_view_test 的真实卡测试覆盖。
    expect(state().validatedCards, hasLength(1));
    await tester.tap(find.widgetWithText(ChoiceChip, '原稿'));
    await tester.pumpAndSettle();
    expect(find.text('分析时的原稿'), findsOneWidget);
    expect(transform().value.storage.every((n) => n.isFinite), isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, '并排对照'));
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNWidgets(2));

    // 横屏切到窄屏时退出并排展示，按新预览尺寸重新定位。
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsOneWidget);
    _expectContentCentered(tester, state().selectedValidatedCandidate!);
    expect(find.text('回到内容').hitTestable(), findsOneWidget);
    expect(find.text('查看整页').hitTestable(), findsOneWidget);
    expect(
      SceneFingerprint.of(controller.currentScene),
      before,
      reason: '预览操作不能改原稿',
    );
    expect(requests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _expectContentCentered(WidgetTester tester, ValidatedCandidate candidate) {
  final snapshot = candidate.snapshot;
  final layer = snapshot.layers.firstWhere((layer) => layer.kind == 'text');
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  final size = tester.getSize(find.byType(InteractiveViewer));
  final imageSize = Size(
    snapshot.image.width.toDouble(),
    snapshot.image.height.toDouble(),
  );
  final destination = Alignment.center.inscribe(
    applyBoxFit(BoxFit.contain, imageSize, size).destination,
    Offset.zero & size,
  );
  final pixelCenter = snapshot.viewport.sceneToScreen(
    Offset(
      layer.bounds.left + layer.bounds.size.width / 2,
      layer.bounds.top + layer.bounds.size.height / 2,
    ),
  );
  final scale = destination.width / imageSize.width;
  final actual = MatrixUtils.transformPoint(
    viewer.transformationController!.value,
    destination.topLeft + pixelCenter * scale,
  );
  expect(
    (actual - size.center(Offset.zero)).distance,
    lessThan(1),
    reason: '可见内容应居中，不受页面背景影响',
  );
  final visibleTextHeight =
      layer.bounds.size.height *
      snapshot.viewport.zoom *
      scale *
      viewer.transformationController!.value.getMaxScaleOnAxis();
  expect(visibleTextHeight, greaterThan(24), reason: '不是只对准几像素的小点');
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (!const bool.fromEnvironment('SMART_LAYOUT_UX_CAPTURE')) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/smart-layout-ux')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
