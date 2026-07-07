import 'package:flutter/foundation.dart';

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import 'handle.dart';
import 'interaction_mode.dart';

/// The gap (in scene units) between the top-center handle and the rotation
/// handle above it.
const double _rotationHandleGap = 20.0;

/// Padding (in scene units) between element bounds and the selection box.
///
/// Returns a larger padding in [InteractionMode.touch] for easier touch
/// targeting.
double selectionPaddingFor(InteractionMode mode) =>
    mode == InteractionMode.touch ? 12.0 : 6.0;

/// Padding for [InteractionMode.pointer] — kept as a convenience constant
/// for backward compatibility.
const double selectionPadding = 6.0;

/// Extra handle offset (in scene units) for line/arrow/diamond elements.
/// These elements are thin or pointy, so handles are pushed further out.
const double _expandedHandleExtra = 10.0;

/// Element types whose handles sit further from the selection box.
const _expandedHandleTypes = {'line', 'arrow', 'diamond'};

/// Per-element bounds used for drawing individual outlines in multi-select.
class ElementSelectionBounds {
  final Bounds bounds;
  final double angle;

  const ElementSelectionBounds({required this.bounds, this.angle = 0.0});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementSelectionBounds &&
          bounds == other.bounds &&
          angle == other.angle;

  @override
  int get hashCode => Object.hash(bounds, angle);
}

/// Describes the selection UI to draw: bounding box, handles, and rotation.
class SelectionOverlay {
  final Bounds bounds;
  final List<Handle> handles;
  final double angle;
  final bool isLocked;

  /// Whether to draw the bounding box and resize/rotation handles.
  /// False for 2-point lines/arrows and elbow arrows (only point handles shown).
  final bool showBoundingBox;

  /// Per-element bounds for drawing individual outlines in multi-select.
  /// Empty for single-element selection.
  final List<ElementSelectionBounds> elementBounds;

  const SelectionOverlay({
    required this.bounds,
    required this.handles,
    this.angle = 0.0,
    this.isLocked = false,
    this.showBoundingBox = true,
    this.elementBounds = const [],
  });

  /// Creates a [SelectionOverlay] from a list of selected elements.
  ///
  /// Returns `null` if the list is empty.
  /// For a single element, the angle is preserved from the element.
  /// For multiple elements, the angle defaults to 0.
  static SelectionOverlay? fromElements(
    List<Element> elements, {
    InteractionMode mode = InteractionMode.pointer,
  }) {
    if (elements.isEmpty) return null;

    Bounds union = Bounds.fromLTWH(
      elements.first.x,
      elements.first.y,
      elements.first.width,
      elements.first.height,
    );
    for (var i = 1; i < elements.length; i++) {
      final e = elements[i];
      union = union.union(Bounds.fromLTWH(e.x, e.y, e.width, e.height));
    }

    final angle = elements.length == 1 ? elements.first.angle : 0.0;
    final isLocked = elements.every((e) => e.locked);

    // Handles sit on the selection box for shapes, further out for
    // lines/arrows/diamonds.
    final needsExpanded = elements.any(
      (e) => _expandedHandleTypes.contains(e.type),
    );
    final handlePad =
        selectionPaddingFor(mode) +
        (needsExpanded ? _expandedHandleExtra : 0.0);
    final handleBounds = Bounds.fromLTWH(
      union.left - handlePad,
      union.top - handlePad,
      union.size.width + handlePad * 2,
      union.size.height + handlePad * 2,
    );

    // Hide bounding box for single 2-point lines/arrows and elbow arrows,
    // matching Excalidraw behavior — only point handles are needed.
    var showBoundingBox = true;
    if (elements.length == 1) {
      final e = elements.first;
      if (e is LineElement) {
        if (e.points.length <= 2) {
          showBoundingBox = false;
        }
        if (e is ArrowElement && e.elbowed) {
          showBoundingBox = false;
        }
      }
    }

    // Populate per-element bounds for multi-select outlines.
    final elemBounds = elements.length > 1
        ? elements
              .map(
                (e) => ElementSelectionBounds(
                  bounds: Bounds.fromLTWH(e.x, e.y, e.width, e.height),
                  angle: e.angle,
                ),
              )
              .toList()
        : const <ElementSelectionBounds>[];

    return SelectionOverlay(
      bounds: union,
      handles: computeHandles(handleBounds),
      angle: angle,
      isLocked: isLocked,
      showBoundingBox: showBoundingBox,
      elementBounds: elemBounds,
    );
  }

  /// Computes 9 handles (8 resize + 1 rotation) for the given [bounds].
  static List<Handle> computeHandles(Bounds bounds) {
    final l = bounds.left;
    final t = bounds.top;
    final r = bounds.right;
    final b = bounds.bottom;
    final cx = (l + r) / 2;
    final cy = (t + b) / 2;

    return [
      Handle(type: HandleType.topLeft, position: Point(l, t)),
      Handle(type: HandleType.topCenter, position: Point(cx, t)),
      Handle(type: HandleType.topRight, position: Point(r, t)),
      Handle(type: HandleType.middleLeft, position: Point(l, cy)),
      Handle(type: HandleType.middleRight, position: Point(r, cy)),
      Handle(type: HandleType.bottomLeft, position: Point(l, b)),
      Handle(type: HandleType.bottomCenter, position: Point(cx, b)),
      Handle(type: HandleType.bottomRight, position: Point(r, b)),
      Handle(
        type: HandleType.rotation,
        position: Point(cx, t - _rotationHandleGap),
      ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionOverlay &&
          bounds == other.bounds &&
          angle == other.angle &&
          isLocked == other.isLocked &&
          showBoundingBox == other.showBoundingBox &&
          listEquals(handles, other.handles) &&
          listEquals(elementBounds, other.elementBounds);

  @override
  int get hashCode => Object.hash(
    bounds,
    angle,
    isLocked,
    showBoundingBox,
    Object.hashAll(handles),
    Object.hashAll(elementBounds),
  );

  @override
  String toString() => 'SelectionOverlay($bounds, angle=$angle)';
}
