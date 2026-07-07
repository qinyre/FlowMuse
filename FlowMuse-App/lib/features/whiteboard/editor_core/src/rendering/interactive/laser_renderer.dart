import 'dart:ui' as ui;

import '../../editor/tools/laser_tool.dart';
import '../viewport_state.dart';

/// Renders the laser pointer's fading trail.
class LaserRenderer {
  LaserRenderer._();

  /// Draws the laser trail on the given canvas.
  ///
  /// Points fade from fully opaque red to transparent over [LaserTool.decayMs].
  static void draw(
    ui.Canvas canvas,
    List<LaserPoint> trail,
    ViewportState viewport,
  ) {
    if (trail.length < 2) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    for (var i = 1; i < trail.length; i++) {
      final prev = trail[i - 1];
      final curr = trail[i];

      final age = now - curr.timestamp;
      final opacity = (1.0 - age / LaserTool.decayMs).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      final p1 = viewport.sceneToScreen(ui.Offset(prev.point.x, prev.point.y));
      final p2 = viewport.sceneToScreen(ui.Offset(curr.point.x, curr.point.y));

      final paint = ui.Paint()
        ..color = ui.Color.fromRGBO(255, 0, 0, opacity)
        ..strokeWidth = 3.0
        ..strokeCap = ui.StrokeCap.round
        ..style = ui.PaintingStyle.stroke;

      canvas.drawLine(p1, p2, paint);
    }
  }
}
