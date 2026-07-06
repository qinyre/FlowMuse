import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../view_models/whiteboard_view_model.dart';

class WhiteboardToolbar extends StatelessWidget {
  const WhiteboardToolbar({
    super.key,
    required this.activeTool,
    required this.canUndo,
    required this.canRedo,
    required this.onToolSelected,
    required this.onUndo,
    required this.onRedo,
  });

  final WhiteboardTool activeTool;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<WhiteboardTool> onToolSelected;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    const tools = [
      _WhiteboardTool('平移', LucideIcons.hand, WhiteboardTool.hand),
      _WhiteboardTool('选择', LucideIcons.mousePointer2, WhiteboardTool.select),
      _WhiteboardTool('矩形', LucideIcons.square, WhiteboardTool.rectangle),
      _WhiteboardTool('圆形', LucideIcons.circle, WhiteboardTool.ellipse),
      _WhiteboardTool('箭头', LucideIcons.arrowRight, WhiteboardTool.arrow),
      _WhiteboardTool('画笔', LucideIcons.penLine, WhiteboardTool.pen),
      _WhiteboardTool('文本', LucideIcons.type, WhiteboardTool.text),
    ];

    return Card(
      elevation: 6,
      shadowColor: const Color(0x175A625F),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '撤销',
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(LucideIcons.undo2, size: 22),
            ),
            IconButton(
              tooltip: '重做',
              onPressed: canRedo ? onRedo : null,
              icon: const Icon(LucideIcons.redo2, size: 22),
            ),
            const SizedBox(width: 6),
            for (final tool in tools)
              IconButton(
                key: ValueKey('whiteboard-tool-${tool.tool.name}'),
                tooltip: tool.tooltip,
                isSelected: activeTool == tool.tool,
                onPressed: () => onToolSelected(tool.tool),
                icon: Icon(tool.icon, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}

class _WhiteboardTool {
  const _WhiteboardTool(this.tooltip, this.icon, this.tool);

  final String tooltip;
  final IconData icon;
  final WhiteboardTool tool;
}
