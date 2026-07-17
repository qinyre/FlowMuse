import 'dart:math' as math;

import '../../core/elements/arrow_element.dart';
import '../../core/elements/arrow_type.dart';
import '../../core/elements/element.dart';
import '../../core/elements/element_id.dart';
import '../../core/elements/line_element.dart';
import '../../core/elements/rectangle_element.dart';
import '../../core/elements/roundness.dart';
import '../../core/elements/text_element.dart';
import '../../core/math/point.dart';
import 'mindmap_tree.dart';
import 'mindmap_utils.dart';

/// Lays out a mind-map tree into Excalidraw elements.
///
/// The tree expands **horizontally to the right**: the root sits on the left,
/// children fan out to its right. Each subtree's height is computed
/// recursively and the parent is vertically centred over its children block —
/// the same silhouette as XMind/MindNode. Parent–child pairs are connected by
/// a smooth Bézier S-curve.
///
/// This class is a pure function of the tree, making it the single entry
/// point for both **manual node-by-node editing** and **AI whole-tree
/// insertion**: the LLM only emits topics + nesting, never coordinates.
///
/// Auto-reflow: after any edit (add child/sibling, edit text), the controller
/// rebuilds the tree from the scene via [MindmapUtils.treeFromScene], then
/// calls [reflowTree] to get new positions for *every* node, and writes them
/// back via [UpdateElementResult]s — so the whole tree re-centres itself,
/// exactly like mature mind-map products.
class MindmapLayout {
  MindmapLayout._();

  // --- Visual constants -------------------------------------------------

  static const double nodeWidth = 140.0;
  static const double nodeHeight = 48.0;
  static const double hGap = 80.0;
  static const double vGap = 24.0;

  /// customData tag identifying mind-map elements.
  static const String _cdKey = 'flowMuse';
  static const String _roleKey = 'role';
  static const String nodeRole = 'mindmap-node';
  static const String edgeRole = 'mindmap-edge';

  static Map<String, Object?> get nodeCustomData =>
      {_cdKey: {_roleKey: nodeRole}};
  static Map<String, Object?> get edgeCustomData =>
      {_cdKey: {_roleKey: edgeRole}};

  /// Per-level visual styling. Depth 0 = root, 1 = first-level branch, 2+ =
  /// leaves. Borrowed from mature products (XMind/MindNode): the root is the
  /// heaviest, branches carry colour, leaves recede.
  static const List<_LevelStyle> _levelStyles = [
    _LevelStyle(backgroundColor: '#1971c2', textColor: '#ffffff', fontSize: 20),
    _LevelStyle(backgroundColor: '#a5d8ff', textColor: '#1e1e1e', fontSize: 18),
    _LevelStyle(backgroundColor: '#e7f5ff', textColor: '#1e1e1e', fontSize: 16),
  ];

  /// Branch colour palette for first-level branches. Each top-level child of
  /// the root gets one of these; its descendants inherit a lightened tint so
  /// a whole branch reads as one colour family.
  static const List<String> _branchPalette = [
    '#fa5252', // red
    '#fab005', // yellow
    '#40c057', // green
    '#228be6', // blue
    '#7950f2', // violet
    '#e8590c', // orange
    '#15aabf', // teal
    '#f06595', // pink
  ];

  static _LevelStyle _styleForDepth(int depth) {
    if (depth < _levelStyles.length) return _levelStyles[depth];
    return _levelStyles.last;
  }

  /// Public style query for existing-node restyle during reflow. Returns
  /// `(backgroundColour, strokeColour, strokeWidth, roundnessValue)`.
  static (String, String, double, double) styleForNode({
    required int depth,
    required int branchIndex,
  }) {
    final style = _styleForDepth(depth);
    final bg = _backgroundColorFor(depth, branchIndex, style);
    final stroke = depth == 0 ? '#1864ab' : '#495057';
    final sw = depth == 0 ? 2.5 : 2.0;
    final rv = depth == 0 ? 20.0 : 16.0;
    return (bg, stroke, sw, rv);
  }

  /// Public text-style query: `(textColour, fontSize)` by depth.
  static (String, double) textStyleForNode({required int depth}) {
    final style = _styleForDepth(depth);
    return (style.textColor, style.fontSize);
  }

