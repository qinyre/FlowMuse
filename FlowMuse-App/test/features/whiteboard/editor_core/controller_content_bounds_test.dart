import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
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
}
