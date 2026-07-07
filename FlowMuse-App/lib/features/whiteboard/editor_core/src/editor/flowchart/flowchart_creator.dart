import '../../core/elements/elements.dart';
import '../../core/scene/scene_exports.dart';
import '../tool_result.dart';
import 'flowchart_utils.dart';

/// Manages the stateful creation of flowchart nodes via Ctrl+Arrow.
///
/// Tracks pending (uncommitted) elements that are shown as a translucent
/// preview. Repeated presses in the same direction fan out additional nodes.
class FlowchartCreator {
  bool _isCreating = false;
  int _numberOfNodes = 0;
  LinkDirection? _direction;
  List<Element> _pendingElements = [];
  ElementId? _startNodeId;

  bool get isCreating => _isCreating;
  List<Element> get pendingElements => List.unmodifiable(_pendingElements);

  /// Create or add nodes from [startNode] in [direction].
  ///
  /// First call: creates 1 node + arrow. Same direction again: increments
  /// count and redistributes with fan-out. Different direction: resets and
  /// starts fresh.
  void createNodes({
    required Element startNode,
    required LinkDirection direction,
    required Scene scene,
  }) {
    if (_isCreating &&
        _direction == direction &&
        _startNodeId == startNode.id) {
      // Same direction — fan out more nodes
      _numberOfNodes += 1;
    } else {
      // New direction or first press
      _numberOfNodes = 1;
      _direction = direction;
      _startNodeId = startNode.id;
    }
    _isCreating = true;

    if (_numberOfNodes == 1) {
      _pendingElements = FlowchartUtils.createNodeAndArrow(
        startNode,
        direction,
        scene,
      );
    } else {
      _pendingElements = FlowchartUtils.createFannedNodes(
        startNode,
        direction,
        scene,
        _numberOfNodes,
      );
    }
  }

  /// Commit pending elements to the scene.
  ///
  /// Returns a CompoundResult containing AddElementResults for all pending
  /// elements, plus a SetSelectionResult selecting the first non-arrow element.
  ToolResult commit() {
    final results = <ToolResult>[];

    // Add all pending elements
    for (final e in _pendingElements) {
      results.add(AddElementResult(e));
    }

    // Select the first non-arrow (node) element
    final firstNode = _pendingElements
        .where((e) => e is! ArrowElement)
        .firstOrNull;
    if (firstNode != null) {
      results.add(SetSelectionResult({firstNode.id}));
    }

    final result = CompoundResult(results);
    clear();
    return result;
  }

  /// Reset all state, discarding pending elements.
  void clear() {
    _isCreating = false;
    _numberOfNodes = 0;
    _direction = null;
    _pendingElements = [];
    _startNodeId = null;
  }
}
