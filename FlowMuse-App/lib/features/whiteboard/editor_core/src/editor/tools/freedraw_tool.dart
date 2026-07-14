import 'dart:collection';
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

/// Tool for creating freehand drawing elements by continuous path recording.
///
/// 当 pressure 参数可用(手写笔)时,收集真实压感并存入 FreedrawElement.pressures,
/// simulatePressure 置 false。当 pressure 为 null(鼠标/触摸)时,pressures 留空,
/// simulatePressure 置 true,由渲染层用速度模拟(Excalidraw 兼容行为)。
class FreedrawTool implements Tool {
  final List<Point> _points = [];
  final List<double> _pressures = [];
  late final List<Point> _previewPoints = UnmodifiableListView(_points);
  late final List<double> _previewPressures = UnmodifiableListView(_pressures);
  final List<int> _pointTimes = [];
  bool _hasRealPressure = false;
  bool _isDrawing = false;
  ElementId? _liveElementId;
  int _liveVersion = 0;
  FreedrawElement? _liveElement;
  String? _sessionId;
  int? _startedAt;

  @override
  ToolType get type => ToolType.freedraw;

  FreedrawElement? get liveElement => _liveElement;

  @override
  ToolResult? onPointerDown(
    Point point,
    ToolContext context, {
    double? pressure,
  }) {
    _isDrawing = true;
    if (context.inkRecognitionMode && context.brushType.canAutoRecognize) {
      _sessionId ??= ElementId.generate().value;
      _startedAt ??= DateTime.now().millisecondsSinceEpoch;
      _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
    }
    _points.add(point);
    _recordPressure(pressure);
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
    if (_sessionId != null) {
      _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
    }
    _points.add(point);
    _recordPressure(pressure);
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

    if (_points.last != point) {
      if (_sessionId != null) {
        _pointTimes.add(DateTime.now().millisecondsSinceEpoch);
      }
      _points.add(point);
      _recordPressure(pressure);
    } else if (_hasRealPressure && pressure != null) {
      _pressures[_pressures.length - 1] = pressure;
    }

    final element = _buildElement(context, isComplete: true);

    _clearStrokeState();
    return AddElementResult(element);
  }

  /// Builds a tombstone for peers when Flutter cancels an in-progress stroke.
  FreedrawElement? cancelStroke() {
    final live = _liveElement;
    if (live == null) {
      reset();
      return null;
    }
    final tombstone = live.copyWith(isDeleted: true, version: ++_liveVersion);
    _clearStrokeState(clearSession: true);
    return tombstone;
  }

  /// Builds a collaboration-only snapshot on demand.
  ///
  /// Pointer moves intentionally do not call this: constructing a complete
  /// element copies every point in the active stroke, so callers must throttle
  /// snapshots outside the input hot path.
  FreedrawElement? buildLiveElement(ToolContext context) {
    if (!_isDrawing || _points.isEmpty) {
      return null;
    }
    return _liveElement = _buildElement(context, isComplete: false);
  }

  void startNewSession() {
    _sessionId = ElementId.generate().value;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
  }

  /// 记录压感。首点收到非 null pressure 即判定本次笔画为真压感,
  /// 后续 null 不再回退(同一笔不应混用真/模拟压感)。
  void _recordPressure(double? pressure) {
    if (_points.length == 1 && pressure != null) {
      _hasRealPressure = true;
    }
    if (_hasRealPressure) {
      // pressure 可能为 null(极少数情况),用最后一个已知值兜底
      _pressures.add(
        pressure ?? (_pressures.isNotEmpty ? _pressures.last : 0.5),
      );
    }
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
    return ToolOverlay(
      creationPoints: _previewPoints,
      creationPressures: _hasRealPressure ? _previewPressures : const [],
      creationIsComplete: false,
      showCreationPreviewLine: false,
    );
  }

  @override
  void reset() {
    _clearStrokeState(clearSession: true);
  }

  void _clearStrokeState({bool clearSession = false}) {
    _points.clear();
    _pressures.clear();
    _pointTimes.clear();
    _hasRealPressure = false;
    _isDrawing = false;
    _liveElementId = null;
    _liveVersion = 0;
    _liveElement = null;
    if (clearSession) {
      _sessionId = null;
      _startedAt = null;
    }
  }

  FreedrawElement _buildElement(
    ToolContext context, {
    required bool isComplete,
  }) {
    final id = _liveElementId ??= ElementId.generate();
    final minX = _points.map((p) => p.x).reduce(math.min);
    final minY = _points.map((p) => p.y).reduce(math.min);
    final maxX = _points.map((p) => p.x).reduce(math.max);
    final maxY = _points.map((p) => p.y).reduce(math.max);
    var customData = customDataWithBrushType(null, context.brushType);
    if (_sessionId != null) {
      customData = {
        ...customData,
        recognitionStrokeSessionKey: _sessionId,
        recognitionStrokePendingKey: true,
        recognitionStrokeStartedAtKey: _startedAt,
        recognitionStrokePointTimesKey: List<int>.unmodifiable(_pointTimes),
      };
    }
    final element = FreedrawElement(
      id: id,
      x: minX,
      y: minY,
      width: math.max(maxX - minX, 1.0),
      height: math.max(maxY - minY, 1.0),
      points: _points.map((p) => Point(p.x - minX, p.y - minY)).toList(),
      pressures: _hasRealPressure ? List.unmodifiable(_pressures) : const [],
      simulatePressure: !_hasRealPressure,
      isComplete: isComplete,
      version: ++_liveVersion,
      customData: customData,
    );
    return element;
  }
}
