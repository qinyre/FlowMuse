import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_type.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/harmony_stylus_stroke_smoother.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HarmonyStylusStrokeSmoother', () {
    test('smooths and filters jitter for OHOS stylus freedraw input', () {
      final smoother = HarmonyStylusStrokeSmoother();

      final down = smoother.down(
        point: const Point(0, 0),
        pressure: 0.4,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );
      expect(down?.point, const Point(0, 0));
      expect(down?.pressure, 0.4);

      final jitter = smoother.move(
        point: const Point(0.2, 0.1),
        pressure: 0.8,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );
      expect(jitter, isNull);

      final smoothed = smoother.move(
        point: const Point(10, 0),
        pressure: 1.0,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );
      expect(smoothed?.point.x, closeTo(3.5, 0.001));
      expect(smoothed?.point.y, closeTo(0, 0.001));
      expect(smoothed?.pressure, closeTo(0.67, 0.001));
    });

    test('passes through stylus input on non-OHOS platforms', () {
      final smoother = HarmonyStylusStrokeSmoother();

      final down = smoother.down(
        point: const Point(0, 0),
        pressure: 0.4,
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );
      final move = smoother.move(
        point: const Point(10, 0),
        pressure: 1.0,
        platform: TargetPlatform.android,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );

      expect(down?.point, const Point(0, 0));
      expect(move?.point, const Point(10, 0));
      expect(move?.pressure, 1.0);
    });

    test('passes through OHOS touch input', () {
      final smoother = HarmonyStylusStrokeSmoother();

      final down = smoother.down(
        point: const Point(0, 0),
        pressure: null,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.touch,
        activeToolType: ToolType.freedraw,
      );
      final move = smoother.move(
        point: const Point(0.2, 0.1),
        pressure: null,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.touch,
        activeToolType: ToolType.freedraw,
      );

      expect(down?.point, const Point(0, 0));
      expect(move?.point, const Point(0.2, 0.1));
      expect(move?.pressure, isNull);
    });

    test('passes through OHOS stylus input outside freedraw', () {
      final smoother = HarmonyStylusStrokeSmoother();

      final down = smoother.down(
        point: const Point(0, 0),
        pressure: 0.4,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.line,
      );
      final move = smoother.move(
        point: const Point(0.2, 0.1),
        pressure: 0.8,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.line,
      );

      expect(down?.point, const Point(0, 0));
      expect(move?.point, const Point(0.2, 0.1));
      expect(move?.pressure, 0.8);
    });

    test('keeps emitted OHOS stylus points and pressures aligned', () {
      final smoother = HarmonyStylusStrokeSmoother();
      final samples = [
        smoother.down(
          point: const Point(0, 0),
          pressure: 0.2,
          platform: TargetPlatform.ohos,
          kind: PointerDeviceKind.stylus,
          activeToolType: ToolType.freedraw,
        ),
        smoother.move(
          point: const Point(5, 0),
          pressure: 0.6,
          platform: TargetPlatform.ohos,
          kind: PointerDeviceKind.stylus,
          activeToolType: ToolType.freedraw,
        ),
        smoother.up(
          point: const Point(10, 0),
          pressure: 1.0,
          platform: TargetPlatform.ohos,
          kind: PointerDeviceKind.stylus,
          activeToolType: ToolType.freedraw,
        ),
      ].nonNulls.toList();

      expect(samples, hasLength(3));
      expect(samples.map((sample) => sample.point), hasLength(samples.length));
      expect(
        samples.map((sample) => sample.pressure).whereType<double>(),
        hasLength(samples.length),
      );
    });

    test('preserves the raw terminal point on pointer up', () {
      final smoother = HarmonyStylusStrokeSmoother();
      smoother.down(
        point: const Point(0, 0),
        pressure: 0.2,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );
      smoother.move(
        point: const Point(5, 0),
        pressure: 0.6,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );

      final up = smoother.up(
        point: const Point(10, 0),
        pressure: 1.0,
        platform: TargetPlatform.ohos,
        kind: PointerDeviceKind.stylus,
        activeToolType: ToolType.freedraw,
      );

      expect(up?.point, const Point(10, 0));
    });
  });
}
