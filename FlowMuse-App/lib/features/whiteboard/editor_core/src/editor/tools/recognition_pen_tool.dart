import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

const String recognitionStrokeSessionKey = 'flowmuse.recognition.sessionId';
const String recognitionStrokePendingKey = 'flowmuse.recognition.pending';
const String recognitionStrokeStartedAtKey = 'flowmuse.recognition.startedAt';
const String recognitionStrokePointTimesKey = 'flowmuse.recognition.pointTimes';

class RecognitionPenTool implements Tool {
  final List<Point> _points = [];
  final List<int> _pointTimes = [];
  bool _isDrawing = false;
  String? _sessionId;
  int? _startedAt;

  @override
  ToolType get type => ToolType.recognitionPen;

  @override
  ToolResult? onPointerDown(
    Point point,
    ToolContext context, {
    double? pressure,
  }) {
    _isDrawing = true;
    _sessionId ??= ElementId.generate().value;
    _startedAt ??= DateTime.now().millisecondsSinceEpoch;
    _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
    _points.add(point);
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
    double? pressure,
  }) {
    if (!_isDrawing) return null;
    _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
    _points.add(point);
    return null;
  }

  @override
  ToolResult? onPointerUp(
    Point point,
    ToolContext context, {
    double? pressure,
  }) {
    if (!_isDrawing || _points.isEmpty) {
      reset();
      return null;
    }
    _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
    _points.add(point);
    final minX = _points.map((p) => p.x).reduce(math.min);
    final minY = _points.map((p) => p.y).reduce(math.min);
    final maxX = _points.map((p) => p.x).reduce(math.max);
    final maxY = _points.map((p) => p.y).reduce(math.max);
    final relativePoints = _points
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();
    final element = FreedrawElement(
      id: ElementId.generate(),
      x: minX,
      y: minY,
      width: math.max(maxX - minX, 1.0),
      height: math.max(maxY - minY, 1.0),
      points: relativePoints,
      simulatePressure: true,
      customData: {
        recognitionStrokeSessionKey: _sessionId,
        recognitionStrokePendingKey: true,
        recognitionStrokeStartedAtKey: _startedAt,
        recognitionStrokePointTimesKey: List<int>.unmodifiable(_pointTimes),
      },
    );
    _points.clear();
    _pointTimes.clear();
    _isDrawing = false;
    return CompoundResult([
      AddElementResult(element),
      SetSelectionResult({element.id}),
    ]);
  }

  void startNewSession() {
    _sessionId = ElementId.generate().value;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    if (key == 'Escape') reset();
    return null;
  }

  @override
  ToolOverlay? get overlay {
    if (_points.isEmpty) return null;
    return ToolOverlay(creationPoints: List.unmodifiable(_points));
  }

  @override
  void reset() {
    _points.clear();
    _pointTimes.clear();
    _isDrawing = false;
    _sessionId = null;
    _startedAt = null;
  }
}