  /// Recomputes an existing mind-map edge's geometry from its endpoints' new
  /// positions, preserving the edge's id and bindings. Used by the controller
  /// after a reflow: existing edges' sampled Bézier points don't follow node
  /// moves on their own (the renderer doesn't resolve bindings), so we
  /// regenerate them against the post-reflow node rectangles.
  static ArrowElement recomputeEdge(
    ArrowElement edge,
    Element parent,
    Element child,
  ) {
    final fresh = _curveEdge(_rectFromElement(parent), _rectFromElement(child));
    // copyWithLine swaps points; copyWith swaps the bounding box. Neither
    // alone covers both, so chain them. id/bindings/style are preserved.
    return edge
        .copyWithLine(points: fresh.points)
        .copyWith(x: fresh.x, y: fresh.y, width: fresh.width, height: fresh.height);
  }

  static _VirtualRect _rectFromElement(Element e) {
    return _VirtualRect(
      id: e.id.value,
      x: e.x,
      y: e.y,
      width: e.width,
      height: e.height,
    );
  }

  // --- Whole-tree element creation (AI entry point) ---------------------

  /// Builds the complete element list for [tree], rooted at [origin].
  /// Used when inserting a brand-new tree (e.g. AI-generated). For updating
  /// an existing tree in place after an edit, use [reflowTree] instead.
  static List<Element> treeToElements(MindmapNode tree, {Point? origin}) {
    final o = origin ?? const Point(80, 80);
    final slots = <_NodeSlot>[];
    _layoutSubtree(tree, o.x, o.y, 0, -1, slots);
    return _materialize(slots, isNew: true);
  }

  // --- Auto-reflow (manual editing) -------------------------------------

  /// Re-lays out the tree and returns a plan describing how to update the
  /// existing scene so the whole tree re-centres.
  ///
  /// Each node in [tree] should carry `sourceId` (from
  /// [MindmapUtils.treeFromScene]) for existing nodes; nodes without a
  /// `sourceId` are treated as newly added and materialised as fresh
  /// elements in [ReflowPlan.newElements] (including their connecting edge).
  ///
  /// [origin] is where the root's top-left should sit. To keep the root
  /// visually stable during editing, pass the root's current top-left.
  static ReflowPlan reflowTree(MindmapNode tree, {Point? origin}) {
    final o = origin ?? const Point(80, 80);
    final slots = <_NodeSlot>[];
    _layoutSubtree(tree, o.x, o.y, 0, -1, slots);

    final nodeUpdates = <ElementUpdate>[];
    for (final slot in slots) {
      if (slot.node.sourceId case final sourceId?) {
        nodeUpdates.add(
          ElementUpdate(
            nodeId: sourceId,
            x: slot.x,
            y: slot.y,
            depth: slot.depth,
            branchIndex: slot.branchIndex,
          ),
        );
      }
    }

    // Materialise brand-new nodes (those without sourceId) plus their edges.
    // Each new slot gets one stable id, shared between its rect and its edge
    // binding so they resolve correctly.
    final newElements = <Element>[];
    final newSlots = slots.where((s) => s.node.sourceId == null).toList();
    final idForNewSlot = <_NodeSlot, ElementId>{};
    for (final slot in newSlots) {
      idForNewSlot[slot] = ElementId.generate();
    }
    for (final slot in newSlots) {
      newElements.addAll(
        _nodeElementsForSlot(slot, id: idForNewSlot[slot]!),
      );
    }
    // Edges from each new node's parent → new node. The parent is found by
    // scanning slots for the node whose children list contains this new node.
    for (final newSlot in newSlots) {
      final parentSlot = _findParentSlot(newSlot, slots);
      if (parentSlot == null) continue;
      final parentId = parentSlot.node.sourceId ?? idForNewSlot[parentSlot]?.value;
      newElements.add(
        _curveEdge(
          _rectForSlot(parentSlot, id: parentId),
          _rectForSlot(newSlot, id: idForNewSlot[newSlot]!.value),
        ),
      );
    }

    return ReflowPlan(nodeUpdates: nodeUpdates, newElements: newElements);
  }

