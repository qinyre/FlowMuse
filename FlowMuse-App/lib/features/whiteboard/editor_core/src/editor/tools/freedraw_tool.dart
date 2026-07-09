import 'dart:math' as math;
import 'dart:ui';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// Tool for creating freehand drawing elements by continuous path recording.
///
/// 当 pressure 参数可用(手写笔)时,收集真实压感并存入 FreedrawElement.pressures,
/// simulatePressure 置 false。当 pressure 为 null(鼠标/触摸)时,pressures 留空,
/// simulatePressure 置 true,由渲染层用速度模拟(Excalidraw 兼容行为)。
class FreedrawTool implements Tool {
  final List<Point> _points = [];
  final List<double> _pressures = [];
  bool _hasRealPressure = false;
  bool _isDrawing = false;

  @override
  ToolType get type => ToolType.freedraw;

  @override
  ToolResult? onPointerDown(
    Point point,
    ToolContext context, {
    double? pressure,
  }) {
    _isDrawing = true;
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
      _points.add(point);
      _recordPressure(pressure);
    } else if (_hasRealPressure && pressure != null) {
      _pressures[_pressures.length - 1] = pressure;
    }

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
      width: maxX - minX,
      height: maxY - minY,
      points: relativePoints,
      pressures: _hasRealPressure ? List.unmodifiable(_pressures) : const [],
      simulatePressure: !_hasRealPressure,
    );

    reset();
    return AddElementResult(element);
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
    return ToolOverlay(creationPoints: List.unmodifiable(_points));
  }

  @override
  void reset() {
    _points.clear();
    _pressures.clear();
    _hasRealPressure = false;
    _isDrawing = false;
  }
}
