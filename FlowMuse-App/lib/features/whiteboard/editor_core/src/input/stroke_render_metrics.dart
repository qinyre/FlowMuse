import 'package:flutter/scheduler.dart';

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

/// 与 [FrameTiming.frameNumber] 一一对应的 UI 帧耗时。
class FrameRenderMetrics {
  const FrameRenderMetrics({
    required this.frameNumber,
    required this.buildMicros,
    required this.rasterMicros,
    required this.totalSpanMicros,
  });

  factory FrameRenderMetrics.fromTiming(FrameTiming timing) {
    return FrameRenderMetrics(
      frameNumber: timing.frameNumber,
      buildMicros: timing.buildDuration.inMicroseconds,
      rasterMicros: timing.rasterDuration.inMicroseconds,
      totalSpanMicros: timing.totalSpan.inMicroseconds,
    );
  }

  final int frameNumber;
  final int buildMicros;
  final int rasterMicros;
  final int totalSpanMicros;

  Map<String, Object?> toJson() => {
    'frameNumber': frameNumber,
    'buildMicros': buildMicros,
    'rasterMicros': rasterMicros,
    'totalSpanMicros': totalSpanMicros,
  };

  factory FrameRenderMetrics.fromJson(Map<String, Object?> json) {
    return FrameRenderMetrics(
      frameNumber: json['frameNumber']! as int,
      buildMicros: json['buildMicros']! as int,
      rasterMicros: json['rasterMicros']! as int,
      totalSpanMicros: json['totalSpanMicros']! as int,
    );
  }
}

/// 收集 Flutter 已完成帧；回调到达时间不参与输入延迟计算。
class FrameTimingMetricsCollector {
  final List<FrameRenderMetrics> _frames = [];
  bool _started = false;

  List<FrameRenderMetrics> get frames => List.unmodifiable(_frames);

  void start() {
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_started) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _started = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(timings.map(FrameRenderMetrics.fromTiming));
  }
}
