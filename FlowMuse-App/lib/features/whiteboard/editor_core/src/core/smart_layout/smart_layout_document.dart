import 'package:flutter/foundation.dart';

import '../elements/elements.dart';
import '../math/math.dart';

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

/// 视觉优先管线请求：整页截图（含编号标记，Set-of-Mark）+可选笔记标题，
/// 服务端调 VLM 一次判定；marks 是客户端已画进截图的编号列表。
class SmartLayoutVisionRequest {
  const SmartLayoutVisionRequest({
    required this.pageId,
    required this.imageBase64,
    this.noteTitle,
    this.imageMime = 'image/png',
    this.marks = const [],
  });

  final String pageId;
  final String? noteTitle;
  final String imageMime;
  final String imageBase64;

  /// 截图上已画出的编号标记（"m1"、"m2"...），VLM 输出引用必须出自这里。
  final List<String> marks;

  Map<String, Object?> toJson() => {
    'pageId': pageId,
    if (noteTitle != null && noteTitle!.isNotEmpty) 'noteTitle': noteTitle,
    'imageMime': imageMime,
    'imageBase64': imageBase64,
    if (marks.isNotEmpty) 'marks': marks,
  };
}

/// VLM 对页面内一项内容的描述；markIds 引用截图上的编号标记（Set-of-Mark，
/// 客户端按编号直查场景对象，不做坐标回归）。
@immutable
class SmartLayoutVisionElement {
  const SmartLayoutVisionElement({
    required this.role,
    this.id,
    this.text,
    this.vertical = false,
    this.markIds = const [],
    this.pairId,
    this.confidence = 0.5,
  });

  /// 服务端按输出顺序分配的引用 id（"e0"、"e1"...），mindmap 树以此引用。
  final String? id;

  /// title | caption | body | figure（未知角色已在服务端归为 body）。
  final String role;
  final String? text;
  final bool vertical;

  /// 引用的截图编号标记（服务端已校验出自请求 marks 且全局不重复）。
  final List<String> markIds;

  final String? pairId;

  /// VLM 对该元素认字把握的自评分（0-1；服务端已钳制）。
  /// 未自报时视为存疑（0.5，与服务端 defaultVisionConfidence 一致），
  /// 低于重问阈值会触发裁剪重问复核。
  final double confidence;

  bool get isFigure => role == 'figure';

  factory SmartLayoutVisionElement.fromJson(Map<String, Object?> json) {
    return SmartLayoutVisionElement(
      id: json['id'] as String?,
      role: json['role'] as String? ?? 'body',
      text: json['text'] as String?,
      vertical: json['vertical'] == true,
      markIds: [
        for (final item in json['markIds'] as List<Object?>? ?? const [])
          if (item is String) item,
      ],
      pairId: json['pairId'] as String?,
      confidence:
          ((json['confidence'] as num?)?.toDouble() ?? 0.5)
              .clamp(0.0, 1.0)
              .toDouble(),
    );
  }
}

/// 视觉识别结果（服务端已做过角色白名单/编号引用校验/幻觉过滤）：
/// 只含认字与图文配对，版式由客户端模板卡片选择后确定性落位。
class SmartLayoutVisionResponse {
  const SmartLayoutVisionResponse({required this.elements});

  final List<SmartLayoutVisionElement> elements;

  factory SmartLayoutVisionResponse.fromJson(Map<String, Object?> json) {
    return SmartLayoutVisionResponse(
      elements: [
        for (final item in json['elements'] as List<Object?>? ?? const [])
          if (item is Map)
            SmartLayoutVisionElement.fromJson(Map<String, Object?>.from(item)),
      ],
    );
  }
}

/// 低置信裁剪重问请求：从整页截图裁出的局部块（外扩 16pt），无上下文单块转写。
/// hint 只允许笔记标题等中性提示，禁止传入原识别结果以免锚定模型。
class SmartLayoutTranscribeRequest {
  const SmartLayoutTranscribeRequest({
    required this.imageBase64,
    this.imageMime = 'image/png',
    this.hint,
  });

  final String imageMime;
  final String imageBase64;
  final String? hint;

  Map<String, Object?> toJson() => {
    if (hint != null && hint!.isNotEmpty) 'hint': hint,
    'imageMime': imageMime,
    'imageBase64': imageBase64,
  };
}

/// 单块转写结果；text 为空表示无法辨认（服务端保证此时 confidence 为 0）。
@immutable
class SmartLayoutTranscribeResponse {
  const SmartLayoutTranscribeResponse({
    required this.text,
    this.confidence = 0,
  });

  final String text;

  /// 模型对该块认字把握的自评分（0-1；服务端已钳制）。
  final double confidence;

  factory SmartLayoutTranscribeResponse.fromJson(Map<String, Object?> json) {
    return SmartLayoutTranscribeResponse(
      text: (json['text'] as String? ?? '').trim(),
      confidence:
          ((json['confidence'] as num?)?.toDouble() ?? 0)
              .clamp(0.0, 1.0)
              .toDouble(),
    );
  }
}
