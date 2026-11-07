import 'dart:ui';
import 'dart:convert';

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

  for (final flow in CanvasPageFlow.values) {
    test('删除 $flow 首中末页保留其他页内容、旧归属和阅读位置', () {
      for (var deletedIndex = 0; deletedIndex < 3; deletedIndex++) {
        final controller = MarkdrawController()..setLayout(_layout(flow: flow));
        addTearDown(controller.dispose);
        controller.canvasSize = const Size(800, 700);
        final pages = controller.layout.pages;
        final original = <String, Element>{};
        for (final page in pages) {
          final text = TextElement(
            id: ElementId('text-${page.id}'),
            x: page.bounds.left + 80,
            y: page.bounds.top + 80,
            width: 180,
            height: 50,
            text: '页面内容',
            // 模拟没有页归属字段的旧笔记。
          );
          original[page.id] = text;
          controller.applyResult(
            AddElementResult(text),
            applyDefaultStyle: false,
          );
        }
        final deleted = pages[deletedIndex];
        controller.navigateToPage(deleted.id, fit: true);
        expect(controller.deletePages({deleted.id}), isTrue);
        final remaining = controller.layout.pages;
        expect(
          remaining.map((page) => page.id),
          pages.where((page) => page.id != deleted.id).map((page) => page.id),
        );
        expect(
          controller.currentScene
              .getElementById(original[deleted.id]!.id)!
              .isDeleted,
          isTrue,
        );
        for (final page in remaining) {
          final before = original[page.id]!;
          final oldPage = pages.firstWhere(
            (candidate) => candidate.id == page.id,
          );
          final element = controller.currentScene.getElementById(before.id)!;
          expect(element.isDeleted, isFalse);
          expect(element.x, before.x + page.bounds.left - oldPage.bounds.left);
          expect(element.y, before.y + page.bounds.top - oldPage.bounds.top);
        }
        expect(
          remaining[controller.pagedViewportMetrics!.currentPageIndex].id,
          remaining[deletedIndex.clamp(0, remaining.length - 1)].id,
        );
        controller.undo();
        expect(
          controller.layout.pages.map((page) => page.id),
          pages.map((page) => page.id),
        );
        expect(
          controller.currentScene
              .getElementById(original[deleted.id]!.id)!
              .isDeleted,
          isFalse,
        );
        expect(controller.historyManager.canUndo, isFalse);
        controller.redo();
        expect(controller.layout.pages, hasLength(2));
      }
    });
  }

  test('批量删页一次提交历史和场景，PDF 墓碑可同步且附件保留供撤销', () {
    final controller = MarkdrawController()..setLayout(_layout());
    final guest = MarkdrawController();
    addTearDown(controller.dispose);
    addTearDown(guest.dispose);
    final file = ImageFile(
      mimeType: 'image/png',
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      ),
    );
    controller.applyResult(
      CompoundResult([
        AddFileResult(fileId: 'pdf-file', file: file),
        for (final page in controller.layout.pages)
          AddElementResult(
            ImageElement(
              id: ElementId('pdf-${page.id}'),
              x: page.bounds.left,
              y: page.bounds.top,
              width: page.bounds.width,
              height: page.bounds.height,
              fileId: 'pdf-file',
              locked: true,
              customData: CanvasLayout.pdfBackgroundCustomData(page.id),
            ),
          ),
        SetSelectionResult({
          const ElementId('pdf-cover'),
          const ElementId('pdf-chapter'),
        }),
      ]),
      applyDefaultStyle: false,
    );
    guest.applyRemoteExcalidrawSceneJson(
      controller.serializeExcalidrawSceneJson(includeDeleted: true),
    );
    controller.canvasSize = const Size(800, 700);
    controller.navigateToPage('chapter', fit: true);
    final zoom = controller.editorState.viewport.zoom;
    var sceneChanges = 0;
    controller.sceneChangeListeners.add((_, _) => sceneChanges++);
    expect(controller.deletePages({'cover', 'end'}), isTrue);
    expect(sceneChanges, 1);
    expect(controller.pagedViewportMetrics!.currentPageIndex, 0);
    expect(controller.editorState.viewport.zoom, zoom);
    expect(controller.editorState.selectedIds, {
      const ElementId('pdf-chapter'),
    });
    expect(controller.currentScene.files['pdf-file'], same(file));
    expect(
      controller.currentScene
          .getElementById(const ElementId('pdf-cover'))!
          .isDeleted,
      isTrue,
    );
    expect(
      controller.currentScene
          .getElementById(const ElementId('pdf-end'))!
          .isDeleted,
      isTrue,
    );
    guest.applyRemoteExcalidrawSceneJson(
      controller.serializeExcalidrawSceneJson(includeDeleted: true),
    );
    expect(guest.layout.pages.map((page) => page.id), ['chapter']);
    expect(
      guest.currentScene
          .getElementById(const ElementId('pdf-cover'))!
          .isDeleted,
      isTrue,
    );
    controller.undo();
    expect(controller.layout.pages, hasLength(3));
    expect(
      controller.currentScene
          .getElementById(const ElementId('pdf-cover'))!
          .isDeleted,
      isFalse,
    );
    expect(controller.currentScene.files['pdf-file'], same(file));
    expect(controller.historyManager.canUndo, isFalse);
    controller.redo();
    expect(controller.layout.pages.map((page) => page.id), ['chapter']);
  });

  test('删页拒绝只读、忙碌、过期选择及删空笔记，不改变历史或场景', () {
    final controller = MarkdrawController()..setLayout(_layout());
    addTearDown(controller.dispose);
    final before = controller.currentScene;
    expect(controller.deletePages({}), isFalse);
    expect(controller.deletePages({'missing', 'cover'}), isFalse);
    expect(controller.deletePages({'cover', 'chapter', 'end'}), isFalse);
    controller.pagedTouchActive = true;
    expect(controller.deletePages({'cover'}), isFalse);
    controller.pagedTouchActive = false;
    controller.toggleViewMode();
    expect(controller.deletePages({'cover'}), isFalse);
    controller.toggleViewMode();
    expect(controller.currentScene, same(before));
    expect(controller.historyManager.canUndo, isFalse);
    controller.deletePage('cover');
    expect(controller.layout.pages, hasLength(2));
    expect(controller.deletePages({'chapter'}), isTrue);
    final last = controller.currentScene;
    expect(controller.deletePages({'end'}), isFalse);
    expect(controller.currentScene, same(last));
  });

  test('批量删除当前页及前页后定位紧邻的存留页', () {
    final layout = _layout();
    final controller = MarkdrawController()
      ..setLayout(
        layout.copyWith(
          pages: [
            ...layout.pages,
            CanvasPage(
              id: 'fourth',
              index: 21,
              bounds: const Rect.fromLTWH(0, 5288, 1600, 2000),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      );
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(800, 700);
    controller.navigateToPage('chapter', fit: true);
    expect(controller.deletePages({'cover', 'chapter'}), isTrue);
    expect(
      controller
          .layout
          .pages[controller.pagedViewportMetrics!.currentPageIndex]
          .id,
      'end',
    );
  });

  for (final template in CanvasPageTemplate.values) {
    test('页面标记恢复 ${template.name} 模板和续页方向', () {
      final host = MarkdrawController()
        ..setLayout(
          CanvasLayout(
            type: CanvasLayoutType.paged,
            template: template,
            pageFlow: CanvasPageFlow.rightToLeft,
          ),
        );
      final guest = MarkdrawController();
      addTearDown(host.dispose);
      addTearDown(guest.dispose);

      guest.applyRemoteExcalidrawSceneJson(host.serializeExcalidrawSceneJson());

      expect(guest.layout.type, CanvasLayoutType.paged);
      expect(guest.layout.template, template);
      expect(guest.layout.pageFlow, CanvasPageFlow.rightToLeft);
      guest.insertBlankPage();
      expect(guest.layout.pages.last.template, template);
      expect(
        guest.layout.pages.last.bounds.size,
        CanvasLayout.pageSizeForTemplate(template),
      );
      expect(guest.layout.pages.last.bounds.right, -CanvasLayout.pageGap);

      final incremental = MarkdrawController();
      addTearDown(incremental.dispose);
      incremental.applyRemoteElements(host.currentScene.elements);
      expect(incremental.layout.template, template);
      expect(incremental.layout.pageFlow, CanvasPageFlow.rightToLeft);
    });
  }

  test('页面标记乱序或缺失旧字段时仍按阅读顺序恢复默认版式', () {
    RectangleElement marker(CanvasPage page) => RectangleElement(
      id: ElementId(page.id),
      x: page.bounds.left,
      y: page.bounds.top,
      width: page.bounds.width,
      height: page.bounds.height,
      customData: CanvasLayout.pageCustomData(page),
    );
    final first = _layout(flow: CanvasPageFlow.rightToLeft).pages.first;
    final last = _layout().pages.last;
    final layout = CanvasLayout.fromScene([
      marker(last),
      marker(first).copyWith(
        customData: {
          'flowMuse': {
            ...CanvasLayout.flowMuseData(CanvasLayout.pageCustomData(first))!,
            'template': CanvasPageTemplate.grid.name,
          },
        },
      ),
    ]);
    expect(layout.template, CanvasPageTemplate.grid);
    expect(layout.pageFlow, CanvasPageFlow.rightToLeft);

    final legacy = CanvasLayout.fromScene(
      [
        marker(first).copyWith(
          customData: {
            'flowMuse': {'role': 'page', 'pageId': first.id},
          },
        ),
      ],
      fallbackTemplate: CanvasPageTemplate.dotGrid,
      fallbackPageFlow: CanvasPageFlow.rightToLeft,
    );
    expect(legacy.template, CanvasPageTemplate.dotGrid);
    expect(legacy.pageFlow, CanvasPageFlow.rightToLeft);
  });

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
