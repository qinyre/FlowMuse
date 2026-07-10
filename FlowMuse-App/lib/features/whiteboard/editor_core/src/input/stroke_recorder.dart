// lib/features/whiteboard/editor_core/src/input/stroke_recorder.dart
import 'dart:convert';
import 'stroke_input_sample.dart';

/// 一段录制：规范化样本序列 + viewport 元数据 + 构建信息。
class StrokeRecording {
  const StrokeRecording({
    required this.samples,
    required this.viewportZoom,
    required this.viewportTransform,
    this.buildVersion,
    this.deviceInfo,
  });

  final List<StrokeInputSample> samples;
  final double viewportZoom;
  /// 仿射变换 [a,b,c,d,e,f]（scene = a*localX + c*localY + e, ...）。
  final List<double> viewportTransform;
  final String? buildVersion;
  final String? deviceInfo;

  Map<String, dynamic> toJson() => {
    'samples': [for (final s in samples) _sampleToJson(s)],
    'viewportZoom': viewportZoom,
    'viewportTransform': viewportTransform,
    'buildVersion': buildVersion,
    'deviceInfo': deviceInfo,
  };

  static StrokeRecording fromJson(Map<String, dynamic> json) => StrokeRecording(
    samples: (json['samples'] as List)
        .map((e) => _sampleFromJson(e as Map<String, dynamic>))
        .toList(),
    viewportZoom: (json['viewportZoom'] as num).toDouble(),
    viewportTransform: (json['viewportTransform'] as List).map((e) => (e as num).toDouble()).toList(),
    buildVersion: json['buildVersion'] as String?,
    deviceInfo: json['deviceInfo'] as String?,
  );

  @override
  String toString() => 'StrokeRecording(${samples.length} samples, zoom=$viewportZoom)';

  static Map<String, dynamic> _sampleToJson(StrokeInputSample s) => {
    'pointerId': s.pointerId, 'x': s.x, 'y': s.y,
    'timeUs': s.time.inMicroseconds, 'pressure': s.pressure,
    'kind': s.kind.name, 'phase': s.phase.name, 'source': s.source.name,
  };
  static StrokeInputSample _sampleFromJson(Map<String, dynamic> m) {
    return StrokeInputSample(
      pointerId: m['pointerId'] as int,
      x: (m['x'] as num).toDouble(), y: (m['y'] as num).toDouble(),
      time: Duration(microseconds: m['timeUs'] as int),
      pressure: (m['pressure'] as num?)?.toDouble(),
      kind: StrokeInputKind.values.byName(m['kind'] as String),
      phase: StrokePhase.values.byName(m['phase'] as String),
      source: StrokeSampleSource.values.byName(m['source'] as String),
    );
  }
}

/// debug/test 用录制器：收集规范化样本与 viewport 元数据。
class StrokeRecorder {
  final List<StrokeInputSample> _samples = [];
  double _zoom = 1.0;
  List<double> _transform = const [1,0,0,1,0,0];

  void record(StrokeInputSample sample, {required double viewportZoom, required List<double> viewportTransform}) {
    _samples.add(sample);
    _zoom = viewportZoom;
    _transform = viewportTransform;
  }

  StrokeRecording finish({String? buildVersion, String? deviceInfo}) => StrokeRecording(
    samples: List.unmodifiable(_samples),
    viewportZoom: _zoom,
    viewportTransform: List.unmodifiable(_transform),
    buildVersion: buildVersion,
    deviceInfo: deviceInfo,
  );

  void clear() { _samples.clear(); _zoom = 1.0; _transform = const [1,0,0,1,0,0]; }
}
