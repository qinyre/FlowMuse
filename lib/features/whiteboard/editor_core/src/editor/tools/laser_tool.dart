import 'dart:ui';

import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';
import 'tool.dart';

/// A timestamped point for the laser trail.
class LaserPoint {
  final Point point;
  final int timestamp;

  LaserPoint(this.point, this.timestamp);
}

/// Tool that draws a temporary fading laser trail.
///
/// Points are collected during drag and decay over ~1 second.
/// No elements are created — purely visual feedback.
class LaserTool implements Tool {
  final List<LaserPoint> _trail = [];
  bool _isDragging = false;

  /// The decay duration in milliseconds.
  static const int decayMs = 1000;

  @override
  ToolType get type => ToolType.laser;

  /// The current trail points (scene coordinates + timestamps).
  List<LaserPoint> get activeTrail => List.unmodifiable(_trail);

  /// Removes points older than [decayMs] from the trail.
  /// Returns true if points were removed.
  bool prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - decayMs;
    final before = _trail.length;
    _trail.removeWhere((p) => p.timestamp < cutoff);
    return _trail.length != before;
  }

  @override
  ToolResult? onPointerDown(Point point, ToolContext context) {
    _isDragging = true;
    _trail.clear();
    _trail.add(LaserPoint(point, DateTime.now().millisecondsSinceEpoch));
    return null;
  }

  @override
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  }) {
    if (!_isDragging) return null;
    _trail.add(LaserPoint(point, DateTime.now().millisecondsSinceEpoch));
    return null;
  }

  @override
  ToolResult? onPointerUp(Point point, ToolContext context) {
    _isDragging = false;
    // Trail stays visible and decays over time
    return null;
  }

  @override
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  }) {
    return null;
  }

  @override
  ToolOverlay? get overlay => null;

  @override
  void reset() {
    _isDragging = false;
    _trail.clear();
  }
}
