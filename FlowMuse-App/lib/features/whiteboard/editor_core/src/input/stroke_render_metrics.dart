import '../core/math/point.dart';

/// 单笔渲染的 CPU 性能指标。
///
/// 注意：Canvas.drawPath 的耗时只能衡量命令提交，不代表 GPU/raster；
/// 端到端帧性能应使用 Flutter FrameTiming / DevTools。
class StrokeRenderMetrics {
  const StrokeRenderMetrics({
    required this.outlinePointCount,
    required this.getStrokeDuration,
    required this.pathBuildDuration,
  });
  final int outlinePointCount;
  final Duration getStrokeDuration;
  final Duration pathBuildDuration;

  @override
  String toString() =>
      'StrokeRenderMetrics(outline=$outlinePointCount, '
      'getStroke=${getStrokeDuration.inMicroseconds}µs, '
      'path=${pathBuildDuration.inMicroseconds}µs)';
}

/// 在回放中基于已建模的中心点生成真实渲染指标。
typedef StrokeReplayMetricsProducer =
    StrokeRenderMetrics Function(List<Point> points, List<double?> pressures);

/// debug/test 下接收指标；release 下 renderer 持有 null sink 不分配。
abstract class StrokeRenderMetricsSink {
  void onMetrics(StrokeRenderMetrics metrics);
}
