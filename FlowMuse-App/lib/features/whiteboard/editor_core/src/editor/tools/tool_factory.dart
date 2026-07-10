import '../tool_type.dart';
import 'arrow_tool.dart';
import 'diamond_tool.dart';
import 'ellipse_tool.dart';
import 'eraser_tool.dart';
import 'frame_tool.dart';
import 'freedraw_tool.dart';
import 'hand_tool.dart';
import 'laser_tool.dart';
import 'line_tool.dart';
import 'rectangle_tool.dart';
import 'select_tool.dart';
import 'text_tool.dart';
import 'tool.dart';

/// Creates a [Tool] instance for the given [ToolType].
Tool createTool(ToolType type) {
  return switch (type) {
    ToolType.select => SelectTool(),
    ToolType.rectangle => RectangleTool(),
    ToolType.ellipse => EllipseTool(),
    ToolType.diamond => DiamondTool(),
    ToolType.line => LineTool(),
    ToolType.arrow => ArrowTool(),
    ToolType.freedraw => FreedrawTool(),
    ToolType.text => TextTool(),
    ToolType.hand => HandTool(),
    ToolType.frame => FrameTool(),
    ToolType.eraser => EraserTool(),
    ToolType.laser => LaserTool(),
  };
}
