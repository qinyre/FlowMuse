import 'element.dart';
import 'element_id.dart';
import 'fill_style.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// Text alignment within a text element.
enum TextAlign { left, center, right }

/// Vertical alignment of bound text within a container shape.
enum VerticalAlign { top, middle, bottom }

/// A text drawing element.
class TextElement extends Element {
  final String text;
  final double fontSize;
  final String fontFamily;
  final TextAlign textAlign;
  final VerticalAlign verticalAlign;
  final String? containerId;
  final double lineHeight;
  final bool autoResize;

  TextElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required this.text,
    this.fontSize = 20.0,
    this.fontFamily = 'Excalifont',
    this.textAlign = TextAlign.left,
    this.verticalAlign = VerticalAlign.middle,
    this.containerId,
    this.lineHeight = 1.25,
    this.autoResize = true,
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
  }) : super(type: 'text');

  /// Creates a copy with text-specific properties changed.
  TextElement copyWithText({
    String? text,
    double? fontSize,
    String? fontFamily,
    TextAlign? textAlign,
    VerticalAlign? verticalAlign,
    String? containerId,
    bool clearContainerId = false,
    double? lineHeight,
    bool? autoResize,
  }) {
    return TextElement(
      id: id,
      x: x,
      y: y,
      width: width,
      height: height,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      verticalAlign: verticalAlign ?? this.verticalAlign,
      containerId: clearContainerId ? null : (containerId ?? this.containerId),
      lineHeight: lineHeight ?? this.lineHeight,
      autoResize: autoResize ?? this.autoResize,
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
  TextElement copyWith({
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
    return TextElement(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      textAlign: textAlign,
      verticalAlign: verticalAlign,
      containerId: containerId,
      lineHeight: lineHeight,
      autoResize: autoResize,
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
