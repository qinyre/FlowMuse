import 'element.dart';
import 'element_id.dart';
import 'fill_style.dart';
import 'image_crop.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// An image drawing element.
///
/// The actual image data is stored in the Scene's file store, keyed by
/// [fileId]. The element tracks position, dimensions, optional [crop],
/// and [imageScale].
class ImageElement extends Element {
  final String fileId;
  final String? mimeType;
  final ImageCrop? crop;
  final double imageScale;

  ImageElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.fileId,
    this.mimeType,
    this.crop,
    this.imageScale = 1.0,
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
  }) : super(type: 'image');

  @override
  ImageElement copyWith({
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
    return ImageElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      fileId: fileId,
      mimeType: mimeType,
      crop: crop,
      imageScale: imageScale,
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

  /// Creates a copy with image-specific fields changed.
  ImageElement copyWithImage({
    String? fileId,
    String? mimeType,
    ImageCrop? crop,
    bool clearCrop = false,
    double? imageScale,
  }) {
    return ImageElement(
      id: id,
      x: x,
      y: y,
      width: width,
      height: height,
      fileId: fileId ?? this.fileId,
      mimeType: mimeType ?? this.mimeType,
      crop: clearCrop ? null : (crop ?? this.crop),
      imageScale: imageScale ?? this.imageScale,
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
