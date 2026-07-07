import 'dart:math' as math;
import 'dart:ui';

import '../core/math/math.dart';

/// An immutable value object representing viewport pan and zoom state.
///
/// Used by [StaticCanvasPainter] to apply canvas transforms. Provides
/// coordinate transforms, pan, zoom-at-point, and fit-to-content.
class ViewportState {
  final Offset offset;
  final double zoom;

  const ViewportState({this.offset = Offset.zero, this.zoom = 1.0});

  /// Returns the visible scene rectangle for the given canvas [size].
  ///
  /// The visible rect is the inverse of the viewport transform: it maps
  /// the canvas pixel area back to scene coordinates.
  Rect visibleRect(Size size) {
    return Rect.fromLTWH(
      offset.dx,
      offset.dy,
      size.width / zoom,
      size.height / zoom,
    );
  }

  /// Converts a screen-space pixel position to scene coordinates.
  ///
  /// Results are rounded to whole numbers to avoid subpixel fractional
  /// coordinates flowing into element positions and the serialization format.
  Offset screenToScene(Offset screenPoint) {
    return Offset(
      (screenPoint.dx / zoom + offset.dx).roundToDouble(),
      (screenPoint.dy / zoom + offset.dy).roundToDouble(),
    );
  }

  /// Converts a scene coordinate to screen-space pixel position.
  Offset sceneToScreen(Offset scenePoint) {
    return Offset(
      (scenePoint.dx - offset.dx) * zoom,
      (scenePoint.dy - offset.dy) * zoom,
    );
  }

  /// Returns a new [ViewportState] panned by a screen-space [delta].
  ///
  /// Positive delta moves the viewport in that screen direction (content
  /// appears to move with the drag).
  ViewportState pan(Offset screenDelta) {
    return ViewportState(
      offset: Offset(
        offset.dx - screenDelta.dx / zoom,
        offset.dy - screenDelta.dy / zoom,
      ),
      zoom: zoom,
    );
  }

  /// Returns a new [ViewportState] zoomed by [factor] anchored at
  /// [screenPoint], so the scene point under that screen position stays fixed.
  ///
  /// The resulting zoom is clamped to [[minZoom], [maxZoom]].
  ViewportState zoomAt(
    double factor,
    Offset screenPoint, {
    double minZoom = 0.1,
    double maxZoom = 30.0,
  }) {
    final newZoom = (zoom * factor).clamp(minZoom, maxZoom);

    // Scene point under the anchor before zoom
    final sceneX = screenPoint.dx / zoom + offset.dx;
    final sceneY = screenPoint.dy / zoom + offset.dy;

    // Adjust offset so the same scene point stays under the anchor
    return ViewportState(
      offset: Offset(
        sceneX - screenPoint.dx / newZoom,
        sceneY - screenPoint.dy / newZoom,
      ),
      zoom: newZoom,
    );
  }

  /// Returns a new [ViewportState] that fits the given scene [bounds] within
  /// the canvas [size], with optional [padding] in screen pixels.
  ///
  /// Returns a default state if [bounds] is null or [size] is zero.
  ViewportState fitToBounds(Bounds? bounds, Size size, {double padding = 0}) {
    if (bounds == null || size.width <= 0 || size.height <= 0) {
      return const ViewportState();
    }

    final availableWidth = math.max(0.0, size.width - padding * 2);
    final availableHeight = math.max(0.0, size.height - padding * 2);

    double newZoom;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) {
      // Zero-size bounds (point element) — keep zoom at 1.0
      newZoom = 1.0;
    } else {
      newZoom = math.min(
        availableWidth / bounds.size.width,
        availableHeight / bounds.size.height,
      );
    }

    // Center the content
    final contentCenterX = bounds.left + bounds.size.width / 2;
    final contentCenterY = bounds.top + bounds.size.height / 2;

    return ViewportState(
      offset: Offset(
        contentCenterX - size.width / 2 / newZoom,
        contentCenterY - size.height / 2 / newZoom,
      ),
      zoom: newZoom,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewportState && offset == other.offset && zoom == other.zoom;

  @override
  int get hashCode => Object.hash(offset, zoom);
}
