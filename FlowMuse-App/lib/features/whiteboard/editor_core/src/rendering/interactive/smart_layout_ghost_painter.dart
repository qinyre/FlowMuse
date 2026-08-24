import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../core/smart_layout/smart_layout_plan.dart';
import '../viewport_state.dart';
import 'selection_renderer.dart';

/// 智能排版幽灵预览/失败红框绘制：场景坐标系 + 视口变换（与 InteractiveCanvasPainter 一致）。
class SmartLayoutGhostPainter extends CustomPainter {
  SmartLayoutGhostPainter({required this.spec, required this.viewport});

  final SmartLayoutGhostSpec spec;
  final ViewportState viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(viewport.zoom);
    canvas.translate(-viewport.offset.dx, -viewport.offset.dy);
    if (spec.isFailure) {
      for (final rect in spec.failureRects) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0x11E03131),
        );
        _dashRect(
          canvas,
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..color = const Color(0xFFE03131),
        );
      }
    } else {
      for (final rect in spec.previewRects) {
        SelectionRenderer.drawMarquee(canvas, rect);
      }
      for (final rect in spec.removalRects) {
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = const Color(0x11888888),
        );
        _dashRect(
          canvas,
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xAA888888),
        );
      }
    }
    canvas.restore();
  }

  void _dashRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    void dashLine(Offset from, Offset to) {
      final length = (to - from).distance;
      if (length <= 0) return;
      var covered = 0.0;
      while (covered < length) {
        final end = math.min(covered + dash, length);
        canvas.drawLine(
          from + (to - from) * (covered / length),
          from + (to - from) * (end / length),
          paint,
        );
        covered = end + gap;
      }
    }

    dashLine(rect.topLeft, rect.topRight);
    dashLine(rect.topRight, rect.bottomRight);
    dashLine(rect.bottomRight, rect.bottomLeft);
    dashLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant SmartLayoutGhostPainter oldDelegate) =>
      oldDelegate.spec != spec || oldDelegate.viewport != viewport;
}
