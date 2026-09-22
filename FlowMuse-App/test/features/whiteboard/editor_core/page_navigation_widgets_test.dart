import 'dart:io';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/page_thumbnail.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_path_cache.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/page_navigation_controls.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/page_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

MarkdrawController _controller(int count) {
  final controller = MarkdrawController();
  controller.setLayout(
    CanvasLayout(
      type: CanvasLayoutType.paged,
      pages: [
        for (var i = 0; i < count; i++)
          CanvasPage(
            id: 'p-$i',
            index: i,
            bounds: Rect.fromLTWH(0, i * 896, 600, 800),
            template: CanvasPageTemplate.grid,
          ),
      ],
    ),
  );
  controller.canvasSize = const Size(600, 700);
  return controller;
}

void main() {
  if (const bool.fromEnvironment('FLOWMUSE_PAGE_NAV_SCREENSHOTS')) {
    setUpAll(() async {
      final textFont = FontLoader('Roboto')
        ..addFont(
          File(
            const String.fromEnvironment(
              'FLOWMUSE_TEST_FONT',
              defaultValue: 'C:/Windows/Fonts/msyh.ttc',
            ),
          ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
        );
      final iconFont = FontLoader('MaterialIcons')
        ..addFont(
          File(
            const String.fromEnvironment(
              'FLOWMUSE_TEST_ICON_FONT',
              defaultValue:
                  'D:/Program/HarmonyOS-Flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
            ),
          ).readAsBytes().then((bytes) => bytes.buffer.asByteData()),
        );
      await Future.wait([textFont.load(), iconFont.load()]);
    });
  }
  testWidgets('page input validates bounds and navigates a large document', (
    tester,
  ) async {
    final controller = _controller(500);
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    controller.toggleViewMode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PageNavigationControls(
              controller: controller,
              onOverview: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1 / 500'));
    await tester.pumpAndSettle();
    for (final invalid in [
      '',
      '0',
      '-5',
      '1.5',
      '501',
      '9999999999999999999999999',
    ]) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(find.text('跳转'));
      await tester.pump();
      expect(find.text('请输入 1–500 之间的页码'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField), '450');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(controller.pagedViewportMetrics!.currentPageIndex, 449);
    expect(controller.historyManager.canUndo, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'overview builds only nearby cards and waits for writing to end',
    (tester) async {
      final controller = _controller(500);
      addTearDown(controller.dispose);
      controller.navigateToPage('p-250');
      controller.pagedTouchActive = true;
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 280,
                  height: 570,
                  child: PageOverview(controller: controller, onClose: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final cards = find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('page-preview-'),
      );
      expect(cards.evaluate().length, lessThan(20));
      expect(find.byKey(const ValueKey('page-preview-p-250')), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      controller.pagedTouchActive = false;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.byType(RawImage), findsWidgets);
      expect(controller.imageCache.length, 0);
      if (const bool.fromEnvironment('FLOWMUSE_PAGE_NAV_SCREENSHOTS')) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/page-navigation-overview.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'thumbnail includes crossing elements, retains formulas and cancels cleanly',
    (tester) async {
      final controller = _controller(2);
      addTearDown(controller.dispose);
      controller.applyResult(
        AddElementResult(
          RectangleElement(
            id: const ElementId('crossing'),
            x: 20,
            y: 780,
            width: 500,
            height: 350,
            roughness: 0,
            strokeWidth: 0,
            strokeColor: '#ff0000',
            backgroundColor: '#ff0000',
            fillStyle: FillStyle.solid,
          ),
        ),
      );
      controller.applyResult(
        AddElementResult(
          TextElement(
            id: const ElementId('formula'),
            x: 100,
            y: 1100,
            width: 160,
            height: 60,
            text: 'x^2',
            customData: const {
              'flowMuse': {'smartLayoutType': 'math'},
            },
          ),
        ),
      );
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        controller.applyResult(
          AddElementResult(
            FreedrawElement(
              id: ElementId('preview-${brush.name}'),
              x: 100,
              y: 1300,
              width: 150,
              height: 50,
              points: const [Point.zero, Point(100, 30), Point(150, 50)],
              pressures: const [0.7, 0.8, 0.6],
              isComplete: true,
              strokeWidth: 8,
              customData: customDataWithFreedrawRender(
                null,
                brush,
                renderVersion: BrushRenderVersion.naturalMediaV2,
              ),
            ),
          ),
        );
      }
      NaturalMediaPathCache.resetForTesting();
      final before = controller.currentScene;
      final thumbnail = await tester.runAsync(
        () => renderPageThumbnail(
          scene: before,
          layout: controller.layout,
          page: controller.layout.pages[1],
          background: '#ffffff',
          longestSide: 80,
          shouldContinue: () => true,
        ),
      );
      expect(thumbnail, isNotNull);
      expect(thumbnail!.mathElements.single.id.value, 'formula');
      expect(thumbnail.image.height, 80);
      final data = await tester.runAsync(() => thumbnail.image.toByteData());
      final pixel = (5 * thumbnail.image.width + 5) * 4;
      expect(data!.getUint8(pixel), greaterThan(200));
      expect(data.getUint8(pixel + 1), lessThan(50));
      thumbnail.dispose();
      expect(
        await renderPageThumbnail(
          scene: before,
          layout: controller.layout,
          page: controller.layout.pages[1],
          background: '#ffffff',
          shouldContinue: () => false,
        ),
        isNull,
      );
      expect(controller.currentScene, same(before));
      expect(controller.imageCache.length, 0);
      expect(NaturalMediaPathCache.entryCount, 0);
      expect(NaturalMediaPathCache.missCount, 0);
    },
  );
}
