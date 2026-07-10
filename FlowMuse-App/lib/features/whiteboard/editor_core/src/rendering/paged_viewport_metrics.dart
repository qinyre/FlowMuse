import 'dart:math' as math;
import 'dart:ui';

import '../core/layout/layout.dart';
import 'viewport_state.dart';

class PagedViewportMetrics {
  const PagedViewportMetrics({
    required this.viewport,
    required this.progress,
    required this.currentPageIndex,
    required this.maxScrollOffsetY,
    required this.atStart,
    required this.atEnd,
  });

  final ViewportState viewport;
  final double progress;
  final int currentPageIndex;
  final double maxScrollOffsetY;
  final bool atStart;
  final bool atEnd;
}

PagedViewportMetrics? computePagedViewportMetrics({
  required CanvasLayout layout,
  required ViewportState viewport,
  required Size canvasSize,
}) {
  if (!layout.isPaged || layout.pages.isEmpty || canvasSize.isEmpty) {
    return null;
  }

  final pages = layout.pages;
  final firstPage = pages.first;
  final lastPage = pages.last;
  final zoom = math.max(viewport.zoom, 0.0001);
  final visibleHeight = canvasSize.height / zoom;
  final minY = firstPage.bounds.top;
  final maxY = math.max(minY, lastPage.bounds.bottom - visibleHeight);
  final clampedY = viewport.offset.dy.clamp(minY, maxY).toDouble();
  final currentPage = _nearestPageToViewportCenter(
    pages,
    clampedY + visibleHeight / 2,
  );
  final centeredX =
      currentPage.bounds.center.dx - canvasSize.width / (2 * zoom);
  final nextViewport = ViewportState(
    offset: Offset(centeredX, clampedY),
    zoom: viewport.zoom,
  );
  final scrollRange = math.max(0.0, maxY - minY);
  final progress = scrollRange == 0
      ? 0.0
      : ((clampedY - minY) / scrollRange).clamp(0.0, 1.0).toDouble();

  return PagedViewportMetrics(
    viewport: nextViewport,
    progress: progress,
    currentPageIndex: currentPage.index,
    maxScrollOffsetY: maxY,
    atStart: (clampedY - minY).abs() < 0.5,
    atEnd: (clampedY - maxY).abs() < 0.5,
  );
}

ViewportState clampPagedViewport({
  required CanvasLayout layout,
  required ViewportState viewport,
  required Size canvasSize,
}) {
  return computePagedViewportMetrics(
        layout: layout,
        viewport: viewport,
        canvasSize: canvasSize,
      )?.viewport ??
      viewport;
}

double pagedViewportProgress({
  required CanvasLayout layout,
  required ViewportState viewport,
  required Size canvasSize,
}) {
  return computePagedViewportMetrics(
        layout: layout,
        viewport: viewport,
        canvasSize: canvasSize,
      )?.progress ??
      0.0;
}

CanvasPage _nearestPageToViewportCenter(
  List<CanvasPage> pages,
  double viewportCenterY,
) {
  var nearest = pages.first;
  var nearestDistance = (nearest.bounds.center.dy - viewportCenterY).abs();
  for (final page in pages.skip(1)) {
    final distance = (page.bounds.center.dy - viewportCenterY).abs();
    if (distance < nearestDistance) {
      nearest = page;
      nearestDistance = distance;
    }
  }
  return nearest;
}
