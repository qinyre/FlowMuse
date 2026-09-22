import 'dart:ui';

import '../core/layout/canvas_layout.dart';
import 'viewport_state.dart';

/// Local view state. Never serialized into the shared scene or undo history.
class PageReadingPosition {
  const PageReadingPosition({
    required this.pageId,
    required this.ordinal,
    required this.zoom,
    required this.anchor,
    required this.screenAnchor,
  });

  final String pageId;
  final int ordinal;
  final double zoom;
  final Offset anchor;
  final Offset screenAnchor;

  static PageReadingPosition? capture(
    CanvasLayout layout,
    ViewportState viewport,
    Size size,
  ) {
    if (!layout.isPaged ||
        size.isEmpty ||
        !viewport.zoom.isFinite ||
        viewport.zoom <= 0) {
      return null;
    }
    final visible = viewport.visibleRect(size);
    final page = layout.pageForVisibleRect(visible);
    if (page == null) return null;
    final overlap = page.bounds.intersect(visible);
    final point = overlap.isEmpty ? page.bounds.center : overlap.center;
    final screen = viewport.sceneToScreen(point);
    return PageReadingPosition(
      pageId: page.id,
      ordinal: layout.pages.indexOf(page),
      zoom: viewport.zoom,
      anchor: Offset(
        ((point.dx - page.bounds.left) / page.bounds.width).clamp(0, 1),
        ((point.dy - page.bounds.top) / page.bounds.height).clamp(0, 1),
      ),
      screenAnchor: Offset(
        (screen.dx / size.width).clamp(0, 1),
        (screen.dy / size.height).clamp(0, 1),
      ),
    );
  }

  ViewportState? restore(CanvasLayout layout, Size size) {
    if (!layout.isPaged || layout.pages.isEmpty || size.isEmpty) return null;
    final matching = layout.pages.where((page) => page.id == pageId);
    final page = matching.isEmpty
        ? layout.pages[ordinal.clamp(0, layout.pages.length - 1)]
        : matching.first;
    return ViewportState(
      zoom: zoom,
      offset: Offset(
        page.bounds.left +
            anchor.dx * page.bounds.width -
            screenAnchor.dx * size.width / zoom,
        page.bounds.top +
            anchor.dy * page.bounds.height -
            screenAnchor.dy * size.height / zoom,
      ),
    );
  }

  Map<String, Object> toJson() => {
    'pageId': pageId,
    'ordinal': ordinal,
    'zoom': zoom,
    'x': anchor.dx,
    'y': anchor.dy,
    'screenX': screenAnchor.dx,
    'screenY': screenAnchor.dy,
  };

  static PageReadingPosition? fromJson(Object? value) {
    if (value is! Map ||
        value['pageId'] is! String ||
        (value['pageId'] as String).isEmpty ||
        value['ordinal'] is! int ||
        (value['ordinal'] as int) < 0) {
      return null;
    }
    for (final key in ['zoom', 'x', 'y', 'screenX', 'screenY']) {
      final number = value[key];
      if (number is! num || !number.isFinite) return null;
      if (key == 'zoom'
          ? number < 0.1 || number > 30
          : number < 0 || number > 1) {
        return null;
      }
    }
    return PageReadingPosition(
      pageId: value['pageId'] as String,
      ordinal: value['ordinal'] as int,
      zoom: (value['zoom'] as num).toDouble(),
      anchor: Offset(
        (value['x'] as num).toDouble(),
        (value['y'] as num).toDouble(),
      ),
      screenAnchor: Offset(
        (value['screenX'] as num).toDouble(),
        (value['screenY'] as num).toDouble(),
      ),
    );
  }
}
