import '../elements/elements.dart';
import '../scene/scene.dart';

/// Manages undo/redo history as a stack of [Scene] snapshots.
///
/// Push the current scene before each mutation. [undo] returns the previous
/// scene and moves the current one to the redo stack. [redo] reverses an undo.
/// New pushes clear the redo stack (branch divergence).
class HistoryManager {
  final int maxDepth;
  final List<Scene> _undoStack = [];
  final List<Scene> _redoStack = [];
  final Map<ElementId, Element> _remoteElements = {};
  final Map<String, ImageFile> _remoteFiles = {};

  HistoryManager({this.maxDepth = 100});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Retain remote winners without rewriting every snapshot on each ink update.
  void recordRemoteElements(Scene current, Iterable<Element> elements) {
    final currentById = {
      for (final element in current.elements) element.id: element,
    };
    for (final element in elements) {
      final previous = currentById[element.id];
      if (previous == null || _newerThan(element, previous)) {
        final recorded = _remoteElements[element.id];
        if (recorded == null || _newerThan(element, recorded)) {
          _remoteElements[element.id] = element;
        }
      }
    }
  }

  void recordRemoteFiles(Map<String, ImageFile> files) {
    _remoteFiles.addAll(files);
  }

  bool _newerThan(Element incoming, Element previous) =>
      incoming.version > previous.version ||
      (incoming.version == previous.version &&
          incoming.versionNonce < previous.versionNonce);

  Scene _withRemoteChanges(Scene scene) {
    final byId = {for (final element in scene.elements) element.id: element};
    var result = scene.upsertRemoteElements([
      for (final remote in _remoteElements.values)
        if (byId[remote.id] == null || _newerThan(remote, byId[remote.id]!))
          remote,
    ]);
    for (final entry in _remoteFiles.entries) {
      result = result.addFile(entry.key, entry.value);
    }
    return result;
  }

  /// Save [scene] (the state before a mutation) to the undo stack.
  /// Clears the redo stack.
  void push(Scene scene) {
    _undoStack.add(scene);
    if (_undoStack.length > maxDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Undo: pop the last saved scene, push [current] to redo.
  /// Returns the restored scene, or null if nothing to undo.
  Scene? undo(Scene current) {
    if (_undoStack.isEmpty) return null;
    _redoStack.add(current);
    return _withRemoteChanges(_undoStack.removeLast());
  }

  /// Redo: pop the last undone scene, push [current] to undo.
  /// Returns the restored scene, or null if nothing to redo.
  Scene? redo(Scene current) {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(current);
    return _withRemoteChanges(_redoStack.removeLast());
  }

  /// Clear all history.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _remoteElements.clear();
    _remoteFiles.clear();
  }
}
