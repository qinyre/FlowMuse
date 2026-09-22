import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/page_reading_position.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasLayout _layout({CanvasPageFlow flow = CanvasPageFlow.topToBottom}) =>
    CanvasLayout(
      type: CanvasLayoutType.paged,
      pageFlow: flow,
      pages: [
        CanvasPage(
          id: 'cover',
          index: 2,
          template: CanvasPageTemplate.blank,
          bounds: const Rect.fromLTWH(0, 0, 1600, 2000),
          pageFlow: flow,
        ),
        CanvasPage(
          id: 'chapter',
          index: 8,
          template: CanvasPageTemplate.blank,
          bounds: flow == CanvasPageFlow.topToBottom
              ? const Rect.fromLTWH(0, 2096, 1200, 1000)
              : const Rect.fromLTWH(-1296, 0, 1200, 1000),
          pageFlow: flow,
        ),
        CanvasPage(
          id: 'end',
          index: 20,
          template: CanvasPageTemplate.blank,
          bounds: flow == CanvasPageFlow.topToBottom
              ? const Rect.fromLTWH(0, 3192, 1600, 2000)
              : const Rect.fromLTWH(-2992, 0, 1600, 2000),
          pageFlow: flow,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deleted and invalid page markers do not become navigable pages', () {
    final page = _layout().pages.first;
    RectangleElement marker(
      String id, {
      bool deleted = false,
      double width = 1600,
    }) => RectangleElement(
      id: ElementId(id),
      x: 0,
      y: 0,
      width: width,
      height: 2000,
      isDeleted: deleted,
      customData: CanvasLayout.pageCustomData(page),
    );
    final layout = CanvasLayout.fromScene([
      marker('deleted', deleted: true),
      marker('invalid', width: double.nan),
      marker('good'),
      marker('duplicate'),
    ]);
    expect(layout.pages.map((p) => p.id), ['cover']);
  });

  test('current page uses visible area and dense reading order', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setLayout(_layout());
    controller.canvasSize = const Size(800, 1600);
    controller.setViewport(const ViewportState(offset: Offset(0, 1000)));
    expect(controller.pagedViewportMetrics!.currentPageIndex, 0);
    expect(
      controller
          .pageForVisibleRect(
            controller.editorState.viewport.visibleRect(controller.canvasSize),
          )!
          .id,
      'cover',
    );
    expect(
      identical(
        controller.pagedViewportMetrics,
        controller.pagedViewportMetrics,
      ),
      isTrue,
    );
  });

  test(
    'legacy PDF metadata provides page bounds without rewriting its scene',
    () {
      final scene = Scene().upsertRemoteElements([
        ImageElement(
          id: const ElementId('old-second'),
          fileId: 'image',
          x: 0,
          y: 900,
          width: 500,
          height: 600,
          customData: CanvasLayout.pdfBackgroundCustomData('old-b'),
        ),
        ImageElement(
          id: const ElementId('old-first'),
          fileId: 'image',
          x: 0,
          y: 0,
          width: 500,
          height: 800,
          customData: CanvasLayout.pdfBackgroundCustomData('old-a'),
        ),
      ]);
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.loadScene(scene);
      expect(controller.layout.pages.map((page) => page.id), [
        'old-a',
        'old-b',
      ]);
      expect(controller.currentScene.elements, scene.elements);
      expect(
        controller.currentScene.elements.any((element) => element.isCanvasPage),
        isFalse,
      );
      expect(controller.layout.pages.last.bounds.top, 900);
    },
  );

  test('fit and deleted-page fallback preserve valid bounded view state', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setLayout(_layout());
    controller.canvasSize = const Size(800, 800);
    controller.navigateToPage('chapter', fit: true);
    final visible = controller.editorState.viewport.visibleRect(
      controller.canvasSize,
    );
    expect(visible.contains(controller.layout.pages[1].bounds.topLeft), isTrue);
    expect(
      visible.contains(controller.layout.pages[1].bounds.bottomRight),
      isTrue,
    );
    final saved = controller.captureReadingPosition()!;
    final withoutPage = controller.layout.copyWith(
      pages: [controller.layout.pages.first],
    );
    expect(saved.restore(withoutPage, const Size(500, 500))!.zoom, saved.zoom);
    controller.pagedTouchActive = true;
    expect(controller.navigateToPage('end'), isFalse);
    controller.pagedTouchActive = false;
  });

  for (final flow in CanvasPageFlow.values) {
    test('mixed-size $flow pages remain separated on insert and reorder', () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.setLayout(_layout(flow: flow));
      controller.insertBlankPage(afterIndex: 0);
      controller.reorderPage('cover', 2);
      final pages = controller.layout.pages;
      for (var i = 1; i < pages.length; i++) {
        final gap = flow == CanvasPageFlow.topToBottom
            ? pages[i].bounds.top - pages[i - 1].bounds.bottom
            : pages[i - 1].bounds.left - pages[i].bounds.right;
        expect(gap, CanvasLayout.pageGap);
      }
    });
  }

  test(
    'navigation preserves scene, history, selection and zoom; return restores view',
    () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.setLayout(_layout());
      controller.canvasSize = const Size(800, 800);
      controller.setViewport(
        const ViewportState(offset: Offset(0, 200), zoom: 0.8),
      );
      final before = controller.editorState;
      var sceneEvents = 0;
      controller.sceneChangeListeners.add((_, _) => sceneEvents++);
      expect(controller.navigateToPage('end'), isTrue);
      expect(controller.editorState.viewport.zoom, 0.8);
      expect(controller.currentScene, same(before.scene));
      expect(controller.editorState.selectedIds, before.selectedIds);
      expect(controller.historyManager.canUndo, isFalse);
      expect(sceneEvents, 0);
      expect(controller.returnToPagePosition(), isTrue);
      expect(controller.editorState.viewport, before.viewport);
      expect(controller.canReturnToPagePosition, isFalse);
    },
  );

  test('navigation refuses an active stroke without discarding it', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setLayout(_layout());
    controller.canvasSize = const Size(800, 800);
    controller.switchTool(ToolType.freedraw);
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 100),
        pressure: 0.5,
      ),
    );
    final viewport = controller.editorState.viewport;
    expect(controller.navigateToPage('chapter'), isFalse);
    expect(controller.editorState.viewport, viewport);
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 100),
        pressure: 0.5,
      ),
    );
    expect(
      controller.currentScene.activeElements.whereType<FreedrawElement>(),
      hasLength(1),
    );
    expect(controller.navigateToPage('chapter'), isTrue);
  });

  test(
    'reading position survives reordered page IDs and rejects corrupt settings',
    () {
      final layout = _layout();
      final position = PageReadingPosition.capture(
        layout,
        const ViewportState(offset: Offset(0, 2200), zoom: 0.8),
        const Size(800, 600),
      )!;
      final decoded = PageReadingPosition.fromJson(position.toJson())!;
      expect(
        decoded.restore(layout, const Size(800, 600)),
        const ViewportState(offset: Offset(0, 2200), zoom: 0.8),
      );
      expect(
        decoded.restore(
          layout.copyWith(pages: layout.pages.reversed.toList()),
          const Size(800, 600),
        ),
        decoded.restore(layout, const Size(800, 600)),
      );
      expect(
        PageReadingPosition.fromJson({
          ...position.toJson(),
          'zoom': double.nan,
        }),
        isNull,
      );
      expect(
        PageReadingPosition.fromJson({...position.toJson(), 'ordinal': -1}),
        isNull,
      );
      expect(PageReadingPosition.fromJson('broken'), isNull);
    },
  );
}
