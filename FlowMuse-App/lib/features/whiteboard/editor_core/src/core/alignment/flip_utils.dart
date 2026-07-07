import 'dart:math' as math;

import '../elements/elements.dart';
import '../math/bounds.dart';
import '../math/point.dart';

/// Stateless utilities for flipping elements horizontally or vertically.
///
/// All operations mirror elements around the union bounding box center,
/// using rotated axis-aligned bounding boxes (same approach as AlignmentUtils).
class FlipUtils {
  FlipUtils._();

  /// Flip all elements horizontally around their union bounding box center.
  static List<Element> flipHorizontal(List<Element> elements) {
    if (elements.isEmpty) return [];
    final infos = elements.map(_FlipInfo.from).toList();
    final union = _unionOf(infos);
    final centerX = union.left + union.size.width / 2;

    return [for (final info in infos) _flipH(info.element, centerX)];
  }

  /// Flip all elements vertically around their union bounding box center.
  static List<Element> flipVertical(List<Element> elements) {
    if (elements.isEmpty) return [];
    final infos = elements.map(_FlipInfo.from).toList();
    final union = _unionOf(infos);
    final centerY = union.top + union.size.height / 2;

    return [for (final info in infos) _flipV(info.element, centerY)];
  }

  static Element _flipH(Element e, double centerX) {
    // Mirror element center around centerX
    final elemCenterX = e.x + e.width / 2;
    final newCenterX = 2 * centerX - elemCenterX;
    final newX = newCenterX - e.width / 2;

    // Negate angle for rotated elements
    final newAngle = e.angle != 0 ? -e.angle : 0.0;

    var result = e.copyWith(x: newX, angle: newAngle);

    // Mirror points for line/arrow/freedraw
    if (e is LineElement) {
      final mirroredPoints = e.points
          .map((p) => Point(e.width - p.x, p.y))
          .toList();
      result = (result as LineElement).copyWithLine(points: mirroredPoints);

      // Swap arrowheads on horizontal flip
      if (e is ArrowElement) {
        result = (result as ArrowElement).copyWithLine(
          startArrowhead: e.endArrowhead,
          clearStartArrowhead: e.endArrowhead == null,
          endArrowhead: e.startArrowhead,
          clearEndArrowhead: e.startArrowhead == null,
        );
      }
    } else if (e is FreedrawElement) {
      final mirroredPoints = e.points
          .map((p) => Point(e.width - p.x, p.y))
          .toList();
      result = FreedrawElement(
        id: result.id,
        x: newX,
        y: result.y,
        width: result.width,
        height: result.height,
        points: mirroredPoints,
        pressures: e.pressures,
        simulatePressure: e.simulatePressure,
        angle: newAngle,
        strokeColor: result.strokeColor,
        backgroundColor: result.backgroundColor,
        fillStyle: result.fillStyle,
        strokeWidth: result.strokeWidth,
        strokeStyle: result.strokeStyle,
        roughness: result.roughness,
        opacity: result.opacity,
        roundness: result.roundness,
        seed: result.seed,
        groupIds: result.groupIds,
        frameId: result.frameId,
        boundElements: result.boundElements,
        link: result.link,
        locked: result.locked,
      );
    }

    return result;
  }

  static Element _flipV(Element e, double centerY) {
    // Mirror element center around centerY
    final elemCenterY = e.y + e.height / 2;
    final newCenterY = 2 * centerY - elemCenterY;
    final newY = newCenterY - e.height / 2;

    // Negate angle for rotated elements
    final newAngle = e.angle != 0 ? -e.angle : 0.0;

    var result = e.copyWith(y: newY, angle: newAngle);

    // Mirror points for line/arrow/freedraw
    if (e is LineElement) {
      final mirroredPoints = e.points
          .map((p) => Point(p.x, e.height - p.y))
          .toList();
      result = (result as LineElement).copyWithLine(points: mirroredPoints);
    } else if (e is FreedrawElement) {
      final mirroredPoints = e.points
          .map((p) => Point(p.x, e.height - p.y))
          .toList();
      result = FreedrawElement(
        id: result.id,
        x: result.x,
        y: newY,
        width: result.width,
        height: result.height,
        points: mirroredPoints,
        pressures: e.pressures,
        simulatePressure: e.simulatePressure,
        angle: newAngle,
        strokeColor: result.strokeColor,
        backgroundColor: result.backgroundColor,
        fillStyle: result.fillStyle,
        strokeWidth: result.strokeWidth,
        strokeStyle: result.strokeStyle,
        roughness: result.roughness,
        opacity: result.opacity,
        roundness: result.roundness,
        seed: result.seed,
        groupIds: result.groupIds,
        frameId: result.frameId,
        boundElements: result.boundElements,
        link: result.link,
        locked: result.locked,
      );
    }

    return result;
  }

  static Bounds _unionOf(List<_FlipInfo> infos) {
    var b = infos.first.aabb;
    for (var i = 1; i < infos.length; i++) {
      b = b.union(infos[i].aabb);
    }
    return b;
  }
}

/// Cached rotated AABB for flip calculations.
class _FlipInfo {
  final Element element;
  final Bounds aabb;

  _FlipInfo(this.element, this.aabb);

  factory _FlipInfo.from(Element e) {
    return _FlipInfo(e, _rotatedAABB(e));
  }

  static Bounds _rotatedAABB(Element e) {
    if (e.angle == 0) {
      return Bounds.fromLTWH(e.x, e.y, e.width, e.height);
    }

    final cx = e.x + e.width / 2;
    final cy = e.y + e.height / 2;
    final cosA = math.cos(e.angle);
    final sinA = math.sin(e.angle);

    final corners = [
      _rotate(e.x, e.y, cx, cy, cosA, sinA),
      _rotate(e.x + e.width, e.y, cx, cy, cosA, sinA),
      _rotate(e.x + e.width, e.y + e.height, cx, cy, cosA, sinA),
      _rotate(e.x, e.y + e.height, cx, cy, cosA, sinA),
    ];

    var minX = corners[0].$1;
    var minY = corners[0].$2;
    var maxX = corners[0].$1;
    var maxY = corners[0].$2;
    for (var i = 1; i < corners.length; i++) {
      minX = math.min(minX, corners[i].$1);
      minY = math.min(minY, corners[i].$2);
      maxX = math.max(maxX, corners[i].$1);
      maxY = math.max(maxY, corners[i].$2);
    }
    return Bounds.fromLTWH(minX, minY, maxX - minX, maxY - minY);
  }

  static (double, double) _rotate(
    double px,
    double py,
    double cx,
    double cy,
    double cosA,
    double sinA,
  ) {
    final dx = px - cx;
    final dy = py - cy;
    return (cx + dx * cosA - dy * sinA, cy + dx * sinA + dy * cosA);
  }
}
