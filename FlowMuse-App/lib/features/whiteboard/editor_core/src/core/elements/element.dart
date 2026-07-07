import 'dart:math' as math;

import 'element_id.dart';
import 'fill_style.dart';
import 'roundness.dart';
import 'stroke_style.dart';

/// A reference to another element that is bound to this one (e.g., an arrow).
class BoundElement {
  final String id;
  final String type;

  const BoundElement({required this.id, required this.type});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundElement && id == other.id && type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'BoundElement($id, $type)';
}

final _random = math.Random();

/// Base class for all drawing elements.
///
/// Elements are identity-equal by [id]. Use [copyWith] to create modified
/// copies and [bumpVersion] to track changes.
class Element {
  final ElementId id;
  final String type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double angle;
  final String strokeColor;
  final String backgroundColor;
  final FillStyle fillStyle;
  final double strokeWidth;
  final StrokeStyle strokeStyle;
  final double roughness;
  final double opacity;
  final Roundness? roundness;
  final int seed;
  final int version;
  final int versionNonce;
  final bool isDeleted;
  final List<String> groupIds;
  final String? frameId;
  final List<BoundElement> boundElements;
  final int updated;
  final String? link;
  final bool locked;
  final String? index;

  Element({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.angle = 0.0,
    this.strokeColor = '#000000',
    this.backgroundColor = 'transparent',
    this.fillStyle = FillStyle.solid,
    this.strokeWidth = 2.0,
    this.strokeStyle = StrokeStyle.solid,
    this.roughness = 1.0,
    this.opacity = 1.0,
    this.roundness,
    int? seed,
    this.version = 1,
    int? versionNonce,
    this.isDeleted = false,
    this.groupIds = const [],
    this.frameId,
    this.boundElements = const [],
    int? updated,
    this.link,
    this.locked = false,
    this.index,
  }) : seed = seed ?? (id.value.hashCode & 0x7FFFFFFF),
       versionNonce = versionNonce ?? _random.nextInt(1 << 31),
       updated = updated ?? DateTime.now().millisecondsSinceEpoch;

  /// Creates a copy with the given fields replaced.
  Element copyWith({
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
    return Element(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
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

  /// Returns a new element with version incremented and a fresh nonce.
  Element bumpVersion() {
    return copyWith(
      version: version + 1,
      versionNonce: _random.nextInt(1 << 31),
      updated: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Returns a new element marked as soft-deleted with bumped version.
  Element softDelete() {
    return bumpVersion().copyWith(isDeleted: true);
  }

  /// Elements are identity-equal by [id].
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Element && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Element($type, id=$id, pos=($x, $y))';
}
