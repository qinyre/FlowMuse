import 'package:flutter/widgets.dart';

import 'canvas_layout.dart';

enum TemplateWritingMode { horizontal, vertical }

class TemplateAnchor {
  const TemplateAnchor({
    required this.position,
    required this.crossAxis,
    required this.mainAxis,
    required this.fontSize,
    required this.lineHeight,
    required this.writingMode,
    required this.pageId,
  });

  final Offset position;
  final double crossAxis;
  final double mainAxis;
  final double fontSize;
  final double lineHeight;
  final TemplateWritingMode writingMode;
  final String pageId;
}

class TemplateGeometry {
  const TemplateGeometry({
    required this.contentRect,
    required this.anchors,
    required this.writingMode,
  });

  static const pageTemplateMargin = 48.0;
  static const ancientBookGutterWidth = 56.0;
  static const ancientBookColumnWidth = 44.0;
  static const practiceCell = 56.0;
  static const practiceGap = 8.0;

  final Rect contentRect;
  final List<TemplateAnchor> anchors;
  final TemplateWritingMode writingMode;

  TemplateAnchor? nearestAnchor(Rect bounds) {
    if (anchors.isEmpty) return null;
    final center = bounds.center;
    TemplateAnchor? best;
    var bestDistance = double.infinity;
    for (final anchor in anchors) {
      final distance = writingMode == TemplateWritingMode.vertical
          ? (center.dx - anchor.position.dx).abs()
          : (center.dy - anchor.position.dy).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = anchor;
      }
    }
    return best;
  }
}

class TemplateAnchorResolver {
  const TemplateAnchorResolver._();

  static TemplateGeometry resolve(CanvasPage page) {
    final rect = page.bounds.deflate(TemplateGeometry.pageTemplateMargin);
    return switch (page.template) {
      CanvasPageTemplate.blank => _blank(page, rect),
      CanvasPageTemplate.narrowLine => _horizontalLines(page, rect, 18, 24),
      CanvasPageTemplate.wideLine => _horizontalLines(page, rect, 24, 36),
      CanvasPageTemplate.grid => _horizontalLines(page, rect, 16, 32),
      CanvasPageTemplate.dotGrid => _horizontalLines(page, rect, 16, 32),
      CanvasPageTemplate.tianGrid => _practiceGrid(page, rect),
      CanvasPageTemplate.miGrid => _practiceGrid(page, rect),
      CanvasPageTemplate.narrowVerticalLine => _verticalLines(
        page,
        rect,
        18,
        24,
      ),
      CanvasPageTemplate.wideVerticalLine => _verticalLines(page, rect, 24, 36),
      CanvasPageTemplate.fourLineGrid => _fourLineGrid(page, rect),
      CanvasPageTemplate.ancientBook => _ancientBook(page, rect),
    };
  }

  static TemplateGeometry _blank(CanvasPage page, Rect rect) {
    return TemplateGeometry(
      contentRect: rect,
      anchors: [
        TemplateAnchor(
          position: rect.topLeft,
          crossAxis: rect.top,
          mainAxis: rect.left,
          fontSize: 20,
          lineHeight: 1.25,
          writingMode: TemplateWritingMode.horizontal,
          pageId: page.id,
        ),
      ],
      writingMode: TemplateWritingMode.horizontal,
    );
  }

  static TemplateGeometry _horizontalLines(
    CanvasPage page,
    Rect rect,
    double start,
    double step,
  ) {
    final anchors = <TemplateAnchor>[];
    for (var y = rect.top + start; y < rect.bottom; y += step) {
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, y - step * 0.72),
          crossAxis: y,
          mainAxis: rect.left,
          fontSize: (step * 0.62).clamp(14.0, 24.0),
          lineHeight: 1.2,
          writingMode: TemplateWritingMode.horizontal,
          pageId: page.id,
        ),
      );
    }
    return TemplateGeometry(
      contentRect: rect,
      anchors: anchors,
      writingMode: TemplateWritingMode.horizontal,
    );
  }

  static TemplateGeometry _practiceGrid(CanvasPage page, Rect rect) {
    final anchors = <TemplateAnchor>[];
    for (
      var top = rect.top;
      top + TemplateGeometry.practiceCell <= rect.bottom;
      top += TemplateGeometry.practiceCell + TemplateGeometry.practiceGap
    ) {
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, top + 4),
          crossAxis: top + TemplateGeometry.practiceCell / 2,
          mainAxis: rect.left,
          fontSize: 34,
          lineHeight: 1.1,
          writingMode: TemplateWritingMode.horizontal,
          pageId: page.id,
        ),
      );
    }
    return TemplateGeometry(
      contentRect: rect,
      anchors: anchors,
      writingMode: TemplateWritingMode.horizontal,
    );
  }

  static TemplateGeometry _fourLineGrid(CanvasPage page, Rect rect) {
    final anchors = <TemplateAnchor>[];
    for (var y = rect.top + 18; y + 24 < rect.bottom; y += 56) {
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, y - 4),
          crossAxis: y + 12,
          mainAxis: rect.left,
          fontSize: 22,
          lineHeight: 1.0,
          writingMode: TemplateWritingMode.horizontal,
          pageId: page.id,
        ),
      );
    }
    return TemplateGeometry(
      contentRect: rect,
      anchors: anchors,
      writingMode: TemplateWritingMode.horizontal,
    );
  }

  static TemplateGeometry _verticalLines(
    CanvasPage page,
    Rect rect,
    double start,
    double step,
  ) {
    final anchors = <TemplateAnchor>[];
    for (var x = rect.right - start; x > rect.left; x -= step) {
      anchors.add(
        TemplateAnchor(
          position: Offset(x - step * 0.52, rect.top),
          crossAxis: x,
          mainAxis: rect.top,
          fontSize: (step * 0.62).clamp(14.0, 24.0),
          lineHeight: 1.15,
          writingMode: TemplateWritingMode.vertical,
          pageId: page.id,
        ),
      );
    }
    return TemplateGeometry(
      contentRect: rect,
      anchors: anchors,
      writingMode: TemplateWritingMode.vertical,
    );
  }

  static TemplateGeometry _ancientBook(CanvasPage page, Rect rect) {
    final centerX = rect.center.dx;
    final gutterLeft = centerX - TemplateGeometry.ancientBookGutterWidth / 2;
    final gutterRight = centerX + TemplateGeometry.ancientBookGutterWidth / 2;
    final anchors = <TemplateAnchor>[];
    void addColumns(Rect area) {
      for (
        var x = area.right - TemplateGeometry.ancientBookColumnWidth / 2;
        x > area.left;
        x -= TemplateGeometry.ancientBookColumnWidth
      ) {
        anchors.add(
          TemplateAnchor(
            position: Offset(x - 12, area.top + 12),
            crossAxis: x,
            mainAxis: area.top,
            fontSize: 22,
            lineHeight: 1.12,
            writingMode: TemplateWritingMode.vertical,
            pageId: page.id,
          ),
        );
      }
    }

    addColumns(Rect.fromLTRB(rect.left, rect.top, gutterLeft, rect.bottom));
    addColumns(Rect.fromLTRB(gutterRight, rect.top, rect.right, rect.bottom));
    return TemplateGeometry(
      contentRect: rect,
      anchors: anchors,
      writingMode: TemplateWritingMode.vertical,
    );
  }
}
