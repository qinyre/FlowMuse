import 'dart:ui';

import '../../core/math/math.dart';
import '../tool_result.dart';
import '../tool_type.dart';

/// Abstract base class for all editor tools.
///
/// Tools are stateful — they track drag start, creation points, etc.
/// They produce [ToolResult] descriptions instead of directly modifying state.
/// The widget holds tool instances and applies results to [EditorState].
abstract class Tool {
  /// The type of this tool.
  ToolType get type;

  /// Called when a pointer/touch starts.
  /// [point] is in scene coordinates.
  /// [pressure] is the normalized stylus pressure 0.0–1.0 (null when
  /// unavailable, e.g. mouse/touch). Consumed by pressure-aware tools.
  ToolResult? onPointerDown(Point point, ToolContext context, {double? pressure});

  /// Called when a pointer/touch moves.
  /// [point] is in scene coordinates.
  /// [screenDelta] is the raw screen-space movement (used by HandTool).
  /// [pressure] is the normalized stylus pressure 0.0–1.0 (null when unavailable).
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
    double? pressure,
  });

  /// Called when a pointer/touch ends.
  /// [point] is in scene coordinates.
  /// [pressure] is the normalized stylus pressure 0.0–1.0 (null when unavailable).
  ToolResult? onPointerUp(Point point, ToolContext context, {double? pressure});

  /// Called on key events.
  /// [context] is provided for tools that need scene/selection info (e.g., SelectTool).
  ToolResult? onKeyEvent(
    String key, {
    bool shift = false,
    bool ctrl = false,
    ToolContext? context,
  });

  /// Transient overlay data for the UI layer (e.g., creation preview).
  ToolOverlay? get overlay;

  /// Resets the tool's internal state (e.g., after cancel).
  void reset();
}
