import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_clamp.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/viewport_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bounds = Bounds.fromLTWH(0, 0, 400, 800);
  const canvas = Size(400, 600);

  test('keeps an unbounded viewport unchanged', () {
    const viewport = ViewportState(offset: Offset(-1000, -2000));
    expect(clampViewportToBounds(viewport, null, canvas), viewport);
  });

  test('clamps a viewport back toward PDF bounds', () {
    const viewport = ViewportState(offset: Offset(1000, -500));
    final clamped = clampViewportToBounds(viewport, bounds, canvas);

    expect(clamped.offset.dx, inInclusiveRange(0, 16));
    expect(clamped.offset.dy, greaterThanOrEqualTo(-16));
    expect(clamped.zoom, viewport.zoom);
  });
}
