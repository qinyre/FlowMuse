import 'package:flutter/widgets.dart';

import '../elements/elements.dart' as flow;

enum CanvasLayoutType { paged, unbounded }

enum CanvasPageFlow { topToBottom, rightToLeft }

enum CanvasPageTemplate {
  blank,
  narrowLine,
  wideLine,
  grid,
  dotGrid,
  tianGrid,
  miGrid,
  narrowVerticalLine,
  wideVerticalLine,
  fourLineGrid,
  ancientBook,
}

class CanvasPage {
  const CanvasPage({
    required this.id,
    required this.index,
    required this.bounds,
    required this.template,
    this.pageFlow = CanvasPageFlow.topToBottom,
    this.source = 'blank',
  });

  final String id;
  final int index;
  final Rect bounds;
  final CanvasPageTemplate template;
  final CanvasPageFlow pageFlow;
  final String source;
}

class CanvasLayout {
  const CanvasLayout({
    required this.type,
    this.template = CanvasPageTemplate.blank,
    this.pageFlow = CanvasPageFlow.topToBottom,
    this.pages = const [],
  });

  static const pageWidth = 1588.0;
  static const pageHeight = 2246.0;
  static const landscapePageWidth = pageHeight;
  static const landscapePageHeight = pageWidth;
  static const pageGap = 96.0;

  final CanvasLayoutType type;
  final CanvasPageTemplate template;
  final CanvasPageFlow pageFlow;
  final List<CanvasPage> pages;

  bool get isPaged => type == CanvasLayoutType.paged;
  bool get isRightToLeft => pageFlow == CanvasPageFlow.rightToLeft;

  static Size pageSizeForTemplate(CanvasPageTemplate template) {
    return switch (template) {
      CanvasPageTemplate.ancientBook => const Size(
        landscapePageWidth,
        landscapePageHeight,
      ),
      _ => const Size(pageWidth, pageHeight),
    };
  }

  static Rect pageBoundsForIndex({
    required int index,
    required Size pageSize,
    required CanvasPageFlow pageFlow,
  }) {
    return switch (pageFlow) {
      CanvasPageFlow.topToBottom => Rect.fromLTWH(
        0,
        index * (pageSize.height + pageGap),
        pageSize.width,
        pageSize.height,
      ),
      CanvasPageFlow.rightToLeft => Rect.fromLTWH(
        -index * (pageSize.width + pageGap),
        0,
        pageSize.width,
        pageSize.height,
      ),
    };
  }

  CanvasLayout ensurePage() {
    if (!isPaged || pages.isNotEmpty) {
      return this;
    }
    final pageSize = pageSizeForTemplate(template);
    return copyWith(
      pages: [
        CanvasPage(
          id: 'page-1',
          index: 0,
          bounds: pageBoundsForIndex(
            index: 0,
            pageSize: pageSize,
            pageFlow: pageFlow,
          ),
          template: template,
          pageFlow: pageFlow,
        ),
      ],
    );
  }

  CanvasPage? pageAt(Offset point) {
    for (final page in pages) {
      if (page.bounds.contains(point)) {
        return page;
      }
    }
    return pages.isEmpty ? null : pages.first;
  }

