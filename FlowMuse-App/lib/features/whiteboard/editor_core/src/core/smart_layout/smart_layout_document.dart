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
    this.sourceIds = const [],
  });

  final String id;
  final String type;
  final String text;
  final String? latex;
  final String? pageId;
  final Bounds? bounds;
  final int order;
  final String writingMode;
  final List<String> sourceIds;

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
    if (sourceIds.isNotEmpty) 'sourceIds': sourceIds,
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
      sourceIds: [
        for (final item in json['sourceIds'] as List<Object?>? ?? const [])
          if (item is String) item,
      ],
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

class SmartLayoutInkBlockRequest {
  const SmartLayoutInkBlockRequest({
    required this.id,
    required this.bounds,
    required this.imageBase64,
    this.strokeBounds = const [],
    this.pageId,
    this.startedAt,
    this.imageMime = 'image/png',
  });

  final String id;
  final String? pageId;
  final Bounds bounds;
  final List<Bounds> strokeBounds;
  final int? startedAt;
  final String imageMime;
  final String imageBase64;

  Map<String, Object?> toJson() => {
    'id': id,
    if (pageId != null) 'pageId': pageId,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.size.width,
      'height': bounds.size.height,
    },
    if (strokeBounds.isNotEmpty)
      'strokeBounds': [
        for (final bounds in strokeBounds)
          {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.size.width,
            'height': bounds.size.height,
          },
      ],
    if (startedAt != null) 'startedAt': startedAt,
    'imageMime': imageMime,
    'imageBase64': imageBase64,
  };
}

class SmartLayoutRequest {
  const SmartLayoutRequest({required this.pages, required this.blocks});

  final List<SmartLayoutPageRequest> pages;
  final List<SmartLayoutInkBlockRequest> blocks;

  Map<String, Object?> toJson() => {
    'pages': pages.map((page) => page.toJson()).toList(),
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };
}

class SmartLayoutRecognizedBlock {
  const SmartLayoutRecognizedBlock({
    required this.id,
    required this.type,
    required this.bounds,
    this.pageId,
    this.text,
    this.latex,
    this.strokeBounds = const [],
    this.startedAt,
    this.error,
  });

  final String id;
  final String? pageId;
  final String type;
  final String? text;
  final String? latex;
  final Bounds bounds;
  final List<Bounds> strokeBounds;
  final int? startedAt;
  final String? error;

  bool get isSuccess => error == null || error!.isEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    if (pageId != null) 'pageId': pageId,
    'type': type,
    if (text != null) 'text': text,
    if (latex != null) 'latex': latex,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.size.width,
      'height': bounds.size.height,
    },
    if (strokeBounds.isNotEmpty)
      'strokeBounds': [
        for (final bounds in strokeBounds)
          {
            'x': bounds.left,
            'y': bounds.top,
            'width': bounds.size.width,
            'height': bounds.size.height,
          },
      ],
    if (startedAt != null) 'startedAt': startedAt,
    if (error != null && error!.isNotEmpty) 'error': error,
  };

  factory SmartLayoutRecognizedBlock.fromJson(Map<String, Object?> json) {
    final rawBounds = json['bounds'];
    final rawStrokeBounds = json['strokeBounds'] as List<Object?>? ?? const [];
    Bounds bounds = Bounds.fromLTWH(0, 0, 1, 1);
    if (rawBounds is Map) {
      final map = Map<String, Object?>.from(rawBounds);
      bounds = Bounds.fromLTWH(
        (map['x'] as num?)?.toDouble() ?? 0,
        (map['y'] as num?)?.toDouble() ?? 0,
        (map['width'] as num?)?.toDouble() ?? 1,
        (map['height'] as num?)?.toDouble() ?? 1,
      );
    }
    return SmartLayoutRecognizedBlock(
      id: json['id'] as String? ?? ElementId.generate().value,
      pageId: json['pageId'] as String?,
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String?,
      latex: json['latex'] as String?,
      bounds: bounds,
      strokeBounds: [
        for (final item in rawStrokeBounds)
          if (item is Map) _boundsFromJson(Map<String, Object?>.from(item)),
      ],
      startedAt: (json['startedAt'] as num?)?.toInt(),
      error: json['error'] as String?,
    );
  }

  static Bounds _boundsFromJson(Map<String, Object?> json) {
    return Bounds.fromLTWH(
      (json['x'] as num?)?.toDouble() ?? 0,
      (json['y'] as num?)?.toDouble() ?? 0,
      (json['width'] as num?)?.toDouble() ?? 1,
      (json['height'] as num?)?.toDouble() ?? 1,
    );
  }
}

class SmartLayoutComposeRequest {
  const SmartLayoutComposeRequest({required this.pages, required this.blocks});

  final List<SmartLayoutPageRequest> pages;
  final List<SmartLayoutRecognizedBlock> blocks;

  Map<String, Object?> toJson() => {
    'pages': pages.map((page) => page.toJson()).toList(),
    'blocks': blocks.map((block) => block.toJson()).toList(),
  };
}

class SmartLayoutPageDecision {
  const SmartLayoutPageDecision({
    required this.pageId,
    required this.mode,
    this.paragraphs = const [],
  });

  final String pageId;
  final String mode;
  final List<List<String>> paragraphs;

  bool get isArticle => mode == 'article';

  factory SmartLayoutPageDecision.fromJson(Map<String, Object?> json) {
    final rawParagraphs = json['paragraphs'] as List<Object?>? ?? const [];
    return SmartLayoutPageDecision(
      pageId: json['pageId'] as String? ?? '',
      mode: json['mode'] as String? ?? 'in_place',
      paragraphs: [
        for (final paragraph in rawParagraphs)
          if (paragraph is List)
            [
              for (final item in paragraph)
                if (item is String) item,
            ],
      ],
    );
  }
}

class SmartLayoutResponse {
  const SmartLayoutResponse({
    required this.document,
    this.blocks = const [],
    this.pages = const [],
  });

  final SmartLayoutDocument document;
  final List<SmartLayoutRecognizedBlock> blocks;
  final List<SmartLayoutPageDecision> pages;

  factory SmartLayoutResponse.fromJson(Map<String, Object?> json) {
    final rawDocument = json['document'];
    final rawBlocks = json['blocks'] as List<Object?>? ?? const [];
    final rawPages = json['pages'] as List<Object?>? ?? const [];
    return SmartLayoutResponse(
      document: rawDocument is Map
          ? SmartLayoutDocument.fromJson(Map<String, Object?>.from(rawDocument))
          : SmartLayoutDocument.fromJson(json),
      blocks: [
        for (final item in rawBlocks)
          if (item is Map)
            SmartLayoutRecognizedBlock.fromJson(
              Map<String, Object?>.from(item),
            ),
      ],
      pages: [
        for (final item in rawPages)
          if (item is Map)
            SmartLayoutPageDecision.fromJson(Map<String, Object?>.from(item)),
      ],
    );
  }
}
