import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter_test/flutter_test.dart';

List<FreedrawElement> _strokes() => [
  for (final x in [100.0, 480.0])
    FreedrawElement(
      id: ElementId('stroke-$x'),
      x: x,
      y: 100,
      width: 40,
      height: 140,
      points: const [Point(0, 0), Point(40, 140)],
    ),
];

void _drag(
  MarkdrawController controller,
  Offset start,
  Offset end, {
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) {
  controller.onPointerDown(
    PointerDownEvent(pointer: 1, kind: kind, position: start),
  );
  final middle = Offset.lerp(start, end, 0.5)!;
  controller.onPointerMove(
    PointerMoveEvent(
      pointer: 1,
      kind: kind,
      position: middle,
      delta: middle - start,
    ),
  );
  controller.onPointerMove(
    PointerMoveEvent(
      pointer: 1,
      kind: kind,
      position: end,
      delta: end - middle,
    ),
  );
  controller.onPointerUp(PointerUpEvent(pointer: 1, kind: kind, position: end));
}

ToolContext _context(List<Element> elements, {Set<ElementId>? selectedIds}) =>
    ToolContext(
      scene: Scene().upsertRemoteElements(elements),
      viewport: const ViewportState(),
      selectedIds: selectedIds ?? elements.map((e) => e.id).toSet(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
  ]) {
    test('${kind.name}：框选后从笔迹间空白拖动整组，可一次撤销和重做', () {
      // Given: two separate strokes selected with a marquee.
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final strokes = _strokes();
      controller.loadScene(Scene().upsertRemoteElements(strokes));
      _drag(controller, const Offset(80, 80), const Offset(540, 260));
      final ids = strokes.map((e) => e.id).toSet();
      expect(controller.editorState.selectedIds, ids);

      // When: start between the strokes, with multiple pointer updates.
      _drag(
        controller,
        const Offset(300, 180),
        const Offset(340, 210),
        kind: kind,
      );

      // Then: both move by the total delta, without panning or reselection.
      for (final stroke in strokes) {
        final moved = controller.currentScene.getElementById(stroke.id)!;
        expect(moved.x, stroke.x + 40);
        expect(moved.y, stroke.y + 30);
      }
      expect(controller.editorState.selectedIds, ids);
      expect(controller.editorState.viewport.offset, Offset.zero);
      controller.undo();
      for (final stroke in strokes) {
        final restored = controller.currentScene.getElementById(stroke.id)!;
        expect(restored.x, stroke.x);
        expect(restored.y, stroke.y);
      }
      controller.redo();
      for (final stroke in strokes) {
        final moved = controller.currentScene.getElementById(stroke.id)!;
        expect(moved.x, stroke.x + 40);
        expect(moved.y, stroke.y + 30);
      }
    });
  }

  testWidgets('缩放后手指从多选空白拖动仍走选择路径，框外手指仍平移', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final strokes = _strokes();
    controller.loadScene(Scene().upsertRemoteElements(strokes));
    controller.applyResult(
      SetSelectionResult(strokes.map((e) => e.id).toSet()),
    );
    await tester.pumpWidget(
      MaterialApp(home: EditorCanvas(controller: controller)),
    );
    controller.setViewport(const ViewportState(zoom: 0.5));
    await tester.pump();
    final viewport = controller.editorState.viewport;
    final start = viewport.sceneToScreen(const Offset(300, 180));

    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.touch,
    );
    await drag.moveBy(const Offset(40, 30));
    await drag.up();
    await tester.pump();
    for (final stroke in strokes) {
      final moved = controller.currentScene.getElementById(stroke.id)!;
      expect(moved.x, stroke.x + 80);
      expect(moved.y, stroke.y + 60);
    }
    expect(controller.editorState.viewport.offset, viewport.offset);

    final outside = viewport.sceneToScreen(const Offset(700, 400));
    final pan = await tester.startGesture(
      outside,
      kind: PointerDeviceKind.touch,
    );
    await pan.moveBy(const Offset(0, -60));
    await pan.up();
    await tester.pump();
    expect(controller.editorState.viewport.offset, isNot(viewport.offset));
    for (final stroke in strokes) {
      expect(
        controller.currentScene.getElementById(stroke.id)!.x,
        stroke.x + 80,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('空白轻点或未越过拖动阈值仍取消选择，不移动元素', () {
    final context = _context(_strokes());
    final tool = SelectTool();
    tool.onPointerDown(const Point(300, 180), context);
    expect(tool.onPointerMove(const Point(301, 181), context), isNull);
    final result = tool.onPointerUp(const Point(301, 181), context);
    expect(result, isA<SetSelectionResult>());
    expect((result! as SetSelectionResult).selectedIds, isEmpty);
  });

  test('框外起拖仍创建新框选，即使随后经过原选框内部', () {
    final strokes = _strokes();
    final context = _context(strokes);
    final tool = SelectTool();
    tool.onPointerDown(const Point(60, 60), context);
    tool.onPointerMove(const Point(300, 250), context);
    expect(tool.overlay!.marqueeRect, isNotNull);
    final result = tool.onPointerUp(const Point(300, 250), context);
    expect((result! as SetSelectionResult).selectedIds, {strokes.first.id});
  });

  test('框内未选中元素的实际命中优先于整组空白拖动', () {
    final strokes = _strokes();
    final image = ImageElement(
      id: ElementId('other-image'),
      x: 250,
      y: 150,
      width: 80,
      height: 60,
      fileId: 'missing-test-image',
    );
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(Scene().upsertRemoteElements([...strokes, image]));
    controller.applyResult(
      SetSelectionResult(strokes.map((e) => e.id).toSet()),
    );
    expect(
      controller.shouldRouteTouchToSelection(const Offset(300, 180)),
      isFalse,
    );
    _drag(controller, const Offset(300, 180), const Offset(340, 210));
    expect(controller.editorState.selectedIds, {image.id});
    expect(controller.currentScene.getElementById(image.id)!.x, 290);
    for (final stroke in strokes) {
      expect(controller.currentScene.getElementById(stroke.id)!.x, stroke.x);
    }
  });

  for (final handleType in [HandleType.bottomCenter, HandleType.rotation]) {
    test('多选${handleType.name}手柄优先于空白移动', () {
      final strokes = _strokes();
      final context = _context(strokes);
      final handle = SelectionOverlay.fromElements(
        strokes,
      )!.handles.firstWhere((h) => h.type == handleType);
      final tool = SelectTool();
      tool.onPointerDown(handle.position, context);
      final result = tool.onPointerMove(
        Point(handle.position.x + 40, handle.position.y + 40),
        context,
      );
      final updated = EditorState(
        scene: context.scene,
        viewport: context.viewport,
        selectedIds: context.selectedIds,
        activeToolType: ToolType.select,
      ).applyResult(result!);
      final element = updated.scene.getElementById(strokes.first.id)!;
      if (handleType == HandleType.rotation) {
        expect(element.angle, isNot(0));
      } else {
        expect(element.height, greaterThan(strokes.first.height));
        expect(element.x, strokes.first.x);
      }
    });
  }

  test('含锁定元素的多选不会从空白处移动，单选仍只命中元素本体', () {
    final strokes = _strokes();
    final tool = SelectTool();
    for (final elements in [
      strokes.map((e) => e.copyWith(locked: true)).toList(),
      [strokes.first, strokes.last.copyWith(locked: true)],
      [strokes.first],
    ]) {
      final context = _context(elements);
      const point = Point(300, 180);
      expect(tool.hitTestForTouch(point, context), isFalse);
      tool.onPointerDown(point, context);
      expect(tool.onPointerMove(const Point(340, 210), context), isNull);
      expect(tool.overlay!.marqueeRect, isNotNull);
      tool.reset();
    }
  });
}
