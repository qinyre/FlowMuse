import 'element.dart';
import 'element_id.dart';
import 'fill_style.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// A frame element — a named container that visually clips its children.
///
/// Children are elements whose [frameId] matches this frame's [id].
/// Frames render with clean (non-rough) lines and display their [label]
/// above the top edge.
class FrameElement extends Element {
  final String label;

  FrameElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    this.label = 'Frame',
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
  }) : super(type: 'frame');

  @override
  FrameElement copyWith({
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
    return FrameElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      label: label,
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

  /// Creates a copy with only the [label] changed.
  FrameElement copyWithLabel(String newLabel) {
    return FrameElement(
      id: id,
      x: x,
      y: y,
      width: width,
      height: height,
      label: newLabel,
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
}
