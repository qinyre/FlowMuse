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
  ToolResult? onPointerDown(Point point, ToolContext context);

  /// Called when a pointer/touch moves.
  /// [point] is in scene coordinates.
  /// [screenDelta] is the raw screen-space movement (used by HandTool).
  ToolResult? onPointerMove(
    Point point,
    ToolContext context, {
    Offset? screenDelta,
  });

  /// Called when a pointer/touch ends.
  /// [point] is in scene coordinates.
  ToolResult? onPointerUp(Point point, ToolContext context);

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
