import 'package:flutter/widgets.dart';

import '../elements/elements.dart' as flow;

enum CanvasLayoutType { paged, unbounded }

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
    this.source = 'blank',
  });

  final String id;
  final int index;
  final Rect bounds;
  final CanvasPageTemplate template;
  final String source;
}

class CanvasLayout {
  const CanvasLayout({
    required this.type,
    this.template = CanvasPageTemplate.blank,
    this.pages = const [],
  });

  static const pageWidth = 794.0;
  static const pageHeight = 1123.0;
  static const pageGap = 48.0;

  final CanvasLayoutType type;
  final CanvasPageTemplate template;
  final List<CanvasPage> pages;

  bool get isPaged => type == CanvasLayoutType.paged;

  CanvasLayout ensurePage() {
    if (!isPaged || pages.isNotEmpty) {
      return this;
    }
    return copyWith(
      pages: [
        CanvasPage(
          id: 'page-1',
          index: 0,
          bounds: const Rect.fromLTWH(0, 0, pageWidth, pageHeight),
          template: template,
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

  CanvasLayout copyWith({
    CanvasLayoutType? type,
    CanvasPageTemplate? template,
    List<CanvasPage>? pages,
  }) {
    return CanvasLayout(
      type: type ?? this.type,
      template: template ?? this.template,
      pages: pages ?? this.pages,
    );
  }

  static CanvasLayout fromScene(
    List<flow.Element> elements, {
    CanvasLayoutType fallbackType = CanvasLayoutType.unbounded,
    CanvasPageTemplate fallbackTemplate = CanvasPageTemplate.blank,
  }) {
    final pages = <CanvasPage>[];
    for (final element in elements) {
      final flowMuse = flowMuseData(element.customData);
      if (flowMuse?['role'] != 'page') {
        continue;
      }
      final id = flowMuse?['pageId'] as String? ?? element.id.value;
      final index = (flowMuse?['pageIndex'] as num?)?.toInt() ?? pages.length;
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
              _templateFromName(flowMuse?['template'] as String?) ??
              fallbackTemplate,
          source: flowMuse?['source'] as String? ?? 'blank',
        ),
      );
    }
    pages.sort((a, b) => a.index.compareTo(b.index));
    if (pages.isNotEmpty) {
      return CanvasLayout(
        type: CanvasLayoutType.paged,
        template: fallbackTemplate,
        pages: pages,
      );
    }
    return CanvasLayout(
      type: fallbackType,
      template: fallbackTemplate,
    ).ensurePage();
  }

  static Map<String, Object?> pageCustomData(CanvasPage page) {
    return {
      'flowMuse': {
        'role': 'page',
        'pageId': page.id,
        'pageIndex': page.index,
        'template': page.template.name,
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

  static CanvasPageTemplate? _templateFromName(String? name) {
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
}

extension FlowMuseElementData on flow.Element {
  Map<String, Object?>? get flowMuseData =>
      CanvasLayout.flowMuseData(customData);
  String? get pageId => flowMuseData?['pageId'] as String?;
  bool get isCanvasPage => flowMuseData?['role'] == 'page';
  bool get isPdfBackground => flowMuseData?['pdfBackground'] == true;
}
