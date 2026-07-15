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

  static const pageTemplateMargin = 96.0;
  static const ancientBookGutterWidth = 112.0;
  static const ancientBookColumnWidth = 88.0;
  static const practiceCell = 112.0;
  static const practiceGap = 16.0;

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
          ? (center.dx - anchor.crossAxis).abs()
          : (center.dy - anchor.crossAxis).abs();
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

  static const double fontSizeToLineHeightRatio = 0.7;

  static TemplateGeometry resolve(CanvasPage page) {
    final rect = page.bounds.deflate(TemplateGeometry.pageTemplateMargin);
    return switch (page.template) {
      CanvasPageTemplate.blank => _blank(page, rect),
      CanvasPageTemplate.narrowLine => _horizontalLines(page, rect, 72, 96),
      CanvasPageTemplate.wideLine => _horizontalLines(page, rect, 96, 144),
      CanvasPageTemplate.grid => _horizontalLines(page, rect, 32, 64),
      CanvasPageTemplate.dotGrid => _horizontalLines(page, rect, 32, 64),
      CanvasPageTemplate.tianGrid => _practiceGrid(page, rect),
      CanvasPageTemplate.miGrid => _practiceGrid(page, rect),
      CanvasPageTemplate.narrowVerticalLine => _verticalLines(
        page,
        rect,
        72,
        96,
      ),
      CanvasPageTemplate.wideVerticalLine => _verticalLines(
        page,
        rect,
        96,
        144,
      ),
      CanvasPageTemplate.fourLineGrid => _fourLineGrid(page, rect),
      CanvasPageTemplate.ancientBook => _ancientBook(page, rect),
    };
  }

  static TemplateGeometry _blank(CanvasPage page, Rect rect) {
    const lineHeight = 56.0;
    return TemplateGeometry(
      contentRect: rect,
      anchors: [
        TemplateAnchor(
          position: rect.topLeft,
          crossAxis: rect.top,
          mainAxis: rect.left,
          fontSize: lineHeight * fontSizeToLineHeightRatio,
          lineHeight: lineHeight,
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
      final fontSize = step * fontSizeToLineHeightRatio;
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, y - fontSize),
          crossAxis: y,
          mainAxis: rect.left,
          fontSize: fontSize,
          lineHeight: step,
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
    const lineHeight = TemplateGeometry.practiceCell;
    for (
      var top = rect.top;
      top + TemplateGeometry.practiceCell <= rect.bottom;
      top += TemplateGeometry.practiceCell + TemplateGeometry.practiceGap
    ) {
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, top + 8),
          crossAxis: top + TemplateGeometry.practiceCell / 2,
          mainAxis: rect.left,
          fontSize: lineHeight * fontSizeToLineHeightRatio,
          lineHeight: lineHeight,
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
    const lineHeight = 96.0;
    for (var y = rect.top + 72; y + 96 < rect.bottom; y += 224) {
      anchors.add(
        TemplateAnchor(
          position: Offset(rect.left, y),
          crossAxis: y + 48,
          mainAxis: rect.left,
          fontSize: lineHeight * fontSizeToLineHeightRatio,
          lineHeight: lineHeight,
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
    for (var x = rect.left + start; x < rect.right; x += step) {
      final fontSize = step * fontSizeToLineHeightRatio;
      anchors.add(
        TemplateAnchor(
          position: Offset(x - fontSize, rect.top),
          crossAxis: x,
          mainAxis: rect.top,
          fontSize: fontSize,
          lineHeight: step,
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
      const lineHeight = TemplateGeometry.ancientBookColumnWidth;
      const fontSize = lineHeight * fontSizeToLineHeightRatio;
      for (
        var x = area.right - TemplateGeometry.ancientBookColumnWidth / 2;
        x > area.left;
        x -= TemplateGeometry.ancientBookColumnWidth
      ) {
        anchors.add(
          TemplateAnchor(
            position: Offset(x - fontSize / 2, area.top + 24),
            crossAxis: x,
            mainAxis: area.top,
            fontSize: fontSize,
            lineHeight: lineHeight,
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
