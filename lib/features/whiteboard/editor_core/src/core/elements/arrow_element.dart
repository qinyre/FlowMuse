import '../math/point.dart';
import 'arrow_type.dart';
import 'element.dart';
import 'element_id.dart';
import 'fill_style.dart';
import 'line_element.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// A binding between an arrow endpoint and another element.
class PointBinding {
  final String elementId;
  final Point fixedPoint;

  const PointBinding({required this.elementId, required this.fixedPoint});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointBinding &&
          elementId == other.elementId &&
          fixedPoint == other.fixedPoint;

  @override
  int get hashCode => Object.hash(elementId, fixedPoint);

  @override
  String toString() => 'PointBinding($elementId, $fixedPoint)';
}

/// An arrow element — a line with bindings to other elements.
class ArrowElement extends LineElement {
  final PointBinding? startBinding;
  final PointBinding? endBinding;
  final ArrowType arrowType;

  /// Whether this arrow uses elbow (orthogonal) routing.
  bool get elbowed => arrowType.isElbow;

  ArrowElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.points,
    super.startArrowhead,
    super.endArrowhead = Arrowhead.arrow,
    super.closed,
    this.startBinding,
    this.endBinding,
    this.arrowType = ArrowType.sharp,
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
  }) : super(type: 'arrow');

  /// Creates a copy with arrow-specific properties changed.
  ArrowElement copyWithArrow({
    PointBinding? startBinding,
    bool clearStartBinding = false,
    PointBinding? endBinding,
    bool clearEndBinding = false,
    ArrowType? arrowType,
  }) {
    return ArrowElement(
      id: id,
      x: x,
      y: y,
      width: width,
      height: height,
      points: points,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      startBinding: clearStartBinding
          ? null
          : (startBinding ?? this.startBinding),
      endBinding: clearEndBinding ? null : (endBinding ?? this.endBinding),
      arrowType: arrowType ?? this.arrowType,
      closed: closed,
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
  ArrowElement copyWithLine({
    List<Point>? points,
    Arrowhead? startArrowhead,
    bool clearStartArrowhead = false,
    Arrowhead? endArrowhead,
    bool clearEndArrowhead = false,
    bool? closed,
  }) {
    return ArrowElement(
      id: id,
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
      startBinding: startBinding,
      endBinding: endBinding,
      arrowType: arrowType,
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
  ArrowElement copyWith({
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
    return ArrowElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      points: points,
      startArrowhead: startArrowhead,
      endArrowhead: endArrowhead,
      startBinding: startBinding,
      endBinding: endBinding,
      arrowType: arrowType,
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