  /// Largest visible area; gaps fall back to the nearest page in reading order.
  CanvasPage? pageForVisibleRect(Rect visible) {
    CanvasPage? best;
    CanvasPage? nearest;
    var bestArea = 0.0;
    var nearestDistance = double.infinity;
    for (final page in pages) {
      final intersection = page.bounds.intersect(visible);
      final area = intersection.isEmpty
          ? 0.0
          : intersection.width * intersection.height;
      if (area > bestArea) {
        bestArea = area;
        best = page;
      }
      final dx = visible.right < page.bounds.left
          ? page.bounds.left - visible.right
          : (page.bounds.right < visible.left
                ? visible.left - page.bounds.right
                : 0.0);
      final dy = visible.bottom < page.bounds.top
          ? page.bounds.top - visible.bottom
          : (page.bounds.bottom < visible.top
                ? visible.top - page.bounds.bottom
                : 0.0);
      final distance = dx * dx + dy * dy;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = page;
      }
    }
    return best ?? nearest;
  }

  CanvasLayout copyWith({
    CanvasLayoutType? type,
    CanvasPageTemplate? template,
    CanvasPageFlow? pageFlow,
    List<CanvasPage>? pages,
  }) {
    return CanvasLayout(
      type: type ?? this.type,
      template: template ?? this.template,
      pageFlow: pageFlow ?? this.pageFlow,
      pages: pages ?? this.pages,
    );
  }

  static CanvasLayout fromScene(
    List<flow.Element> elements, {
    CanvasLayoutType fallbackType = CanvasLayoutType.unbounded,
    CanvasPageTemplate fallbackTemplate = CanvasPageTemplate.blank,
    CanvasPageFlow fallbackPageFlow = CanvasPageFlow.topToBottom,
  }) {
    final pages = <CanvasPage>[];
    final pageIds = <String>{};
    var pageFlow = fallbackPageFlow;
    for (final element in elements) {
      if (element.isDeleted ||
          !element.x.isFinite ||
          !element.y.isFinite ||
          !element.width.isFinite ||
          !element.height.isFinite ||
          element.width <= 0 ||
          element.height <= 0) {
        continue;
      }
      final flowMuse = flowMuseData(element.customData);
      if (flowMuse?['role'] != 'page') {
        continue;
      }
      pageFlow = _pageFlowFromName(flowMuse?['pageFlow']) ?? pageFlow;
      final rawId = flowMuse?['pageId'];
      final id = rawId is String && rawId.isNotEmpty ? rawId : element.id.value;
      if (!pageIds.add(id)) continue;
      final rawIndex = flowMuse?['pageIndex'];
      final index = rawIndex is num && rawIndex.isFinite && rawIndex >= 0
          ? rawIndex.toInt()
          : pages.length;
      pages.add(
        CanvasPage(
          id: id,
          index: index,
          bounds: Rect.fromLTWH(
            element.x,
            element.y,
            element.width,
            element.height,
          ),
          template:
              _templateFromName(flowMuse?['template']) ?? fallbackTemplate,
          pageFlow: pageFlow,
          source: flowMuse?['source'] is String
              ? flowMuse!['source']! as String
              : 'blank',
        ),
      );
    }
    // Older PDF notes can have reliable background metadata without page
    // markers. Derive navigation bounds without moving or rewriting content.
    if (pages.isEmpty && !elements.any((element) => element.isCanvasPage)) {
      final backgrounds = elements
          .whereType<flow.ImageElement>()
          .where(
            (element) =>
                !element.isDeleted &&
                element.isPdfBackground &&
                element.pageId != null &&
                element.x.isFinite &&
                element.y.isFinite &&
                element.width.isFinite &&
                element.height.isFinite &&
                element.width > 0 &&
                element.height > 0,
          )
          .toList();
      backgrounds.sort((a, b) {
        final order = fallbackPageFlow == CanvasPageFlow.rightToLeft
            ? b.x.compareTo(a.x)
            : a.y.compareTo(b.y);
        return order != 0 ? order : a.id.value.compareTo(b.id.value);
      });
      for (final element in backgrounds) {
        if (!pageIds.add(element.pageId!)) continue;
        pages.add(
          CanvasPage(
            id: element.pageId!,
            index: pages.length,
            bounds: Rect.fromLTWH(
              element.x,
              element.y,
              element.width,
              element.height,
            ),
            template: fallbackTemplate,
            pageFlow: fallbackPageFlow,
            source: 'pdf',
          ),
        );
      }
    }
    pages.sort((a, b) {
      final order = a.index.compareTo(b.index);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    if (pages.isNotEmpty) {
      return CanvasLayout(
        type: CanvasLayoutType.paged,
        template: fallbackTemplate,
        pageFlow: pageFlow,
        pages: pages,
      );
    }
    return CanvasLayout(
      type: fallbackType,
      template: fallbackTemplate,
      pageFlow: fallbackPageFlow,
    ).ensurePage();
  }

  static Map<String, Object?> pageCustomData(CanvasPage page) {
    return {
      'flowMuse': {
        'role': 'page',
        'pageId': page.id,
        'pageIndex': page.index,
        'template': page.template.name,
        'pageFlow': page.pageFlow.name,
        'source': page.source,
      },
    };
  }

  static Map<String, Object?> elementCustomData(String pageId) {
    return {
      'flowMuse': {'pageId': pageId},
    };
  }

  static Map<String, Object?> pdfBackgroundCustomData(String pageId) {
    return {
      'flowMuse': {'pageId': pageId, 'pdfBackground': true},
    };
  }

  static Map<String, Object?>? flowMuseData(Map<String, Object?>? customData) {
    final value = customData?['flowMuse'];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return null;
  }

  static CanvasPageTemplate? _templateFromName(Object? name) {
    if (name == null) {
      return null;
    }
    for (final template in CanvasPageTemplate.values) {
      if (template.name == name) {
        return template;
      }
    }
    return null;
  }

  static CanvasPageFlow? _pageFlowFromName(Object? name) {
    if (name == null) {
      return null;
    }
    for (final pageFlow in CanvasPageFlow.values) {
      if (pageFlow.name == name) {
        return pageFlow;
      }
    }
    return null;
  }
}

extension FlowMuseElementData on flow.Element {
  Map<String, Object?>? get flowMuseData =>
      CanvasLayout.flowMuseData(customData);
  String? get pageId {
    final value = flowMuseData?['pageId'];
    return value is String && value.isNotEmpty ? value : null;
  }

  bool get isCanvasPage => flowMuseData?['role'] == 'page';
  bool get isPdfBackground => flowMuseData?['pdfBackground'] == true;
}
