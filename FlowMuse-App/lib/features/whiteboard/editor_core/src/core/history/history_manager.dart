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

  HistoryManager({this.maxDepth = 100});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

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
    return _undoStack.removeLast();
  }

  /// Redo: pop the last undone scene, push [current] to undo.
  /// Returns the restored scene, or null if nothing to redo.
  Scene? redo(Scene current) {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(current);
    return _redoStack.removeLast();
  }

  /// Clear all history.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
