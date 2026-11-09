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
  testWidgets('预览长按和选择删页：确认、至少一页、撤销和只读', (tester) async {
    final controller = _controller(3);
    addTearDown(controller.dispose);
    var navigations = 0;
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 280,
                height: 620,
                child: PageOverview(
                  controller: controller,
                  onClose: () {},
                  onNavigate: () => navigations++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('page-preview-p-1')));
    await tester.pump();
    expect(find.text('已选 1 页 · 点按勾选页面'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-preview-p-2')));
    await tester.pump();
    expect(find.text('已选 2 页 · 点按勾选页面'), findsOneWidget);
    expect(navigations, 0);
    if (const bool.fromEnvironment('FLOWMUSE_PAGE_NAV_SCREENSHOTS')) {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/page-preview-delete.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.byKey(const ValueKey('page-preview-p-0')));
    await tester.pump();
    expect(find.text('至少保留一页'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '删除所选 3 页'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('page-preview-p-0')));
    await tester.pump();
    await tester.tap(find.text('删除所选 2 页'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 页？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.layout.pages, hasLength(3));
    expect(controller.historyManager.canUndo, isFalse);
    await tester.tap(find.text('删除所选 2 页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(controller.layout.pages.map((page) => page.id), ['p-0']);
    expect(find.byKey(const ValueKey('page-preview-p-1')), findsNothing);
    expect(find.text('选择'), findsNothing);
    expect(find.text('第 1 / 1 页 · 输入页码跳转'), findsOneWidget);
    controller.undo();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-preview-p-1')), findsOneWidget);
    expect(controller.historyManager.canUndo, isFalse);
    controller.toggleViewMode();
    await tester.pump();
    expect(find.text('选择'), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('page-preview-p-1')));
    await tester.pump();
    expect(find.byType(Checkbox), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认期间页面被删除，不会按过期页码删除其他页', (tester) async {
    final controller = _controller(3);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 620,
            child: PageOverview(controller: controller, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('选择'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('page-preview-p-1')));
    await tester.pump();
    await tester.tap(find.text('删除所选 1 页'));
    await tester.pumpAndSettle();
    controller.deletePage('p-1');
    await tester.pump();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(controller.layout.pages.map((page) => page.id), ['p-0', 'p-2']);
    expect(find.text('已选 0 页 · 点按勾选页面'), findsOneWidget);
    expect(find.text('页面已变化或正在编辑，请重新选择后重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('页码固定在工具区，Agent 展开和窄屏时仍可翻页及提问', (tester) async {
    final controller = _controller(4);
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var asked = 0;
    Future<void> showEditor({bool agent = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MarkdrawEditor(
            controller: controller,
            onAskCurrentPage: () => asked++,
            assistantPanel: agent ? const Text('Agent') : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final pages = find.byType(PageNavigationControls);
    final rail = find.byKey(const ValueKey('editor-tool-rail'));
    Finder button(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );
    await showEditor();
    expect(tester.getRect(rail).contains(tester.getCenter(pages)), isTrue);
    expect(button('问这一页'), findsOneWidget);
    expect(
      tester
          .getRect(pages)
          .overlaps(tester.getRect(find.byType(DesktopToolbar))),
      isFalse,
    );

    await showEditor(agent: true);
    final dock = find.byKey(const ValueKey('editor-assistant-panel'));
    expect(tester.getRect(pages).overlaps(tester.getRect(dock)), isFalse);
    expect(button('多页预览'), findsOneWidget);
    await tester.tap(button('更多页面操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('问这一页'));
    await tester.pumpAndSettle();
    expect(asked, 1);

    await tester.binding.setSurfaceSize(const Size(390, 780));
    await showEditor();
    expect(tester.getRect(rail).contains(tester.getCenter(pages)), isTrue);
    expect(
      tester
          .getRect(pages)
          .overlaps(tester.getRect(find.byType(CompactToolbar))),
      isFalse,
    );
    await tester.tap(button('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
