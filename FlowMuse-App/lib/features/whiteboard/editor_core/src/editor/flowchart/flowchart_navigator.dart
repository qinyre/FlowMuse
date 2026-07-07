import '../../core/elements/elements.dart';
import '../../core/scene/scene_exports.dart';
import 'flowchart_utils.dart';

/// Manages stateful navigation between connected flowchart nodes via Alt+Arrow.
///
/// Tracks visited nodes and cycles through same-level alternatives on repeated
/// presses in the same direction.
class FlowchartNavigator {
  bool _isExploring = false;
  LinkDirection? _direction;
  List<Element> _sameLevelNodes = [];
  int _sameLevelIndex = 0;
  final _visitedIds = <ElementId>{};

  bool get isExploring => _isExploring;

  /// Navigate from [element] in [direction].
  ///
  /// Returns the ElementId to select, or null if no connected node exists.
  ///
  /// Algorithm (matches Excalidraw's FlowChartNavigator.exploreByDirection):
  /// 1. Direction change -> clear all state
  /// 2. If already exploring same direction with multiple nodes -> cycle
  /// 3. Get linked nodes in direction -> if found, go to first
  /// 4. Fallback: check other 3 directions for unvisited nodes
  /// 5. Return null if dead end
  ElementId? exploreByDirection(
    Element element,
    Scene scene,
    LinkDirection direction,
  ) {
    // Direction change -> reset
    if (_isExploring && _direction != direction) {
      clear();
    }

    _isExploring = true;
    _visitedIds.add(element.id);

    // If we're already cycling through same-level nodes in this direction
    if (_direction == direction && _sameLevelNodes.length > 1) {
      _sameLevelIndex = (_sameLevelIndex + 1) % _sameLevelNodes.length;
      final target = _sameLevelNodes[_sameLevelIndex];
      _visitedIds.add(target.id);
      return target.id;
    }

    _direction = direction;

    // Try the requested direction
    final linked = FlowchartUtils.getLinkedNodesInDirection(
      scene,
      element,
      direction,
    );
    if (linked.isNotEmpty) {
      _sameLevelNodes = linked;
      _sameLevelIndex = 0;
      final target = linked.first;
      _visitedIds.add(target.id);
      return target.id;
    }

    // Fallback: check other 3 directions for unvisited nodes
    for (final fallbackDir in LinkDirection.values) {
      if (fallbackDir == direction) continue;
      final others = FlowchartUtils.getLinkedNodesInDirection(
        scene,
        element,
        fallbackDir,
      );
      final unvisited = others.where((e) => !_visitedIds.contains(e.id));
      if (unvisited.isNotEmpty) {
        final target = unvisited.first;
        _visitedIds.add(target.id);
        _sameLevelNodes = [];
        return target.id;
      }
    }

    return null; // dead end
  }

  /// Reset all navigation state.
  void clear() {
    _isExploring = false;
    _direction = null;
    _sameLevelNodes = [];
    _sameLevelIndex = 0;
    _visitedIds.clear();
  }
}
