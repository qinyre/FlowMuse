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
