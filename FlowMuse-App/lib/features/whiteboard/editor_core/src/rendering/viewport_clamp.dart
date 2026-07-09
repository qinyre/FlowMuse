import 'dart:ui';

import '../core/math/math.dart';
import 'viewport_state.dart';

ViewportState clampViewportToBounds(
  ViewportState viewport,
  Bounds? bounds,
  Size canvasSize, {
  double padding = 16,
}) {
  if (bounds == null || canvasSize.width <= 0 || canvasSize.height <= 0) {
    return viewport;
  }

  final viewWidth = canvasSize.width / viewport.zoom;
  final viewHeight = canvasSize.height / viewport.zoom;
  final contentFitsX = bounds.size.width <= viewWidth;
  final contentFitsY = bounds.size.height <= viewHeight;
  final minX = contentFitsX
      ? bounds.right - viewWidth - padding
      : bounds.left - padding;
  final maxX = contentFitsX
      ? bounds.left + padding
      : bounds.right - viewWidth + padding;
  final minY = contentFitsY
      ? bounds.bottom - viewHeight - padding
      : bounds.top - padding;
  final maxY = contentFitsY
      ? bounds.top + padding
      : bounds.bottom - viewHeight + padding;
  final offset = Offset(
    viewport.offset.dx.clamp(minX, maxX).toDouble(),
    viewport.offset.dy.clamp(minY, maxY).toDouble(),
  );
  if ((offset - viewport.offset).distance < 0.001) return viewport;
  return ViewportState(offset: offset, zoom: viewport.zoom);
}
