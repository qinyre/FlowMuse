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

/// debug/test 下接收指标；release 下 renderer 持有 null sink 不分配。
abstract class StrokeRenderMetricsSink {
  void onMetrics(StrokeRenderMetrics metrics);
}
