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
  @Deprecated('Use flow-aware progress/atEnd instead.')
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
  final visibleWidth = canvasSize.width / zoom;
  final visibleHeight = canvasSize.height / zoom;

  late final ViewportState nextViewport;
  late final double progress;
  late final bool atStart;
  late final bool atEnd;
  var maxScrollOffsetY = 0.0;

  switch (layout.pageFlow) {
    case CanvasPageFlow.topToBottom:
      final minY = firstPage.bounds.top;
      final maxY = math.max(minY, lastPage.bounds.bottom - visibleHeight);
      final clampedY = viewport.offset.dy.clamp(minY, maxY).toDouble();
      final currentPage = _nearestPageToViewportCenter(
        pages,
        clampedY + visibleHeight / 2,
      );
      final centeredX = currentPage.bounds.center.dx - visibleWidth / 2;
      final scrollRange = math.max(0.0, maxY - minY);
      progress = scrollRange == 0
          ? 0.0
          : ((clampedY - minY) / scrollRange).clamp(0.0, 1.0).toDouble();
      atStart = (clampedY - minY).abs() < 0.5;
      atEnd = (clampedY - maxY).abs() < 0.5;
      maxScrollOffsetY = maxY;
      nextViewport = ViewportState(
        offset: Offset(centeredX, clampedY),
        zoom: viewport.zoom,
      );
    case CanvasPageFlow.rightToLeft:
      final startX = _rightToLeftPageOffset(firstPage, visibleWidth, true);
      final endX = _rightToLeftPageOffset(lastPage, visibleWidth, false);
      final minX = math.min(startX, endX);
      final maxX = math.max(startX, endX);
      final clampedX = viewport.offset.dx.clamp(minX, maxX).toDouble();
      final currentPage = _nearestPageToViewportCenter(
        pages,
        clampedX + visibleWidth / 2,
      );
      final centeredY = currentPage.bounds.center.dy - visibleHeight / 2;
      final scrollRange = math.max(0.0, startX - endX);
      progress = scrollRange == 0
          ? 0.0
          : ((startX - clampedX) / scrollRange).clamp(0.0, 1.0).toDouble();
      atStart = (clampedX - startX).abs() < 0.5;
      atEnd = (clampedX - endX).abs() < 0.5;
      nextViewport = ViewportState(
        offset: Offset(clampedX, centeredY),
        zoom: viewport.zoom,
      );
  }

  return PagedViewportMetrics(
    viewport: nextViewport,
    progress: progress,
    currentPageIndex: _nearestPageToViewportCenter(
      pages,
      layout.isRightToLeft
          ? nextViewport.offset.dx + visibleWidth / 2
          : nextViewport.offset.dy + visibleHeight / 2,
    ).index,
    maxScrollOffsetY: maxScrollOffsetY,
    atStart: atStart,
    atEnd: atEnd,
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
  double viewportCenter,
) {
  var nearest = pages.first;
  final firstCenter = nearest.pageFlow == CanvasPageFlow.rightToLeft
      ? nearest.bounds.center.dx
      : nearest.bounds.center.dy;
  var nearestDistance = (firstCenter - viewportCenter).abs();
  for (final page in pages.skip(1)) {
    final pageCenter = page.pageFlow == CanvasPageFlow.rightToLeft
        ? page.bounds.center.dx
        : page.bounds.center.dy;
    final distance = (pageCenter - viewportCenter).abs();
    if (distance < nearestDistance) {
      nearest = page;
      nearestDistance = distance;
    }
  }
  return nearest;
}

double _rightToLeftPageOffset(
  CanvasPage page,
  double visibleWidth,
  bool startPage,
) {
  if (visibleWidth >= page.bounds.width) {
    return page.bounds.center.dx - visibleWidth / 2;
  }
  return startPage ? page.bounds.right - visibleWidth : page.bounds.left;
}
