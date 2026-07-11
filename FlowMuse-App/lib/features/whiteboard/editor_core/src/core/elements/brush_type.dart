enum BrushType {
  pencil('pencil'),
  ballpoint('ballpoint'),
  fountainPen('fountain-pen'),
  brushPen('brush-pen'),
  highlighter('highlighter');

  const BrushType(this.wireName);

  final String wireName;

  bool get canAutoRecognize => this != BrushType.highlighter;

  static BrushType fromWireName(String? value) {
    return switch (value) {
      'pencil' => BrushType.pencil,
      'ballpoint' => BrushType.ballpoint,
      'fountain-pen' || 'fountainPen' => BrushType.fountainPen,
      'brush-pen' || 'brushPen' => BrushType.brushPen,
      'highlighter' => BrushType.highlighter,
      _ => BrushType.fountainPen,
    };
  }
}

/// 每种笔形独立保存的状态（参考 Saber 设计）。
///
/// 切换笔形时自动保存当前设置并恢复新笔形的上次设置，
/// 用起来每支笔都像独立工具。
class BrushState {
  const BrushState({
    this.strokeColor,
    this.strokeWidth,
    this.pressureSensitivity = 0.7,
    this.strokeWidthMin = 1,
    this.strokeWidthMax = 25,
    this.strokeWidthStep = 1,
  });

  /// 笔迹颜色（hex 字符串如 '#1e1e1e'）。
  final String? strokeColor;

  /// 笔迹粗细（逻辑像素）。
  final double? strokeWidth;

  /// 压感灵敏度 (0.0–1.0)。
  final double pressureSensitivity;

  /// 粗细滑块最小值（参考 Saber 每种笔不同范围）。
  final double strokeWidthMin;

  /// 粗细滑块最大值。
  final double strokeWidthMax;

  /// 粗细滑块步长。
  final double strokeWidthStep;

  BrushState copyWith({
    String? strokeColor,
    bool clearStrokeColor = false,
    double? strokeWidth,
    bool clearStrokeWidth = false,
    double? pressureSensitivity,
    double? strokeWidthMin,
    double? strokeWidthMax,
    double? strokeWidthStep,
  }) {
    return BrushState(
      strokeColor: clearStrokeColor ? null : (strokeColor ?? this.strokeColor),
      strokeWidth:
          clearStrokeWidth ? null : (strokeWidth ?? this.strokeWidth),
      pressureSensitivity:
          pressureSensitivity ?? this.pressureSensitivity,
      strokeWidthMin: strokeWidthMin ?? this.strokeWidthMin,
      strokeWidthMax: strokeWidthMax ?? this.strokeWidthMax,
      strokeWidthStep: strokeWidthStep ?? this.strokeWidthStep,
    );
  }

  /// 每种笔形的出厂默认状态（粗细范围参考 Saber）。
  static const defaults = <BrushType, BrushState>{
    BrushType.pencil: BrushState(
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
      strokeWidthMin: 1,
      strokeWidthMax: 15,
    ),
    BrushType.ballpoint: BrushState(
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
    ),
    BrushType.fountainPen: BrushState(
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
    ),
    BrushType.brushPen: BrushState(
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
      pressureSensitivity: 0.85,
    ),
    BrushType.highlighter: BrushState(
      strokeColor: '#ffff00',
      strokeWidth: 20,
      strokeWidthMin: 10,
      strokeWidthMax: 100,
      strokeWidthStep: 10,
    ),
  };
}

const String flowMuseCustomDataKey = 'flowMuse';
const String brushTypeCustomDataKey = 'brushType';

BrushType brushTypeFromCustomData(Map<String, Object?>? customData) {
  final flowMuse = customData?[flowMuseCustomDataKey];
  if (flowMuse is Map<String, Object?>) {
    return BrushType.fromWireName(flowMuse[brushTypeCustomDataKey] as String?);
  }
  if (flowMuse is Map) {
    final value = flowMuse[brushTypeCustomDataKey];
    return BrushType.fromWireName(value is String ? value : null);
  }
  return BrushType.fountainPen;
}

Map<String, Object?> customDataWithBrushType(
  Map<String, Object?>? customData,
  BrushType brushType,
) {
  final next = {...?customData};
  final flowMuse = next[flowMuseCustomDataKey];
  next[flowMuseCustomDataKey] = {
    if (flowMuse is Map<String, Object?>) ...flowMuse,
    if (flowMuse is Map && flowMuse is! Map<String, Object?>)
      for (final entry in flowMuse.entries)
        if (entry.key is String) entry.key as String: entry.value,
    brushTypeCustomDataKey: brushType.wireName,
  };
  return next;
}