  /// Returns the slot whose node has [childSlot.node] among its children, or
  /// null if [childSlot] is the root.
  static _NodeSlot? _findParentSlot(
    _NodeSlot childSlot,
    List<_NodeSlot> slots,
  ) {
    for (final slot in slots) {
      if (slot.node.children.contains(childSlot.node)) return slot;
    }
    return null;
  }

  /// Builds a virtual rect (position + size) for edge-anchor maths. Pass
  /// [id] to override the slot's sourceId (used when materialising a fresh
  /// tree where nodes have no sourceId yet — the generated id must be used
  /// for the edge binding to resolve).
  static _VirtualRect _rectForSlot(_NodeSlot slot, {String? id}) {
    return _VirtualRect(
      id: id ?? slot.node.sourceId,
      x: slot.x,
      y: slot.y,
      width: nodeWidth,
      height: nodeHeight,
    );
  }

  // --- Layout core (shared by both paths) -------------------------------

  /// Recursively lays out [node] at top-left (`x`, `y`) with [depth] and
  /// [branchIndex] (the index of this node's top-level branch ancestor, or -1
  /// for the root). Appends a [_NodeSlot] to [slots] and returns the total
  /// vertical height consumed by this subtree.
  static double _layoutSubtree(
    MindmapNode node,
    double x,
    double y,
    int depth,
    int branchIndex,
    List<_NodeSlot> slots,
  ) {
    // Leaf: place node and return its height.
    if (node.children.isEmpty) {
      slots.add(
        _NodeSlot(node: node, x: x, y: y, depth: depth, branchIndex: branchIndex),
      );
      return nodeHeight;
    }

    // Lay out children to the right, top to bottom.
    final childX = x + nodeWidth + hGap;
    var childY = y;
    var childrenHeight = 0.0;
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      // Each top-level child (depth 0 → children at depth 1) starts its own
      // branch colour lineage. Deeper descendants inherit the branch index.
      final childBranch = depth == 0 ? i : branchIndex;
      final subHeight = _layoutSubtree(
        child,
        childX,
        childY,
        depth + 1,
        childBranch,
        slots,
      );
      // Accumulate the child's subtree height + the gap *before* it (none for
      // the first child). This yields N*subHeight + (N-1)*vGap — the exact
      // vertical span the children block occupies.
      childrenHeight += subHeight + (i > 0 ? vGap : 0);
      // Advance childY by subHeight + vGap; the trailing vGap after the last
      // child is harmless because the loop ends.
      childY += subHeight + vGap;
    }

    // Place parent vertically centred over its children block.
    final parentY = y + (childrenHeight - nodeHeight) / 2;
    slots.add(
      _NodeSlot(node: node, x: x, y: parentY, depth: depth, branchIndex: branchIndex),
    );

