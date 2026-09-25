import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element;
import 'package:flutter_test/flutter_test.dart';

ImageElement _image() => ImageElement(
  id: ElementId('touch-image'),
  x: 100,
  y: 100,
  width: 200,
  height: 150,
  fileId: 'missing-test-image',
);

void _down(
  MarkdrawController controller,
  Offset position, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => controller.onPointerDown(
  PointerDownEvent(pointer: 1, kind: kind, position: position),
);

void _move(
  MarkdrawController controller,
  Offset from,
  Offset to, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => controller.onPointerMove(
  PointerMoveEvent(pointer: 1, kind: kind, position: to, delta: to - from),
);

void _up(
  MarkdrawController controller,
  Offset position, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => controller.onPointerUp(
  PointerUpEvent(pointer: 1, kind: kind, position: position),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final layout in CanvasLayoutType.values) {
    testWidgets('$layout：图片上直接滑动翻页，轻点选中后才能拖动并撤销', (tester) async {
      // Given: an unselected image in either canvas layout.
      final controller = MarkdrawController(
        config: MarkdrawEditorConfig(initialLayout: CanvasLayout(type: layout)),
      );
      addTearDown(controller.dispose);
      final image = layout == CanvasLayoutType.paged
          ? _image().copyWith(x: 600)
          : _image();
      controller.loadScene(Scene().addElement(image));
      await tester.pumpWidget(
        MaterialApp(home: EditorCanvas(controller: controller)),
      );
      await tester.pump();
      final originalViewport = controller.editorState.viewport;
      final start = originalViewport.sceneToScreen(Offset(image.x + 100, 175));

      // When: the first contact slides instead of tapping.
      var gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.touch,
      );
      await gesture.moveBy(const Offset(0, -60));
      await gesture.up();
      await tester.pump();

      // Then: only the page moves.
      expect(controller.currentScene.getElementById(image.id), same(image));
      expect(controller.editorState.selectedIds, isEmpty);
      expect(
        controller.editorState.viewport.offset,
        isNot(originalViewport.offset),
      );

      controller.setViewport(originalViewport);
      await tester.pump();
      gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(4, 4));
      expect(controller.editorState.selectedIds, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(controller.editorState.selectedIds, {image.id});
      expect(controller.currentScene.getElementById(image.id), same(image));
      expect(controller.editorState.viewport.offset, originalViewport.offset);

      gesture = await tester.startGesture(start, kind: PointerDeviceKind.touch);
      await gesture.moveBy(const Offset(40, -40));
      await gesture.up();
      await tester.pump();
      expect(
        controller.currentScene.getElementById(image.id)!.x,
        greaterThan(image.x),
      );
      expect(controller.editorState.viewport.offset, originalViewport.offset);
      controller.undo();
      expect(controller.currentScene.getElementById(image.id)!.x, image.x);
      expect(controller.currentScene.getElementById(image.id)!.y, image.y);

      controller.applyResult(SetSelectionResult({image.id}));
      final first = await tester.startGesture(
        start - const Offset(40, 0),
        pointer: 51,
        kind: PointerDeviceKind.touch,
      );
      final second = await tester.startGesture(
        start + const Offset(40, 0),
        pointer: 52,
        kind: PointerDeviceKind.touch,
      );
      await second.moveBy(const Offset(40, 0));
      await tester.pump();
      await first.moveBy(const Offset(-40, 0));
      await second.up();
      await first.up();
      await tester.pump();
      expect(controller.currentScene.getElementById(image.id)!.x, image.x);
      expect(controller.currentScene.getElementById(image.id)!.y, image.y);
      expect(controller.editorState.selectedIds, {image.id});
      expect(
        controller.editorState.viewport.zoom,
        greaterThan(originalViewport.zoom),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('非选择工具下手指只移动页面，轻点也不更改选择', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final image = _image();
    controller.loadScene(Scene().addElement(image));
    for (final tool in ToolType.values.where(
      (tool) => tool != ToolType.select,
    )) {
      controller.switchTool(tool);
      controller.applyResult(SetSelectionResult({image.id}));
      controller.setViewport(const ViewportState());
      const start = Offset(200, 175);
      const end = Offset(240, 135);
      _down(controller, start);
      _move(controller, start, end);
      _up(controller, end);
      expect(
        controller.currentScene.getElementById(image.id),
        same(image),
        reason: tool.name,
      );
      expect(
        controller.editorState.viewport.offset,
        const Offset(-40, 40),
        reason: tool.name,
      );
      _down(controller, const Offset(500, 400));
      _up(controller, const Offset(500, 400));
      expect(controller.editorState.selectedIds, {image.id}, reason: tool.name);
    }
  });

  test('笔选中的笔画可以直接手指拖动，空白滑动保留选区，空白轻点清除', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final stroke = FreedrawElement(
      id: ElementId('touch-stroke'),
      x: 100,
      y: 100,
      width: 200,
      height: 100,
      points: const [Point(0, 0), Point(100, 50), Point(200, 100)],
    );
    controller.loadScene(Scene().addElement(stroke));
    const start = Offset(200, 150);
    _down(controller, start, kind: PointerDeviceKind.stylus);
    _up(controller, start, kind: PointerDeviceKind.stylus);
    expect(controller.editorState.selectedIds, {stroke.id});
    _down(controller, start);
    _move(controller, start, start + const Offset(50, 50));
    _up(controller, start + const Offset(50, 50));
    expect(controller.currentScene.getElementById(stroke.id)!.x, 150);
    _down(controller, const Offset(500, 400));
    _move(controller, const Offset(500, 400), const Offset(500, 450));
    _up(controller, const Offset(500, 450));
    expect(controller.editorState.selectedIds, {stroke.id});
    _down(controller, const Offset(500, 400));
    _up(controller, const Offset(500, 400));
    expect(controller.editorState.selectedIds, isEmpty);
  });

  test('手指轻点容差按屏幕距离计算，选中前后均容忍轻微抖动', () {
    for (final zoom in [0.5, 3.0]) {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final image = _image();
      controller.loadScene(Scene().addElement(image));
      controller.setViewport(ViewportState(zoom: zoom));
      final viewport = controller.editorState.viewport;
      final start = viewport.sceneToScreen(const Offset(200, 175));
      for (var tap = 0; tap < 2; tap++) {
        _down(controller, start);
        _move(controller, start, start + const Offset(4, 4));
        _up(controller, start + const Offset(4, 4));
        expect(controller.editorState.selectedIds, {image.id});
        expect(controller.currentScene.getElementById(image.id), same(image));
        expect(controller.editorState.viewport.offset, viewport.offset);
      }
    }
  });

  test('取消和双指缩放不提交点选，防误触期间也不选择对象', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.loadScene(Scene().addElement(_image()));
    const start = Offset(200, 175);
    _down(controller, start);
    controller.onPointerCancel(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.touch),
    );
    expect(controller.editorState.selectedIds, isEmpty);
    _down(controller, start);
    controller.onScaleStart(ScaleStartDetails(localFocalPoint: start));
    controller.onScaleUpdate(
      ScaleUpdateDetails(localFocalPoint: start, scale: 1.5, pointerCount: 2),
    );
    _up(controller, start);
    controller.onScaleEnd(ScaleEndDetails());
    expect(controller.editorState.selectedIds, isEmpty);
    expect(controller.editorState.viewport.zoom, 1.5);
    controller.setViewport(const ViewportState());
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.stylus,
        position: Offset(500, 400),
      ),
    );
    _down(controller, start);
    _up(controller, start);
    expect(controller.editorState.selectedIds, isEmpty);
  });

  test('鼠标和触控笔仍能直接拖动未选中对象', () {
    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.stylus]) {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      final image = _image();
      controller.loadScene(Scene().addElement(image));
      const start = Offset(200, 175);
      const end = Offset(240, 135);
      _down(controller, start, kind: kind);
      _move(controller, start, end, kind: kind);
      _up(controller, end, kind: kind);
      expect(controller.currentScene.getElementById(image.id)!.x, 140);
      expect(controller.currentScene.getElementById(image.id)!.y, 60);
    }
  });

  test('单指平移关闭仍可先点选后拖动，手指绘制开启仍可直接拖动', () {
    for (final fingerDrawing in [false, true]) {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.applyEditorPreferences(
        defaultTool: ToolType.select,
        defaultBrush: BrushType.pencil,
        brushStates: const {},
        pressureEnabled: true,
        pressureExponent: 1,
        palmRejectionEnabled: true,
        twoFingerZoomEnabled: true,
        singleFingerPanEnabled: false,
        fingerDrawingEnabled: fingerDrawing,
      );
      final image = _image();
      controller.loadScene(Scene().addElement(image));
      const start = Offset(200, 175);
      const end = Offset(240, 135);
      if (!fingerDrawing) {
        _down(controller, start);
        _move(controller, start, end);
        _up(controller, end);
        expect(controller.currentScene.getElementById(image.id), same(image));
        expect(controller.editorState.selectedIds, isEmpty);
        expect(controller.editorState.viewport.offset, Offset.zero);
        _down(controller, start);
        _up(controller, start);
        expect(controller.editorState.selectedIds, {image.id});
      }
      _down(controller, start);
      _move(controller, start, end);
      _up(controller, end);
      expect(controller.currentScene.getElementById(image.id)!.x, 140);
    }
  });

  test('先点选后仍可拖动选择框句柄调整图片大小', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final image = _image();
    controller.loadScene(Scene().addElement(image));
    _down(controller, const Offset(200, 175));
    _up(controller, const Offset(200, 175));
    final handle = controller.buildSelectionOverlay()!.handles.firstWhere(
      (handle) => handle.type == HandleType.bottomRight,
    );
    final start = Offset(handle.position.x, handle.position.y);
    final end = start + const Offset(40, 40);
    _down(controller, start);
    _move(controller, start, end);
    _up(controller, end);
    expect(
      controller.currentScene.getElementById(image.id)!.width,
      greaterThan(image.width),
    );
    expect(controller.editorState.viewport.offset, Offset.zero);
  });
}
