import 'dart:math' as math;

import '../elements/elements.dart';
import '../math/bounds.dart';

/// Stateless utilities for aligning and distributing elements.
///
/// All operations use each element's **rotated** axis-aligned bounding box
/// (the AABB of its four rotated corners) so that alignment matches the
/// visual position on screen.
class AlignmentUtils {
  AlignmentUtils._();

  /// Align all elements' visual left edges to the union bounding box's left.
  static List<Element> alignLeft(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    return [
      for (final info in infos)
        info.element.copyWith(
          x: info.element.x + (union.left - info.aabb.left),
        ),
    ];
  }

  /// Align all elements' visual horizontal centers to the union center.
  static List<Element> alignCenterH(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    final targetCx = union.left + union.size.width / 2;
    return [
      for (final info in infos)
        info.element.copyWith(
          x: info.element.x + (targetCx - info.aabbCenterX),
        ),
    ];
  }

  /// Align all elements' visual right edges to the union bounding box's right.
  static List<Element> alignRight(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    final targetRight = union.left + union.size.width;
    return [
      for (final info in infos)
        info.element.copyWith(
          x: info.element.x + (targetRight - info.aabb.right),
        ),
    ];
  }

  /// Align all elements' visual top edges to the union bounding box's top.
  static List<Element> alignTop(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    return [
      for (final info in infos)
        info.element.copyWith(y: info.element.y + (union.top - info.aabb.top)),
    ];
  }

  /// Align all elements' visual vertical centers to the union center.
  static List<Element> alignCenterV(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    final targetCy = union.top + union.size.height / 2;
    return [
      for (final info in infos)
        info.element.copyWith(
          y: info.element.y + (targetCy - info.aabbCenterY),
        ),
    ];
  }

  /// Align all elements' visual bottom edges to the union bounding box's bottom.
  static List<Element> alignBottom(List<Element> elements) {
    if (elements.length < 2) return [];
    final infos = elements.map(_ElementInfo.from).toList();
    final union = _unionOf(infos);
    final targetBottom = union.top + union.size.height;
    return [
      for (final info in infos)
        info.element.copyWith(
          y: info.element.y + (targetBottom - info.aabb.bottom),
        ),
    ];
  }

  /// Distribute elements evenly horizontally using their visual bounding boxes.
  ///
  /// Requires 3+ elements. Sorted by visual left edge; the leftmost and
  /// rightmost stay fixed, others are evenly spaced between them.
  static List<Element> distributeH(List<Element> elements) {
    if (elements.length < 3) return [];
    final infos = elements.map(_ElementInfo.from).toList()
      ..sort((a, b) => a.aabb.left.compareTo(b.aabb.left));

    final first = infos.first;
    final last = infos.last;
    final totalWidth = last.aabb.right - first.aabb.left;
    final elemWidths = infos.fold<double>(
      0,
      (sum, info) => sum + info.aabb.size.width,
    );
    final gap = (totalWidth - elemWidths) / (infos.length - 1);

    var currentLeft = first.aabb.left;
    final results = <Element>[];
    for (final info in infos) {
      final dx = currentLeft - info.aabb.left;
      results.add(info.element.copyWith(x: info.element.x + dx));
      currentLeft += info.aabb.size.width + gap;
    }
    return results;
  }

  /// Distribute elements evenly vertically using their visual bounding boxes.
  ///
  /// Requires 3+ elements. Sorted by visual top edge; the topmost and
  /// bottommost stay fixed, others are evenly spaced between them.
  static List<Element> distributeV(List<Element> elements) {
    if (elements.length < 3) return [];
    final infos = elements.map(_ElementInfo.from).toList()
      ..sort((a, b) => a.aabb.top.compareTo(b.aabb.top));

    final first = infos.first;
    final last = infos.last;
    final totalHeight = last.aabb.bottom - first.aabb.top;
    final elemHeights = infos.fold<double>(
      0,
      (sum, info) => sum + info.aabb.size.height,
    );
    final gap = (totalHeight - elemHeights) / (infos.length - 1);

    var currentTop = first.aabb.top;
    final results = <Element>[];
    for (final info in infos) {
      final dy = currentTop - info.aabb.top;
      results.add(info.element.copyWith(y: info.element.y + dy));
      currentTop += info.aabb.size.height + gap;
    }
    return results;
  }

  static Bounds _unionOf(List<_ElementInfo> infos) {
    var b = infos.first.aabb;
    for (var i = 1; i < infos.length; i++) {
      b = b.union(infos[i].aabb);
    }
    return b;
  }
}

/// Cached info about an element's rotated axis-aligned bounding box.
class _ElementInfo {
  final Element element;

  /// The axis-aligned bounding box of the element's four rotated corners.
  final Bounds aabb;

  double get aabbCenterX => aabb.left + aabb.size.width / 2;
  double get aabbCenterY => aabb.top + aabb.size.height / 2;

  _ElementInfo(this.element, this.aabb);

  factory _ElementInfo.from(Element e) {
    return _ElementInfo(e, _rotatedAABB(e));
  }

  /// Compute the axis-aligned bounding box of the element after rotation.
  ///
  /// For angle == 0 this returns the element's own (x, y, width, height).
  static Bounds _rotatedAABB(Element e) {
    if (e.angle == 0) {
      return Bounds.fromLTWH(e.x, e.y, e.width, e.height);
    }

    final cx = e.x + e.width / 2;
    final cy = e.y + e.height / 2;
    final cosA = math.cos(e.angle);
    final sinA = math.sin(e.angle);

    // Four corners in local space, rotated around center
    final corners = [
      _rotate(e.x, e.y, cx, cy, cosA, sinA),
      _rotate(e.x + e.width, e.y, cx, cy, cosA, sinA),
      _rotate(e.x + e.width, e.y + e.height, cx, cy, cosA, sinA),
      _rotate(e.x, e.y + e.height, cx, cy, cosA, sinA),
    ];

    var minX = corners[0].x;
    var minY = corners[0].y;
    var maxX = corners[0].x;
    var maxY = corners[0].y;
    for (var i = 1; i < corners.length; i++) {
      minX = math.min(minX, corners[i].x);
      minY = math.min(minY, corners[i].y);
      maxX = math.max(maxX, corners[i].x);
      maxY = math.max(maxY, corners[i].y);
    }
    return Bounds.fromLTWH(minX, minY, maxX - minX, maxY - minY);
  }

  static ({double x, double y}) _rotate(
    double px,
    double py,
    double cx,
    double cy,
    double cosA,
    double sinA,
  ) {
    final dx = px - cx;
    final dy = py - cy;
    return (x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA);
  }
}
