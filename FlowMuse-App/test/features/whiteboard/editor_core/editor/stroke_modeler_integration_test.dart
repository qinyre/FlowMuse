import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';

Offset _local(double x, double y) => Offset(x, y);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('freedraw stroke via controller commits real up endpoint', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);

    controller.onPointerDown(PointerDownEvent(
      pointer: 1,
      position: _local(0, 0),
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      timeStamp: Duration.zero,
    ));
    for (var i = 1; i <= 20; i++) {
      controller.onPointerMove(PointerMoveEvent(
        pointer: 1,
        position: _local(i.toDouble(), (i % 3).toDouble()),
        delta: const Offset(1, 0),
        kind: PointerDeviceKind.stylus,
        pressure: 0.5,
        timeStamp: Duration(milliseconds: i * 16),
      ));
    }
    controller.onPointerUp(PointerUpEvent(
      pointer: 1,
      position: _local(21, 0),
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      timeStamp: const Duration(milliseconds: 21 * 16),
    ));

    final elements = controller.editorState.scene.elements;
    expect(elements.length, 1);
    final points = (elements.first as dynamic).points as List;
    expect((points.last as dynamic).x, closeTo(21, 1.0));
  });

  test('cancel does not commit an element', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);
    controller.onPointerDown(PointerDownEvent(
      pointer: 1,
      position: _local(0, 0),
      kind: PointerDeviceKind.stylus,
      timeStamp: Duration.zero,
    ));
    controller.onPointerMove(PointerMoveEvent(
      pointer: 1,
      position: _local(10, 0),
      delta: const Offset(10, 0),
      kind: PointerDeviceKind.stylus,
      timeStamp: const Duration(milliseconds: 16),
    ));
    controller.onPointerCancel(PointerCancelEvent(
      pointer: 1,
      position: _local(10, 0),
      kind: PointerDeviceKind.stylus,
      timeStamp: const Duration(milliseconds: 32),
    ));
    expect(controller.editorState.scene.elements, isEmpty);
  });

  test('non-freedraw tool (select) bypasses modeler (no filtering)', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.select);
    controller.onPointerDown(PointerDownEvent(
      pointer: 1,
      position: _local(50, 50),
      kind: PointerDeviceKind.mouse,
      timeStamp: Duration.zero,
    ));
    expect(
      () => controller.onPointerUp(PointerUpEvent(
        pointer: 1,
        position: _local(50, 50),
        kind: PointerDeviceKind.mouse,
        timeStamp: const Duration(milliseconds: 16),
      )),
      returnsNormally,
    );
  });

  test('freedraw preserves subpixel scene coordinates', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.canvasSize = const Size(400, 600);
    controller.switchTool(ToolType.freedraw);
    controller.setViewport(const ViewportState(
      offset: Offset(0.25, 0.5),
      zoom: 1.5,
    ));
    controller.onPointerDown(PointerDownEvent(
      pointer: 1,
      position: _local(1, 1),
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      timeStamp: Duration.zero,
    ));
    controller.onPointerUp(PointerUpEvent(
      pointer: 1,
      position: _local(10, 10),
      kind: PointerDeviceKind.stylus,
      pressure: 0.5,
      timeStamp: const Duration(milliseconds: 16),
    ));
    final element = controller.editorState.scene.elements.single;
    // Element origin is min of all absolute points. With down at screen (1,1):
    // x = 1/1.5 + 0.25 = 0.9166..., y = 1/1.5 + 0.5 = 1.1666...
    // NOT rounded to (1, 1).
    expect((element as dynamic).x, closeTo(0.9166666667, 1e-6));
    expect((element as dynamic).y, closeTo(1.1666666667, 1e-6));
  });
}
