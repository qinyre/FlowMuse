import 'dart:ui';

import '../core/elements/elements.dart' as core show TextElement;
import '../core/elements/elements.dart' hide TextElement;
import '../core/math/math.dart';
import 'viewport_state.dart';

/// Filters [elements] to those whose bounding box intersects the visible
/// viewport area (expanded by [margin] in scene units).
///
/// Deleted elements and bound text (containerId != null) are excluded.
List<Element> cullElements(
  List<Element> elements,
  ViewportState viewport,
  Size canvasSize, {
  double margin = 50.0,
}) {
  final visibleRect = viewport.visibleRect(canvasSize);
  final marginInScene = margin / viewport.zoom;
  final expanded = Bounds.fromLTWH(
    visibleRect.left - marginInScene,
    visibleRect.top - marginInScene,
    visibleRect.width + marginInScene * 2,
    visibleRect.height + marginInScene * 2,
  );

  return elements.where((e) {
    if (e.isDeleted) return false;
    if (e is core.TextElement && e.containerId != null) return false;

    final elementBounds = Bounds.fromLTWH(e.x, e.y, e.width, e.height);
    return expanded.intersects(elementBounds);
  }).toList();
}