    return math.max(childrenHeight, nodeHeight);
  }

  /// Turns slots into a flat element list (nodes + edges). Used by the
  /// fresh-insertion path [treeToElements].
  static List<Element> _materialize(List<_NodeSlot> slots, {required bool isNew}) {
    final out = <Element>[];

    // Assign each slot an element id (reuse sourceId for existing nodes,
    // generate fresh for new ones) and remember it for edge bindings.
    final idForSlot = <_NodeSlot, ElementId>{};
    // Map node identity → slot, so edges can find child slots regardless of
    // whether the node carries a sourceId (AI-generated trees don't).
    final slotByNode = <MindmapNode, _NodeSlot>{};
    for (final slot in slots) {
      final id = slot.node.sourceId != null
          ? ElementId(slot.node.sourceId!)
          : ElementId.generate();
      idForSlot[slot] = id;
      slotByNode[slot.node] = slot;
    }

    // Materialise node rect + text.
    for (final slot in slots) {
      out.addAll(_nodeElementsForSlot(slot, id: idForSlot[slot]!));
    }

    // Emit edges parent → child using virtual rects (so _curveEdge can bind).
    for (final slot in slots) {
      for (final child in slot.node.children) {
        final childSlot = slotByNode[child];
        if (childSlot == null) continue;
        out.add(
          _curveEdge(
            _rectForSlot(slot, id: idForSlot[slot]!.value),
            _rectForSlot(childSlot, id: idForSlot[childSlot]!.value),
          ),
        );
      }
    }
    return out;
  }

  /// Creates a root node centred at [center]. Returns `[rect, text]`.
  static List<Element> createRootAt(Point center, [String text = '中心主题']) {
    return _nodeElements(
      ElementId.generate(),
      center.x - nodeWidth / 2,
      center.y - nodeHeight / 2,
      text,
      depth: 0,
      branchIndex: -1,
    );
  }

  // --- Element factories ------------------------------------------------

  /// Creates `[rect, text]` for a node at (`x`, `y`), styled by [depth]
  /// (size/colour hierarchy) and [branchIndex] (branch colour for depth ≥ 1).
  static List<Element> _nodeElements(
    ElementId id,
    double x,
    double y,
    String text, {
    int depth = 1,
    int branchIndex = -1,
  }) {
    final slot = _NodeSlot(
      node: MindmapNode(text: text),
      x: x,
      y: y,
      depth: depth,
      branchIndex: branchIndex,
    );
    final tempRect = _rectForSlot(slot);
    return _buildPair(id, tempRect, text, depth, branchIndex);
  }

  /// Creates `[rect, text]` for a node described by [slot].
  static List<Element> _nodeElementsForSlot(_NodeSlot slot, {required ElementId id}) {
    final tempRect = _rectForSlot(slot);
    return _buildPair(
      id,
      tempRect,
      slot.node.text,
      slot.depth,
      slot.branchIndex,
    );
  }

  static List<Element> _buildPair(
    ElementId id,
    _VirtualRect r,
    String text,
    int depth,
    int branchIndex,
  ) {
    final style = _styleForDepth(depth);
    final bg = _backgroundColorFor(depth, branchIndex, style);
    final textId = ElementId.generate();
    final rect = RectangleElement(
      id: id,
      x: r.x,
      y: r.y,
      width: nodeWidth,
      height: nodeHeight,
      strokeColor: depth == 0 ? '#1864ab' : '#495057',
      backgroundColor: bg,
      strokeWidth: depth == 0 ? 2.5 : 2.0,
      roundness: Roundness.adaptive(value: depth == 0 ? 20 : 16),
      boundElements: [BoundElement(id: textId.value, type: 'text')],
      customData: nodeCustomData,
    );
    final textElement = TextElement(
      id: textId,
      x: r.x,
      y: r.y,
      width: nodeWidth,
      height: nodeHeight,
      text: text,
      fontSize: style.fontSize,
      strokeColor: style.textColor,
      containerId: id.value,
      textAlign: TextAlign.center,
      verticalAlign: VerticalAlign.middle,
    );
    return [rect, textElement];
  }

  /// Background colour for a node: depth 0 uses the level style; depth ≥ 1
  /// uses the branch palette colour lightened by depth (so a whole branch
  /// reads as one colour family, leaves are paler).
  static String _backgroundColorFor(
    int depth,
    int branchIndex,
    _LevelStyle style,
  ) {
    if (depth == 0 || branchIndex < 0) return style.backgroundColor;
    final base = _branchPalette[branchIndex % _branchPalette.length];
    if (depth == 1) return base;
    return _lighten(base, 0.78);
  }

  /// Returns a hex colour lightened towards white by [amount] ∈ [0, 1].
  static String _lighten(String hex, double amount) {
    final c = _parseHex(hex);
    if (c == null) return hex;
    final r = (c[0] + (255 - c[0]) * amount).round();
    final g = (c[1] + (255 - c[1]) * amount).round();
    final b = (c[2] + (255 - c[2]) * amount).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  static List<int>? _parseHex(String hex) {
    var h = hex;
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 3) {
      h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    }
    if (h.length != 6) return null;
    return [
      int.tryParse(h.substring(0, 2), radix: 16),
      int.tryParse(h.substring(2, 4), radix: 16),
      int.tryParse(h.substring(4, 6), radix: 16),
    ].whereType<int>().toList();
  }

  /// Creates a smooth-curve edge from [parent] (right edge) to [child]
  /// (left edge), with bindings so it follows when either node moves.
  ///
  /// Horizontal S-cubic-Bézier: both control handles point horizontally, so
  /// the curve leaves the parent tangent-horizontal and arrives at the child
  /// tangent-horizontal — same silhouette as XMind/MindNode connectors.
  ///
  /// The renderer's `drawCurvedArrow` uses Catmull-Rom, which forces the
  /// curve *through* every point. Passing the control handles directly would
  /// turn them into mandatory waypoints and create a kink. Instead we sample
  /// the true cubic Bézier at ~12 points: Catmull-Rom through dense samples
  /// reproduces the Bézier shape with no visible corner.
  static ArrowElement _curveEdge(_VirtualRect parent, _VirtualRect child) {
    final arrowId = ElementId.generate();

    final startAbs = Point(parent.x + parent.width, parent.y + parent.height / 2);
    final endAbs = Point(child.x, child.y + child.height / 2);

    final dxRaw = (endAbs.x - startAbs.x).abs() / 2;
    final dx = dxRaw.clamp(16.0, 80.0);

    final c1 = Point(startAbs.x + dx, startAbs.y);
    final c2 = Point(endAbs.x - dx, endAbs.y);

    const steps = 12;
    final absPoints = <Point>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      absPoints.add(_cubicBezier(startAbs, c1, c2, endAbs, t));
    }

    var minX = absPoints.first.x;
    var minY = absPoints.first.y;
    var maxX = absPoints.first.x;
    var maxY = absPoints.first.y;
    for (final p in absPoints) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final relPoints = absPoints
        .map((p) => Point(p.x - minX, p.y - minY))
        .toList();

    final parentId = parent.id;
    final childId = child.id;
    return ArrowElement(
      id: arrowId,
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY,
      points: relPoints,
      endArrowhead: Arrowhead.arrow,
      arrowType: ArrowType.round,
      strokeColor: '#495057',
      strokeWidth: 2.0,
      startBinding: parentId == null
          ? null
          : PointBinding(elementId: parentId, fixedPoint: const Point(1.0, 0.5)),
      endBinding: childId == null
          ? null
          : PointBinding(elementId: childId, fixedPoint: const Point(0.0, 0.5)),
      customData: edgeCustomData,
    );
  }

  /// Evaluates a cubic Bézier at parameter [t] ∈ [0, 1].
  static Point _cubicBezier(Point p0, Point p1, Point p2, Point p3, double t) {
    final u = 1 - t;
    final a = u * u * u;
    final b = 3 * u * u * t;
    final c = 3 * u * t * t;
    final d = t * t * t;
    return Point(
      a * p0.x + b * p1.x + c * p2.x + d * p3.x,
      a * p0.y + b * p1.y + c * p2.y + d * p3.y,
    );
  }
}

