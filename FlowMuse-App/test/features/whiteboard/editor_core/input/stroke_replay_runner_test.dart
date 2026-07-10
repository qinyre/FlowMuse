import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/point.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_sample.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_recorder.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_replay_runner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/stroke_render_metrics.dart';

StrokeInputSample s(double x, double y, int ms, StrokePhase phase) =>
    StrokeInputSample(
      pointerId: 1,
      x: x,
      y: y,
      time: Duration(milliseconds: ms),
      pressure: 0.5,
      kind: StrokeInputKind.stylus,
      phase: phase,
      source: StrokeSampleSource.actual,
    );

StrokeRecording sampleRecording() {
  final r = StrokeRecorder();
  r.record(
    s(0, 0, 0, StrokePhase.down),
    viewportZoom: 1,
    viewportTransform: [1, 0, 0, 1, 0, 0],
  );
  for (var i = 1; i <= 30; i++) {
    r.record(
      s(i.toDouble(), (i % 5) * 0.5, i * 16, StrokePhase.move),
      viewportZoom: 1,
      viewportTransform: [1, 0, 0, 1, 0, 0],
    );
  }
  r.record(
    s(31, 0, 31 * 16, StrokePhase.up),
    viewportZoom: 1,
    viewportTransform: [1, 0, 0, 1, 0, 0],
  );
  return r.finish();
}

void main() {
  test('replay forwards produced render metrics to its result and sink', () {
    final rec = sampleRecording();
    final sink = _MetricsSink();
    final runner = const StrokeReplayRunner();

    final result = runner.run(
      rec,
      modeler: StrokeInputModeler(InputPolicy.stylus),
      metricsProducer: (points, pressures) => StrokeRenderMetrics(
        outlinePointCount: points.length * 2,
        getStrokeDuration: const Duration(microseconds: 10),
        pathBuildDuration: const Duration(microseconds: 5),
      ),
      metricsSink: sink,
    );

    expect(result.perPointMetrics, isNotEmpty);
    expect(result.perPointMetrics, hasLength(sink.metrics.length));
    expect(result.perPointMetrics.last.outlinePointCount, greaterThan(0));
  });

  test(
    'replay is deterministic: same recording + same modeler params => same geometry',
    () {
      final rec = sampleRecording();
      final runner = const StrokeReplayRunner();
      final a = runner.run(
        rec,
        modeler: StrokeInputModeler(InputPolicy.stylus),
      );
      final b = runner.run(
        rec,
        modeler: StrokeInputModeler(InputPolicy.stylus),
      );
      expect(b.emittedPoints, a.emittedPoints);
      expect(b.emittedPressures, a.emittedPressures);
    },
  );

  test('replay emits at least down + up', () {
    final rec = sampleRecording();
    final runner = const StrokeReplayRunner();
    final r = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    expect(r.emittedPoints.length, greaterThanOrEqualTo(2));
    expect(r.emittedPoints.first, const Point(0, 0));
    // up flush: 终点接近真实抬笔点
    expect(r.emittedPoints.last.x, closeTo(31, 1.0));
  });

  test('different policy => different geometry', () {
    final rec = sampleRecording();
    final runner = const StrokeReplayRunner();
    final a = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.stylus));
    final b = runner.run(rec, modeler: StrokeInputModeler(InputPolicy.mouse));
    // mouse 几乎不滤波，几何应与 stylus 有差异
    expect(a.emittedPoints, isNot(equals(b.emittedPoints)));
  });
}

class _MetricsSink implements StrokeRenderMetricsSink {
  final metrics = <StrokeRenderMetrics>[];

  @override
  void onMetrics(StrokeRenderMetrics value) => metrics.add(value);
}
