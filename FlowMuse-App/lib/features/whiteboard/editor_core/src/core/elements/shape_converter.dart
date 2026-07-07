import 'diamond_element.dart';
import 'element.dart';
import 'ellipse_element.dart';
import 'rectangle_element.dart';

/// Converts between shape element types (rectangle, diamond, ellipse).
///
/// Preserves all shared properties (position, size, style, angle, groupIds,
/// boundElements, etc.) while changing the element type.
class ShapeConverter {
  ShapeConverter._();

  /// Cycle order: rectangle → diamond → ellipse → rectangle.
  /// Returns null if the element is not a convertible shape.
  static Element? cycleShape(Element element, {bool reverse = false}) {
    if (element is! RectangleElement &&
        element is! DiamondElement &&
        element is! EllipseElement) {
      return null;
    }

    if (reverse) {
      return switch (element) {
        RectangleElement() => _toEllipse(element),
        DiamondElement() => _toRectangle(element),
        EllipseElement() => _toDiamond(element),
        _ => null,
      };
    }
    return switch (element) {
      RectangleElement() => _toDiamond(element),
      DiamondElement() => _toEllipse(element),
      EllipseElement() => _toRectangle(element),
      _ => null,
    };
  }

  static RectangleElement _toRectangle(Element e) {
    return RectangleElement(
      id: e.id,
      x: e.x,
      y: e.y,
      width: e.width,
      height: e.height,
      angle: e.angle,
      strokeColor: e.strokeColor,
      backgroundColor: e.backgroundColor,
      fillStyle: e.fillStyle,
      strokeWidth: e.strokeWidth,
      strokeStyle: e.strokeStyle,
      roughness: e.roughness,
      opacity: e.opacity,
      roundness: e.roundness,
      seed: e.seed,
      groupIds: e.groupIds,
      frameId: e.frameId,
      boundElements: e.boundElements,
      link: e.link,
      locked: e.locked,
    );
  }

  static DiamondElement _toDiamond(Element e) {
    return DiamondElement(
      id: e.id,
      x: e.x,
      y: e.y,
      width: e.width,
      height: e.height,
      angle: e.angle,
      strokeColor: e.strokeColor,
      backgroundColor: e.backgroundColor,
      fillStyle: e.fillStyle,
      strokeWidth: e.strokeWidth,
      strokeStyle: e.strokeStyle,
      roughness: e.roughness,
      opacity: e.opacity,
      roundness: e.roundness,
      seed: e.seed,
      groupIds: e.groupIds,
      frameId: e.frameId,
      boundElements: e.boundElements,
      link: e.link,
      locked: e.locked,
    );
  }

  static EllipseElement _toEllipse(Element e) {
    return EllipseElement(
      id: e.id,
      x: e.x,
      y: e.y,
      width: e.width,
      height: e.height,
      angle: e.angle,
      strokeColor: e.strokeColor,
      backgroundColor: e.backgroundColor,
      fillStyle: e.fillStyle,
      strokeWidth: e.strokeWidth,
      strokeStyle: e.strokeStyle,
      roughness: e.roughness,
      opacity: e.opacity,
      roundness: e.roundness,
      seed: e.seed,
      groupIds: e.groupIds,
      frameId: e.frameId,
      boundElements: e.boundElements,
      link: e.link,
      locked: e.locked,
    );
  }
}
