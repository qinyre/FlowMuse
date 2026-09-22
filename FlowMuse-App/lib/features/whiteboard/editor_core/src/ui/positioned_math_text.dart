import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import '../rendering/collaboration_focus_alpha.dart';

class PositionedMathText extends StatelessWidget {
  const PositionedMathText({
    super.key,
    required this.element,
    required this.viewport,
    this.focusedCreatorKey,
    this.focusHistoricalContent = false,
    this.highlightedElementIds = const {},
  });

  final TextElement element;
  final ViewportState viewport;
  final String? focusedCreatorKey;
  final bool focusHistoricalContent;
  final Set<ElementId> highlightedElementIds;

  @override
  Widget build(BuildContext context) {
    final zoom = viewport.zoom;
    final left = (element.x - viewport.offset.dx) * zoom;
    final top = (element.y - viewport.offset.dy) * zoom;
    final width = element.width * zoom;
    final height = element.height * zoom;
    final focusAlpha = collaborationFocusAlpha(
      element,
      focusedCreatorKey: focusedCreatorKey,
      focusHistoricalContent: focusHistoricalContent,
      highlightedElementIds: highlightedElementIds,
    );
    final color = parseColor(
      element.strokeColor,
    ).withValues(alpha: element.opacity * focusAlpha);

    final child = Align(
      alignment: Alignment.topLeft,
      child: Math.tex(
        element.text,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(color: color, fontSize: element.fontSize * zoom),
        onErrorFallback: (_) => Text(
          element.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: element.fontSize * zoom,
            height: element.lineHeight,
            fontFamily: element.fontFamily,
          ),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: element.angle,
        alignment: Alignment.center,
        child: ClipRect(child: child),
      ),
    );
  }
}
