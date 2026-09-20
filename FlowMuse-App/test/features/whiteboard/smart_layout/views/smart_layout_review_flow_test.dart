import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:google_fonts/google_fonts.dart';

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
      for (final family in ['Ahem', 'Roboto', 'Excalifont']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('审阅完整流程 ${width.toInt()}px：对照/纠错/保留/应用/一次撤销', (tester) async {
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
              throw StateError('此原生文本场景不应请求识别');
            },
      );
      addTearDown(scope.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: Stack(
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
      await _capture(tester, boundary, 'review-${width.toInt()}');

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
      expect(requests, 0, reason: '对照/角色/保留不重新请求识别');
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
