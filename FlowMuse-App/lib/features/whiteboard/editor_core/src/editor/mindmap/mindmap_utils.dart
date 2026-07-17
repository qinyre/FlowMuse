import '../../core/elements/arrow_element.dart';
import '../../core/elements/element.dart';
import '../../core/elements/text_element.dart';
import 'mindmap_layout.dart';
import 'mindmap_tree.dart';

/// Query helpers for mind-map elements within a scene's element list.
///
/// These operate on plain `List<Element>` (rather than `Scene`) so they can
/// be used both from layout code and from controller logic that already
/// holds the element list.
class MindmapUtils {
  MindmapUtils._();

  /// Returns true if [e] is a mind-map node (rectangle tagged via
  /// `customData['flowMuse']['role'] == 'mindmap-node'`).
  static bool isMindmapNode(Element e) {
    if (e.type != 'rectangle') return false;
    return _role(e) == MindmapLayout.nodeRole;
  }

  /// Returns true if [e] is a mind-map connecting edge.
  static bool isMindmapEdge(Element e) {
    if (e is! ArrowElement) return false;
    return _role(e) == MindmapLayout.edgeRole;
  }

  /// Returns the mind-map children of [parent] — the node rectangles that
  /// [parent] connects to via outgoing mind-map edges, in vertical (top to
  /// bottom) order so layout stacking matches visual order.
  static List<Element> childrenOf(
    Element parent,
    List<Element> elements,
  ) {
    final childIds = <String>{};
    for (final e in elements) {
      if (e.isDeleted) continue;
      if (e is! ArrowElement) continue;
      if (!isMindmapEdge(e)) continue;
      final start = e.startBinding;
      final end = e.endBinding;
      if (start != null && start.elementId == parent.id.value && end != null) {
        childIds.add(end.elementId);
      }
    }
    if (childIds.isEmpty) return const [];
    final children = elements
        .where((e) => !e.isDeleted && childIds.contains(e.id.value))
        .toList();
    // Sort by current y so the order reflects visual top→bottom.
    children.sort((a, b) => a.y.compareTo(b.y));
    return children;
  }

  /// Returns the mind-map parent of [child], or null if it is a root.
  static Element? parentOf(Element child, List<Element> elements) {
    for (final e in elements) {
      if (e.isDeleted) continue;
      if (e is! ArrowElement) continue;
      if (!isMindmapEdge(e)) continue;
      final start = e.startBinding;
      final end = e.endBinding;
      if (end != null && end.elementId == child.id.value && start != null) {
        final parentId = start.elementId;
        final parent = elements.firstWhere(
          (pe) => !pe.isDeleted && pe.id.value == parentId,
          orElse: () => e, // defensive
        );
        if (parent.id.value == parentId) return parent;
      }
    }
    return null;
  }

  /// Rebuilds a [MindmapNode] tree rooted at [rootNode] by walking the
  /// mind-map edges in [elements]. Node text is read from the bound text
  /// element of each node rectangle. Used by the auto-reflow: after editing,
  /// the controller rebuilds the tree, re-lays it out, and writes back the
  /// new coordinates.
  ///
  /// Each returned [MindmapNode] also carries its source element id via
  /// [MindmapNode.sourceId], so the reflow can update existing elements in
  /// place (preserving ids) rather than recreating them.
  static MindmapNode treeFromScene(
    Element rootNode,
    List<Element> elements,
  ) {
    final text = _boundText(rootNode, elements);
    final node = MindmapNode(text: text, sourceId: rootNode.id.value);
    for (final child in childrenOf(rootNode, elements)) {
      node.children.add(treeFromScene(child, elements));
    }
    return node;
  }

  /// Returns the text of the bound text element for [node], or empty string.
  static String _boundText(Element node, List<Element> elements) {
    for (final e in elements) {
      if (e.isDeleted) continue;
      if (e is! TextElement) continue;
      if (e.containerId == node.id.value) return e.text;
    }
    return '';
  }

  /// Finds the top-most mind-map root (a node with no mind-map parent) that
  /// contains [node] in its subtree. Returns [node] itself if it is a root.
  /// Used to reflow the whole tree starting from the root after an edit.
  static Element rootOf(Element node, List<Element> elements) {
    var current = node;
    while (true) {
      final parent = parentOf(current, elements);
      if (parent == null) return current;
      current = parent;
    }
  }

  static String? _role(Element e) {
    final cd = e.customData;
    if (cd == null) return null;
    final flowMuse = cd[MindmapLayout.nodeCustomData.keys.first];
    if (flowMuse is! Map<String, Object?>) return null;
    final role = flowMuse['role'];
    return role is String ? role : null;
  }
}
