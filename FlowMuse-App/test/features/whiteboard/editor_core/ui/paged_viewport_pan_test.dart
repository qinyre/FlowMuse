import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasLayout _layout(CanvasPageFlow flow, {String source = 'blank'}) =>
    CanvasLayout(
      type: CanvasLayoutType.paged,
      pageFlow: flow,
      pages: [
        CanvasPage(
          id: 'first',
          index: 0,
          bounds: const Rect.fromLTWH(0, 0, 800, 1000),
          template: CanvasPageTemplate.blank,
          pageFlow: flow,
          source: source,
        ),
        CanvasPage(
          id: 'second',
          index: 1,
          bounds: flow == CanvasPageFlow.topToBottom
              ? const Rect.fromLTWH(200, 1096, 500, 600)
              : const Rect.fromLTWH(-596, 200, 500, 600),
          template: CanvasPageTemplate.blank,
          pageFlow: flow,
          source: source,
        ),
      ],
    );

Future<MarkdrawController> _openCanvas(
  WidgetTester tester,
  CanvasPageFlow flow,
  String source,
) async {
  final controller = MarkdrawController(
    config: MarkdrawEditorConfig(initialLayout: _layout(flow, source: source)),
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: EditorCanvas(controller: controller),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final flow in CanvasPageFlow.values) {
    final vertical = flow == CanvasPageFlow.topToBottom;
    double crossOffset(ViewportState viewport) =>
        vertical ? viewport.offset.dx : viewport.offset.dy;

    test('$flow 放大保留侧向偏移、边缘限位，缩小后居中', () {
      // Given：页面大于视口，侧向偏移位于页面内部。
      final layout = _layout(flow);
      ViewportState clamp(Offset offset, {double zoom = 2}) =>
          clampPagedViewport(
            layout: layout,
            viewport: ViewportState(offset: offset, zoom: zoom),
            canvasSize: const Size(400, 400),
          );

      // When / Then：保留有效偏移，禁止越过页面两侧。
      expect(clamp(const Offset(100, 100)).offset, const Offset(100, 100));
      expect(
        crossOffset(
          clamp(
            vertical ? const Offset(-10000, 100) : const Offset(100, -10000),
          ),
        ),
        0,
      );
      expect(
        crossOffset(
          clamp(vertical ? const Offset(10000, 100) : const Offset(100, 10000)),
        ),
        vertical ? 600 : 800,
      );
      expect(
        crossOffset(clamp(const Offset(100, 100), zoom: 0.25)),
        vertical ? -400 : -300,
      );
      final nextPage = clamp(
        vertical ? const Offset(0, 1200) : const Offset(-500, 0),
      );
      expect(crossOffset(nextPage), 200);
    });

    for (final source in ['blank', 'pdf']) {
      testWidgets('$flow $source 抓手、单指和双指均可侧向移动，视口不写场景或历史', (tester) async {
        final controller = await _openCanvas(tester, flow, source);
        final scene = controller.currentScene;
        const initial = ViewportState(offset: Offset(100, 100), zoom: 2);
        final drag = vertical ? const Offset(-80, 0) : const Offset(0, -80);
        final start = tester.getCenter(find.byType(EditorCanvas));

        for (final kind in [
          PointerDeviceKind.mouse,
          PointerDeviceKind.stylus,
          PointerDeviceKind.touch,
        ]) {
          // Given：抓手或关闭手指绘制时的单指平移。
          controller.switchTool(
            kind == PointerDeviceKind.touch ? ToolType.freedraw : ToolType.hand,
          );
          controller.setViewport(initial);
          // When：实际指针从页面内向侧方拖动。
          final gesture = await tester.startGesture(start, kind: kind);
          await gesture.moveBy(drag);
          await gesture.up();
          await tester.pump();
          // Then：按缩放换算位移，两种排列都不被重新居中。
          expect(
            crossOffset(controller.editorState.viewport),
            140,
            reason: kind.name,
          );
        }

        controller.setViewport(initial);
        final separation = vertical
            ? const Offset(0, 120)
            : const Offset(120, 0);
        final first = await tester.startGesture(
          start - separation,
          pointer: 11,
        );
        final second = await tester.startGesture(
          start + separation,
          pointer: 12,
        );
        await tester.pump();
        // 先移动一次使双指手势赢得识别，再同步平移焦点。
        await first.moveBy(drag / 4);
        await second.moveBy(drag / 4);
        await tester.pump();
        final before = crossOffset(controller.editorState.viewport);
        await first.moveBy(drag / 2);
        await second.moveBy(drag / 2);
        await tester.pump();
        expect(
          crossOffset(controller.editorState.viewport),
          greaterThan(before),
        );
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        expect(controller.currentScene, same(scene));
        expect(controller.historyManager.canUndo, isFalse);
        expect(controller.editorState.viewport.zoom, initial.zoom);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$flow 横向与斜向滚轮保留二维位移，末页侧移不误增页', (tester) async {
      final controller = await _openCanvas(tester, flow, 'pdf');
      controller.setViewport(
        const ViewportState(offset: Offset(100, 100), zoom: 2),
      );
      Future<void> wheel(Offset delta) => tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(EditorCanvas)),
          scrollDelta: delta,
        ),
      );

      await wheel(const Offset(80, 0));
      expect(controller.editorState.viewport.offset, const Offset(140, 100));
      await wheel(const Offset(-40, 60));
      expect(controller.editorState.viewport.offset, const Offset(120, 130));
      final before = controller.editorState.viewport;
      await wheel(const Offset(0, 60));
      expect(
        controller.editorState.viewport.offset,
        vertical
            ? before.offset + const Offset(0, 30)
            : before.offset - const Offset(30, 0),
      );

      controller.scrollPagedViewportBy(100000);
      final pages = controller.layout.pages.length;
      final atEnd = controller.editorState.viewport;
      await wheel(vertical ? const Offset(80, 0) : const Offset(80, 80));
      await tester.pump(const Duration(seconds: 1));
      expect(
        crossOffset(controller.editorState.viewport),
        crossOffset(atEnd) + 40,
      );
      expect(controller.layout.pages.length, pages);
      controller.scrollPagedViewportBy(100000);
      final beforeElastic = crossOffset(controller.editorState.viewport);
      await wheel(vertical ? const Offset(40, 40) : const Offset(-40, 40));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(crossOffset(controller.editorState.viewport), beforeElastic + 20);
      expect(controller.layout.pages.length, pages);
      expect(controller.editorState.viewport.zoom, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$flow 触控板沿翻页轴越过末页仍可新增一页', (tester) async {
      final controller = await _openCanvas(tester, flow, 'blank');
      controller.setViewport(const ViewportState(zoom: 2));
      controller.scrollPagedViewportBy(100000);
      final before = controller.layout.pages.length;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(EditorCanvas)),
          scrollDelta: vertical ? const Offset(0, 600) : const Offset(-600, 0),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(controller.layout.pages.length, before + 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$flow 触底弹性只消费翻页方向，斜向抓手和单指仍可侧移', (tester) async {
      final controller = await _openCanvas(tester, flow, 'blank');
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        controller.switchTool(
          kind == PointerDeviceKind.mouse ? ToolType.hand : ToolType.freedraw,
        );
        controller.setViewport(
          const ViewportState(offset: Offset(250, 250), zoom: 2),
        );
        controller.scrollPagedViewportBy(100000);
        final before = crossOffset(controller.editorState.viewport);
        final pages = controller.layout.pages.length;
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(EditorCanvas)),
          kind: kind,
        );
        await gesture.moveBy(
          vertical ? const Offset(-80, -40) : const Offset(40, -80),
        );
        expect(
          crossOffset(controller.editorState.viewport),
          before + 40,
          reason: kind.name,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.layout.pages.length, pages);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
