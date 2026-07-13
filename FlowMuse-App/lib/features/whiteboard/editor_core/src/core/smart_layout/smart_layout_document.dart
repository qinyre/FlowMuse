import '../elements/elements.dart';
import '../layout/layout.dart';
import '../math/math.dart';
import '../../recognition/ink_recognition.dart';

enum SmartLayoutExportFormat { markdown, latex }

class SmartLayoutDocument {
  const SmartLayoutDocument({
    required this.version,
    required this.blocks,
    required this.generatedAt,
  });

  final int version;
  final List<SmartLayoutBlock> blocks;
  final int generatedAt;

  bool get isEmpty => blocks.isEmpty;

  Map<String, Object?> toJson() => {
    'version': version,
    'generatedAt': generatedAt,
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };

  factory SmartLayoutDocument.fromJson(Map<String, Object?> json) {
    final rawBlocks = json['blocks'] as List<Object?>? ?? const [];
    return SmartLayoutDocument(
      version: (json['version'] as num?)?.toInt() ?? 1,
      generatedAt:
          (json['generatedAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      blocks: [
        for (final item in rawBlocks)
          if (item is Map)
            SmartLayoutBlock.fromJson(Map<String, Object?>.from(item)),
      ],
    );
  }
}

class SmartLayoutBlock {
  const SmartLayoutBlock({
    required this.id,
    required this.type,
    required this.text,
    this.latex,
    this.pageId,
    this.bounds,
    this.order = 0,
    this.writingMode = 'horizontal',
  });

  final String id;
  final String type;
  final String text;
  final String? latex;
  final String? pageId;
  final Bounds? bounds;
  final int order;
  final String writingMode;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'text': text,
    if (latex != null) 'latex': latex,
    if (pageId != null) 'pageId': pageId,
    if (bounds != null)
      'bounds': {
        'x': bounds!.left,
        'y': bounds!.top,
        'width': bounds!.size.width,
        'height': bounds!.size.height,
      },
    'order': order,
    'writingMode': writingMode,
  };

  factory SmartLayoutBlock.fromJson(Map<String, Object?> json) {
    final rawBounds = json['bounds'];
    Bounds? bounds;
    if (rawBounds is Map) {
      final map = Map<String, Object?>.from(rawBounds);
      bounds = Bounds.fromLTWH(
        (map['x'] as num?)?.toDouble() ?? 0,
        (map['y'] as num?)?.toDouble() ?? 0,
        (map['width'] as num?)?.toDouble() ?? 1,
        (map['height'] as num?)?.toDouble() ?? 1,
      );
    }
    return SmartLayoutBlock(
      id: json['id'] as String? ?? ElementId.generate().value,
      type: json['type'] as String? ?? 'paragraph',
      text: json['text'] as String? ?? '',
      latex: json['latex'] as String?,
      pageId: json['pageId'] as String?,
      bounds: bounds,
      order: (json['order'] as num?)?.toInt() ?? 0,
      writingMode: json['writingMode'] as String? ?? 'horizontal',
    );
  }
}

class SmartLayoutPageRequest {
  const SmartLayoutPageRequest({
    required this.id,
    required this.index,
    required this.bounds,
    required this.template,
    required this.anchors,
  });

  final String id;
  final int index;
  final Bounds bounds;
  final CanvasPageTemplate template;
  final List<Map<String, Object?>> anchors;

  Map<String, Object?> toJson() => {
    'id': id,
    'index': index,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.size.width,
      'height': bounds.size.height,
    },
    'template': template.name,
    'anchors': anchors,
  };
}

class SmartLayoutElementRequest {
  const SmartLayoutElementRequest({
    required this.id,
    required this.type,
    required this.bounds,
    this.text,
    this.points,
  });

  final String id;
  final String type;
  final Bounds bounds;
  final String? text;
  final List<InkRecognitionPoint>? points;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.size.width,
      'height': bounds.size.height,
    },
    if (text != null) 'text': text,
    if (points != null)
      'points': points!.map((point) => point.toJson()).toList(),
  };
}

class SmartLayoutRequest {
  const SmartLayoutRequest({
    required this.pages,
    required this.ink,
    required this.text,
    required this.context,
  });

  final List<SmartLayoutPageRequest> pages;
  final List<SmartLayoutElementRequest> ink;
  final List<SmartLayoutElementRequest> text;
  final List<SmartLayoutElementRequest> context;

  Map<String, Object?> toJson() => {
    'pages': pages.map((page) => page.toJson()).toList(),
    'ink': ink.map((element) => element.toJson()).toList(),
    'text': text.map((element) => element.toJson()).toList(),
    'context': context.map((element) => element.toJson()).toList(),
  };
}

class SmartLayoutResponse {
  const SmartLayoutResponse({required this.document});

  final SmartLayoutDocument document;

  factory SmartLayoutResponse.fromJson(Map<String, Object?> json) {
    final rawDocument = json['document'];
    return SmartLayoutResponse(
      document: rawDocument is Map
          ? SmartLayoutDocument.fromJson(Map<String, Object?>.from(rawDocument))
          : SmartLayoutDocument.fromJson(json),
    );
  }
}
