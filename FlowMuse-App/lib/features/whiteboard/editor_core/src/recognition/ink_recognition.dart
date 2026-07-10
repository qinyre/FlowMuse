import '../core/math/math.dart';

class InkRecognitionPoint {
  const InkRecognitionPoint({required this.x, required this.y, this.t});

  final double x;
  final double y;
  final int? t;

  factory InkRecognitionPoint.fromPoint(Point point, {int? t}) {
    return InkRecognitionPoint(x: point.x, y: point.y, t: t);
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y, if (t != null) 't': t};

  factory InkRecognitionPoint.fromJson(Map<String, Object?> json) {
    return InkRecognitionPoint(
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      t: (json['t'] as num?)?.toInt(),
    );
  }

  Point toPoint() => Point(x, y);
}

class InkRecognitionStroke {
  const InkRecognitionStroke({required this.id, required this.points});

  final String id;
  final List<InkRecognitionPoint> points;

  Map<String, Object?> toJson() => {
    'id': id,
    'points': points.map((point) => point.toJson()).toList(),
  };
}

class InkRecognitionBounds {
  const InkRecognitionBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory InkRecognitionBounds.fromJson(Map<String, Object?> json) {
    return InkRecognitionBounds(
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
    );
  }
}

class InkRecognitionRequest {
  const InkRecognitionRequest({
    required this.sessionId,
    required this.strokes,
    required this.bounds,
    this.hint = 'auto',
  });

  final String sessionId;
  final String hint;
  final List<InkRecognitionStroke> strokes;
  final InkRecognitionBounds bounds;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'hint': hint,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    'bounds': bounds.toJson(),
  };
}

class InkRecognitionResult {
  const InkRecognitionResult({required this.elements});

  final List<InkRecognizedElement> elements;

  factory InkRecognitionResult.fromJson(Map<String, Object?> json) {
    final raw = json['elements'] as List<Object?>? ?? const [];
    return InkRecognitionResult(
      elements: [
        for (final item in raw)
          if (item is Map<String, Object?>) InkRecognizedElement.fromJson(item),
      ],
    );
  }
}

class InkRecognizedElement {
  const InkRecognizedElement({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.text,
    this.latex,
    this.points = const [],
  });

  final String type;
  final String? text;
  final String? latex;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<InkRecognitionPoint> points;

  factory InkRecognizedElement.fromJson(Map<String, Object?> json) {
    final rawPoints = json['points'] as List<Object?>? ?? const [];
    return InkRecognizedElement(
      type: json['type']! as String,
      text: json['text'] as String?,
      latex: json['latex'] as String?,
      x: (json['x']! as num).toDouble(),
      y: (json['y']! as num).toDouble(),
      width: (json['width']! as num).toDouble(),
      height: (json['height']! as num).toDouble(),
      points: [
        for (final item in rawPoints)
          if (item is Map<String, Object?>) InkRecognitionPoint.fromJson(item),
      ],
    );
  }
}
