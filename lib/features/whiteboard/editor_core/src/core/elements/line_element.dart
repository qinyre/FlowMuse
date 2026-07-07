import '../math/point.dart';
import 'element.dart';
import 'element_id.dart';
import 'fill_style.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// Arrowhead styles for line endpoints.
enum Arrowhead {
  arrow,
  bar,
  dot,
  triangle,
  triangleOutline,
  circle,
  circleOutline,
  diamond,
  diamondOutline,
  crowfootOne,
  crowfootMany,
  crowfootOneOrMany,
}

/// A linear element defined by a list of points.
class LineElement extends Element {
  final List<Point> points;
  final Arrowhead? startArrowhead;
  final Arrowhead? endArrowhead;
  final bool closed;

  LineElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.points,
    this.startArrowhead,
    this.endArrowhead,
    this.closed = false,
    super.angle,
    super.strokeColor,
    super.backgroundColor,
    super.fillStyle,
    super.strokeWidth,
    super.strokeStyle,
    super.roughness,
    super.opacity,
    super.roundness,
    super.seed,
    super.version,
    super.versionNonce,
    super.isDeleted,
    super.groupIds,
    super.frameId,
    super.boundElements,
    super.updated,
    super.link,
    super.locked,
    super.index,
    super.type = 'line',
  });

  /// Creates a copy with line-specific properties changed.
  LineElement copyWithLine({
    List<Point>? points,
    Arrowhead? startArrowhead,
    bool clearStartArrowhead = false,
    Arrowhead? endArrowhead,
    bool clearEndArrowhead = false,
    bool? closed,
  }) {
    return LineElement(
      id: id,
      type: type,
      x: x,
      y: y,
      width: width,
      height: height,
      points: points ?? this.points,
      startArrowhead: clearStartArrowhead
          ? null
          : (startArrowhead ?? this.startArrowhead),
      endArrowhead: clearEndArrowhead
          ? null
          : (endArrowhead ?? this.endArrowhead),
      closed: closed ?? this.closed,
      angle: angle,
      strokeColor: strokeColor,
      backgroundColor: backgroundColor,
      fillStyle: fillStyle,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      roughness: roughness,
      opacity: opacity,
      roundness: roundness,
      seed: seed,
      version: version,
      versionNonce: versionNonce,
      isDeleted: isDeleted,
      groupIds: groupIds,
      frameId: frameId,
      boundElements: boundElements,
      updated: updated,
      link: link,
      locked: locked,
      index: index,
    );
  }

  @override
  LineElement copyWith({
    ElementId? id,
    String? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? angle,
    String? strokeColor,
    String? backgroundColor,
    FillStyle? fillStyle,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    double? roughness,
    double? opacity,
    Roundness? roundness,
    bool clearRoundness = false,
    int? seed,
    int? version,
    int? versionNonce,
    bool? isDeleted,
    List<String>? groupIds,
    String? frameId,
    bool clearFrameId = false,
    List<BoundElement>? boundElements,
    int? updated,
    String? link,
    bool clearLink = false,
    bool? locked,
    String? index,
    bool clearIndex = false,
  }) {
    return LineElement(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      points: points,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      closed: closed,
      angle: angle ?? this.angle,
      strokeColor: strokeColor ?? this.strokeColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fillStyle: fillStyle ?? this.fillStyle,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeStyle: strokeStyle ?? this.strokeStyle,
      roughness: roughness ?? this.roughness,
      opacity: opacity ?? this.opacity,
      roundness: clearRoundness ? null : (roundness ?? this.roundness),
      seed: seed ?? this.seed,
      version: version ?? this.version,
      versionNonce: versionNonce ?? this.versionNonce,
      isDeleted: isDeleted ?? this.isDeleted,
      groupIds: groupIds ?? this.groupIds,
      frameId: clearFrameId ? null : (frameId ?? this.frameId),
      boundElements: boundElements ?? this.boundElements,
      updated: updated ?? this.updated,
      link: clearLink ? null : (link ?? this.link),
      locked: locked ?? this.locked,
      index: clearIndex ? null : (index ?? this.index),
    );
  }
}
