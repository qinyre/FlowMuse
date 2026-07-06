import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class WhiteboardToolbar extends StatelessWidget {
  const WhiteboardToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    const tools = [
      _WhiteboardTool('解锁', LucideIcons.lockOpen),
      _WhiteboardTool('平移', LucideIcons.hand),
      _WhiteboardTool('选择', LucideIcons.mousePointer2),
      _WhiteboardTool('矩形', LucideIcons.square),
      _WhiteboardTool('圆形', LucideIcons.circle),
      _WhiteboardTool('箭头', LucideIcons.arrowRight),
      _WhiteboardTool('画笔', LucideIcons.penLine),
      _WhiteboardTool('文本', LucideIcons.type),
      _WhiteboardTool('图片', LucideIcons.image),
    ];

    return Card(
      elevation: 6,
      shadowColor: const Color(0x175A625F),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tool in tools)
              IconButton(
                tooltip: tool.tooltip,
                onPressed: () {},
                icon: Icon(tool.icon, size: 22),
              ),
          ],
        ),
      ),
    );
  }
}

class _WhiteboardTool {
  const _WhiteboardTool(this.tooltip, this.icon);

  final String tooltip;
  final IconData icon;
}
