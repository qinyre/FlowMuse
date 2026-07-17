/// A node in a mind-map tree.
///
/// This is the **content-only** representation used as the input to
/// [MindmapLayout] — it carries the textual structure (a topic and its
/// children) but **no geometry**. Coordinates, bindings and element ids are
/// produced deterministically by the layout algorithm.
///
/// This is also the shape that a future AI generator produces: the LLM only
/// emits this tree (topics + nesting), never coordinates or Excalidraw JSON.
class MindmapNode {
  MindmapNode({required this.text, List<MindmapNode>? children, this.sourceId})
    : children = children ?? [];

  /// The topic text shown inside the node.
  String text;

  /// Child sub-topics.
  final List<MindmapNode> children;

  /// The element id of the existing node rectangle this tree node was
  /// rebuilt from (via [MindmapUtils.treeFromScene]), or null when the tree
  /// comes from [MindmapNode.fromJson] (AI generation). The auto-reflow uses
  /// this to update existing elements in place instead of recreating them.
  final String? sourceId;

  /// Parses a tree from a plain JSON map, e.g. the output of an LLM.
  ///
  /// Accepted shapes (any of these keys, first hit wins):
  /// `{ "text": "...", "children": [...] }`
  /// `{ "topic": "...", "children": [...] }`
  /// `{ "title": "...", "children": [...] }`
  factory MindmapNode.fromJson(Map<String, Object?> json) {
    final text =
        (json['text'] ?? json['topic'] ?? json['title'] ?? '').toString();
    final rawChildren = json['children'];
    final children = <MindmapNode>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        if (item is Map<String, Object?>) {
          children.add(MindmapNode.fromJson(item));
        }
      }
    }
    return MindmapNode(text: text, children: children);
  }

  /// Serialises back to JSON (round-trips with [fromJson]). [sourceId] is
  /// intentionally omitted — it is runtime-only bookkeeping, not content.
  Map<String, Object?> toJson() => {
    'text': text,
    'children': children.map((c) => c.toJson()).toList(),
  };

  /// Total number of nodes in this subtree (including self).
  int get size => 1 + children.fold(0, (sum, c) => sum + c.size);

  @override
  String toString() => 'MindmapNode($text${children.isEmpty ? '' : ', ${children.length} children'})';
}