/// Per-level visual styling.
class _LevelStyle {
  const _LevelStyle({
    required this.backgroundColor,
    required this.textColor,
    required this.fontSize,
  });
  final String backgroundColor;
  final String textColor;
  final double fontSize;
}

/// A node's computed position + lineage metadata (internal).
class _NodeSlot {
  _NodeSlot({
    required this.node,
    required this.x,
    required this.y,
    required this.depth,
    required this.branchIndex,
  });
  final MindmapNode node;
  final double x;
  final double y;
  final int depth;
  final int branchIndex;
}

/// Position + size used for edge-anchor maths (internal). Carries the
/// element id (if the node is existing) so edges can bind to it.
class _VirtualRect {
  _VirtualRect({this.id, required this.x, required this.y, required this.width, required this.height});
  final String? id;
  final double x;
  final double y;
  final double width;
  final double height;
}

/// A description of how to update an existing node element after a reflow.
/// The controller looks up the element with [nodeId] and updates its x/y and
/// style (which depend on [depth]/[branchIndex]).
class ElementUpdate {
  ElementUpdate({
    required this.nodeId,
    required this.x,
    required this.y,
    required this.depth,
    required this.branchIndex,
  });
  final String nodeId;
  final double x;
  final double y;
  final int depth;
  final int branchIndex;
}

/// The result of [MindmapLayout.reflowTree]: updates for existing nodes +
/// brand-new elements to add.
class ReflowPlan {
  ReflowPlan({required this.nodeUpdates, required this.newElements});

  /// Updates for nodes that already exist in the scene (matched by
  /// [ElementUpdate.nodeId] == `MindmapNode.sourceId`).
  final List<ElementUpdate> nodeUpdates;

  /// Brand-new elements to add (new nodes + their bound text + their edge).
  final List<Element> newElements;
}
