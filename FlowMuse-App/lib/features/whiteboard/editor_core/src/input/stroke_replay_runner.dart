import '../core/math/point.dart';
import 'stroke_input_sample.dart';
import 'stroke_input_modeler.dart';
import 'stroke_recorder.dart';
import 'stroke_render_metrics.dart';

class ReplayResult {
  const ReplayResult({
    required this.emittedPoints,
    required this.emittedPressures,
    required this.perPointMetrics,
  });
  final List<Point> emittedPoints;
  final List<double?> emittedPressures;
  final List<StrokeRenderMetrics> perPointMetrics;
}

/// 用同一录制样本重复运行不同 modeler 参数，输出几何与指标。
/// 自检门槛：相同 recording + 相同参数 → 确定性几何（见测试）。
class StrokeReplayRunner {
  const StrokeReplayRunner();

  ReplayResult run(
    StrokeRecording recording, {
    required StrokeInputModeler modeler,
    StrokeReplayMetricsProducer? metricsProducer,
    StrokeRenderMetricsSink? metricsSink,
  }) {
    final points = <Point>[];
    final pressures = <double?>[];
    final metrics = <StrokeRenderMetrics>[];
    modeler.reset(reason: 'replay start');
    for (final sample in recording.samples) {
      final r = modeler.process(sample);
      if (r.decision == StrokeModelDecision.emitted && r.point != null) {
        points.add(r.point!);
        pressures.add(r.pressure);
        if (metricsProducer != null) {
          final metric = metricsProducer(points, pressures);
          metrics.add(metric);
          metricsSink?.onMetrics(metric);
        }
      }
    }
    return ReplayResult(
      emittedPoints: List.unmodifiable(points),
      emittedPressures: List.unmodifiable(pressures),
      perPointMetrics: List.unmodifiable(metrics),
    );
  }
}
