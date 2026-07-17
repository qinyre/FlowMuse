import '../../core/elements/element.dart';
import '../../core/math/point.dart';
import '../tool_result.dart';
import 'mindmap_layout.dart';

/// Coordinates mind-map root creation.
///
/// Adding children/siblings is handled directly by [MarkdrawController] via
/// [MindmapLayout.reflowTree], because reflow needs to look up existing scene
/// elements to build [UpdateElementResult]s — that lookup belongs in the
/// controller, which owns the scene. This class therefore only owns the one
/// operation that has no reflow: creating the initial root.
///
/// `pendingElements` is retained (always empty in the immediate model) so the
/// same preview-rendering pipeline can be reused if preview-on-drag is added.
class MindmapCreator {
  final List<Element> _pendingElements = const [];

  bool get isCreating => false;

  /// Always empty in the immediate-commit model; kept for API compatibility
  /// with the preview-rendering pipeline.
  List<Element> get pendingElements => _pendingElements;

  /// Creates a root node centred at [center] and returns the commit result
  /// (add rect + text, select the rect).
  ToolResult createRoot(Point center) {
    final elements = MindmapLayout.createRootAt(center);
    final results = <ToolResult>[
      for (final e in elements) AddElementResult(e),
    ];
    results.add(SetSelectionResult({elements.first.id}));
    return CompoundResult(results);
  }

  /// No-op in the immediate model; kept for parity with FlowchartCreator.
  void clear() {}
}
