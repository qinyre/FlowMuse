// lib/features/whiteboard/editor_core/src/input/stroke_input_sample.dart

/// 与 Flutter `PointerDeviceKind` 解耦的输入设备分类。
enum StrokeInputKind { stylus, invertedStylus, touch, mouse, unknown }

/// 笔画事件阶段。
enum StrokePhase { down, move, up, cancel }

/// 样本来源：真实采样 or 预测点（仅湿墨层）。
enum StrokeSampleSource { actual, predicted }

/// 整个书写管线的通用货币：规范化后的单个输入样本。
///
/// 坐标 [x]/[y] 为 EditorCanvas local logical pixels（未做 screenToScene）。
/// [time] 为单调时间戳，是采样率无关滤波的关键。
class StrokeInputSample {
  const StrokeInputSample({
    required this.pointerId,
    required this.x,
    required this.y,
    required this.time,
    required this.pressure,
    required this.kind,
    required this.phase,
    required this.source,
  });

  final int pointerId;
  final double x;
  final double y;
  final Duration time;
  final double? pressure; // null = 无可靠真实压感
  final StrokeInputKind kind;
  final StrokePhase phase;
  final StrokeSampleSource source;

  StrokeInputSample copyWith({
    int? pointerId, double? x, double? y, Duration? time,
    double? pressure, StrokeInputKind? kind, StrokePhase? phase,
    StrokeSampleSource? source,
  }) => StrokeInputSample(
    pointerId: pointerId ?? this.pointerId,
    x: x ?? this.x, y: y ?? this.y, time: time ?? this.time,
    pressure: pressure ?? this.pressure, kind: kind ?? this.kind,
    phase: phase ?? this.phase, source: source ?? this.source,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeInputSample &&
          pointerId == other.pointerId && x == other.x && y == other.y &&
          time == other.time && pressure == other.pressure &&
          kind == other.kind && phase == other.phase && source == other.source;

  @override
  int get hashCode => Object.hash(pointerId, x, y, time, pressure, kind, phase, source);

  @override
  String toString() =>
      'StrokeInputSample(ptr=$pointerId, $x,$y, t=${time.inMicroseconds}µs, '
      'p=$pressure, $kind, $phase, $source)';
}
