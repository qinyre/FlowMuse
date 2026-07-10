// test/features/whiteboard/editor_core/input/stroke_input_sample_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';

void main() {
  group('StrokeInputSample', () {
    test('constructs with required fields', () {
      const s = StrokeInputSample(
        pointerId: 1,
        x: 10.0,
        y: 20.0,
        time: Duration(milliseconds: 16),
        pressure: 0.5,
        kind: StrokeInputKind.stylus,
        phase: StrokePhase.move,
        source: StrokeSampleSource.actual,
      );
      expect(s.pointerId, 1);
      expect(s.x, 10.0);
      expect(s.y, 20.0);
      expect(s.time, const Duration(milliseconds: 16));
      expect(s.pressure, 0.5);
      expect(s.kind, StrokeInputKind.stylus);
      expect(s.phase, StrokePhase.move);
      expect(s.source, StrokeSampleSource.actual);
    });

    test('pressure may be null', () {
      const s = StrokeInputSample(
        pointerId: 1, x: 0, y: 0, time: Duration.zero,
        pressure: null, kind: StrokeInputKind.mouse,
        phase: StrokePhase.down, source: StrokeSampleSource.actual,
      );
      expect(s.pressure, isNull);
    });

    test('value equality', () {
      const a = StrokeInputSample(
        pointerId: 1, x: 1, y: 2, time: Duration(milliseconds: 5),
        pressure: 0.3, kind: StrokeInputKind.touch,
        phase: StrokePhase.up, source: StrokeSampleSource.actual,
      );
      const b = StrokeInputSample(
        pointerId: 1, x: 1, y: 2, time: Duration(milliseconds: 5),
        pressure: 0.3, kind: StrokeInputKind.touch,
        phase: StrokePhase.up, source: StrokeSampleSource.actual,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
