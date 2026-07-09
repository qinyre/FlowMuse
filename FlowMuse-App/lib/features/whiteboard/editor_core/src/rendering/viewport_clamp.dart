import 'dart:math' as math;
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

  // Clamp zoom so the viewport never shrinks smaller than the content —
  // the screen is always fully filled by PDF, zero blank space.
  final minZoomX = canvasSize.width / bounds.size.width;
  final minZoomY = canvasSize.height / bounds.size.height;
  final minZoom = math.max(minZoomX, minZoomY);
  final zoom = viewport.zoom.clamp(minZoom, double.infinity).toDouble();

  final viewWidth = canvasSize.width / zoom;
  final viewHeight = canvasSize.height / zoom;
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
  final offsetChanged = (offset - viewport.offset).distance >= 0.001;
  final zoomChanged = zoom != viewport.zoom;
  if (!offsetChanged && !zoomChanged) return viewport;
  return ViewportState(offset: offset, zoom: zoom);
}
