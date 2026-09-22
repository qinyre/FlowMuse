import 'dart:async';

import '../models/excalidraw_scene.dart';
import 'scene_reconciler.dart';

typedef ChangeBatchCallback =
    Future<void> Function(List<Map<String, Object?>> elements, bool isInitial);

class ChangeAccumulator {
  ChangeAccumulator({
    Duration batchWindow = const Duration(milliseconds: 16),
    SceneReconciler? reconciler,
  }) : _batchWindow = batchWindow,
       _reconciler = reconciler ?? SceneReconciler();

  final Duration _batchWindow;
  final SceneReconciler _reconciler;
  Timer? _timer;
  final Map<String, Map<String, Object?>> _pending = {};
  bool _hasInitial = false;
  bool _flushing = false;
  int _generation = 0;

  ChangeBatchCallback? onFlush;

  /// 调度一批元素。
  /// [bypass] 为 true 时跳过批处理立即发送；[isInitial] 仅当 bypass 时生效，决定消息类型。
  void schedule(
    ExcalidrawScene scene, {
    bool bypass = false,
    bool isInitial = false,
  }) {
    if (bypass) {
      _timer?.cancel();
      _timer = null;
      final syncable = _reconciler.getSyncableElements(scene.elements);
      _pending.clear();
      _hasInitial = false;
      onFlush?.call(syncable, isInitial);
      return;
    }

    scheduleElements(scene.elements);
  }

  void scheduleElements(List<Map<String, Object?>> elements) {
    for (final element in elements) {
      final id = element['id'] as String;
      final existing = _pending[id];
      if (_shouldReplace(existing, element)) {
        _pending[id] = Map<String, Object?>.from(element);
      }
    }

    // A batch has a deadline. Debouncing here starves continuous edits.
    _timer ??= Timer(_batchWindow, _flush);
  }

  /// 对齐 SceneReconciler._shouldKeepLocal: version 高的赢，
  /// version 相同时 nonce 小的赢（见 scene_reconciler.dart:95-98）。
  bool _shouldReplace(
    Map<String, Object?>? existing,
    Map<String, Object?> incoming,
  ) {
    if (existing == null) return true;
    final existingVersion = (existing['version'] as num).toInt();
    final incomingVersion = (incoming['version'] as num).toInt();
    if (incomingVersion > existingVersion) return true;
    if (incomingVersion < existingVersion) return false;
    // version 相同 → nonce 小的赢
    final existingNonce = (existing['versionNonce'] as num).toInt();
    final incomingNonce = (incoming['versionNonce'] as num).toInt();
    return incomingNonce < existingNonce;
  }

  Future<void> _flush() async {
    _timer = null;
    // Keep coalescing while the previous batch waits for encryption/send.
    if (_flushing) return;
    if (_pending.isEmpty && !_hasInitial) return;

    final generation = _generation;
    final elements = _reconciler.getSyncableElements(_pending.values.toList());
    final isInitial = _hasInitial;
    _pending.clear();
    _hasInitial = false;
    _flushing = true;
    try {
      await onFlush?.call(elements, isInitial);
    } finally {
      if (generation == _generation) {
        _flushing = false;
        // An expired window drains now; a future deadline stays in place.
        if (_timer == null && _pending.isNotEmpty) unawaited(_flush());
      }
    }
  }

  void dispose() {
    _generation++;
    _flushing = false;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
