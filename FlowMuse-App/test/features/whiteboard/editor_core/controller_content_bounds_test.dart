import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bounds = Bounds.fromLTWH(0, 0, 400, 1600);

  test('controller clamps pan within explicit content bounds', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.contentBounds = bounds;

    controller.panViewport(-5000, -5000);

    expect(controller.editorState.viewport.offset.dx, greaterThan(-1000));
    expect(controller.editorState.viewport.offset.dy, greaterThan(-1000));
  });

  test('controller without content bounds keeps an infinite canvas', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);

    controller.panViewport(-5000, -5000);

    expect(controller.editorState.viewport.offset.dx, lessThan(-4000));
    expect(controller.editorState.viewport.offset.dy, lessThan(-4000));
  });

  test(
    'freedraw preview keeps scene-space points without per-frame rebasing',
    () {
      final controller = MarkdrawController();
      addTearDown(controller.dispose);
      controller.switchTool(ToolType.freedraw);
      const points = [Point(120, 80), Point(124, 83)];

      final preview =
          controller.buildPreviewElement(
                const ToolOverlay(
                  creationPoints: points,
                  creationPressures: [0.4, 0.5],
                ),
              )
              as FreedrawElement;

      expect(preview.x, 0);
      expect(preview.y, 0);
      expect(preview.points, points);
    },
  );

  test('setting content bounds immediately reclamps the viewport', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.panViewport(-5000, 0);

    controller.contentBounds = bounds;

    expect(controller.editorState.viewport.offset.dx, greaterThan(-1000));
  });

  test('canvas resize reclamps without returning to the first page', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.contentBounds = bounds;
    controller.setViewport(
      const ViewportState(offset: Offset(0, 700), zoom: 1),
    );

    controller.canvasSize = const Size(600, 400);

    expect(controller.editorState.viewport.offset.dy, greaterThan(600));
    expect(controller.editorState.viewport.offset.dy, lessThan(1000));
  });

  test('pinch uses the gesture-start focal point as its viewport anchor', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.setViewport(
      const ViewportState(offset: Offset(10, 20), zoom: 2),
    );

    controller.onScaleStart(
      ScaleStartDetails(localFocalPoint: const Offset(100, 120)),
    );
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        scale: 1.5,
        localFocalPoint: const Offset(140, 150),
        focalPointDelta: const Offset(40, 30),
        pointerCount: 2,
      ),
    );

    final viewport = controller.editorState.viewport;
    expect(viewport.zoom, 3);
    expect(viewport.offset.dx, closeTo(13.333333, 0.000001));
    expect(viewport.offset.dy, 30);
  });

  testWidgets('pinch gesture prevents an active hand tool from panning again', (
    tester,
  ) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.hand);
    controller.onPointerDown(
      const PointerDownEvent(
        position: Offset.zero,
        kind: PointerDeviceKind.touch,
      ),
    );

    controller.onScaleStart(ScaleStartDetails(localFocalPoint: Offset.zero));
    controller.onScaleUpdate(
      ScaleUpdateDetails(
        localFocalPoint: Offset.zero,
        focalPointDelta: Offset.zero,
        pointerCount: 2,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        position: Offset(40, 0),
        delta: Offset(40, 0),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(controller.editorState.viewport.offset, Offset.zero);
  });

  testWidgets('touch pans while a drawing tool stays selected', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);

    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 7,
        position: Offset.zero,
        kind: PointerDeviceKind.touch,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 7,
        position: Offset(40, 20),
        delta: Offset(40, 20),
        kind: PointerDeviceKind.touch,
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        pointer: 7,
        position: Offset(40, 20),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(controller.editorState.activeToolType, ToolType.freedraw);
    expect(controller.editorState.viewport.offset, const Offset(-40, -20));
    expect(controller.editorState.scene.elements, isEmpty);
  });

  testWidgets('touch does not pan while a stylus stroke is active', (
    tester,
  ) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.switchTool(ToolType.freedraw);
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        position: Offset.zero,
        kind: PointerDeviceKind.stylus,
        pressure: 0.5,
      ),
    );
    controller.onPointerDown(
      const PointerDownEvent(
        pointer: 7,
        position: Offset.zero,
        kind: PointerDeviceKind.touch,
      ),
    );
    controller.onPointerMove(
      const PointerMoveEvent(
        pointer: 7,
        position: Offset(40, 20),
        delta: Offset(40, 20),
        kind: PointerDeviceKind.touch,
      ),
    );

    expect(controller.editorState.viewport.offset, Offset.zero);
    expect(controller.editorState.scene.elements, isEmpty);
  });
}
