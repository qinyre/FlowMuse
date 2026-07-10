// test/features/whiteboard/editor_core/input/stroke_input_normalizer_test.dart
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart';

PointerEvent mkEvent({
  required Offset localPosition,
  required PointerDeviceKind kind,
  double pressure = 0.0,
  int pointer = 1,
  Duration timeStamp = const Duration(milliseconds: 16),
}) => PointerMoveEvent(
  pointer: pointer, position: localPosition,
  kind: kind, pressure: pressure, timeStamp: timeStamp, delta: Offset.zero,
);

void main() {
  test('stylus with pressure > 0 yields real pressure', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(10,20), kind: PointerDeviceKind.stylus, pressure: 0.5), phase: StrokePhase.move);
    expect(s, isNotNull);
    expect(s!.pressure, 0.5);
    expect(s.kind, StrokeInputKind.stylus);
  });

  test('mouse pressure is dropped to null', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(1,2), kind: PointerDeviceKind.mouse, pressure: 0.5), phase: StrokePhase.move);
    expect(s!.pressure, isNull);
    expect(s.kind, StrokeInputKind.mouse);
  });

  test('maps device kind to StrokeInputKind', () {
    final n = StrokeInputNormalizer();
    expect(n.normalize(mkEvent(localPosition: Offset.zero, kind: PointerDeviceKind.touch), phase: StrokePhase.down)!.kind, StrokeInputKind.touch);
    expect(n.normalize(mkEvent(localPosition: Offset.zero, kind: PointerDeviceKind.stylus), phase: StrokePhase.down)!.kind, StrokeInputKind.stylus);
  });

  test('passes pointer id, timestamp, local coords', () {
    final n = StrokeInputNormalizer();
    final s = n.normalize(mkEvent(localPosition: const Offset(5,6), kind: PointerDeviceKind.stylus, pointer: 7, timeStamp: const Duration(milliseconds: 99)), phase: StrokePhase.down)!;
    expect(s.pointerId, 7);
    expect(s.x, 5); expect(s.y, 6);
    expect(s.time, const Duration(milliseconds: 99));
  });
}
