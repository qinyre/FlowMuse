import '../gateways/smart_layout_editor_gateway.dart';
import 'scene_fingerprint.dart';

/// Scene 变更的一跳记录：单调 revision/epoch + 新 fingerprint。
class SceneRevision {
  const SceneRevision({
    required this.epoch,
    required this.revision,
    required this.fingerprint,
  });

  /// 场景血缘分界计数：reset/restore（整场景替换语义）时递增。
  final int epoch;

  /// 当前 epoch 内的内容变更单调计数；0 表示观察起点。
  final int revision;

  final SceneFingerprint fingerprint;

  bool get isInitial => revision == 0;

  @override
  bool operator ==(Object other) =>
      other is SceneRevision &&
      other.epoch == epoch &&
      other.revision == revision &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(epoch, revision, fingerprint.value);

  @override
  String toString() =>
      'SceneRevision(epoch: $epoch, revision: $revision, '
      'fingerprint: ${fingerprint.value})';
}

/// 从既有 editor change 边界观察 Scene 内容变化并推进 [SceneRevision]。
///
/// 接线（不改写 History/LWW/协作协议）：
/// - [SmartLayoutEditorGateway.addSceneChangeListener]：带源标签的变化
///   （userEdit/undo/redo/remoteApply/reset/restore）；
/// - [SmartLayoutEditorGateway.changes]（ChangeNotifier 兜底）：覆盖
///   loadScene/clear/applyScene 等只 notifyListeners、不发源标签的替换路径。
///
/// 递进规则：fingerprint 变化才递增 revision（视口/选择/同内容重放不递增）；
/// 源为 reset/restore 时同时递增 epoch；load/clear 经兜底路径只递增
/// revision（无源标签可辨，文档化为既定口径）。undo 回到旧内容同样递增
/// （revision 是变更计数，不是内容新颖度）。
/// Scene 不可变：同一实例的重复通知直接跳过，避免绘制/视口事件
/// 在 UI 线程上反复序列化整页，也避免内容通知与通用通知重复计算。
class SceneRevisionTracker {
  SceneRevisionTracker({required SmartLayoutEditorGateway editor})
    : _editor = editor,
      _observedScene = editor.currentScene,
      _current = SceneRevision(
        epoch: 0,
        revision: 0,
        fingerprint: SceneFingerprint.of(editor.currentScene),
      ) {
    editor.addSceneChangeListener(_onSceneChanged);
    editor.changes.addListener(_onNotified);
  }

  final SmartLayoutEditorGateway _editor;
  Scene? _observedScene;
  SceneRevision _current;
  bool _disposed = false;

  SceneRevision get current => _current;

  bool get isDisposed => _disposed;

  /// 停止观察；幂等。释放后 [current] 冻结在最后状态。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _editor.removeSceneChangeListener(_onSceneChanged);
    _editor.changes.removeListener(_onNotified);
    _observedScene = null;
  }

  void _onSceneChanged(Scene scene, SceneChangeSource source) {
    if (_disposed) return;
    _advance(
      scene,
      newEpoch:
          source == SceneChangeSource.reset ||
          source == SceneChangeSource.restore,
    );
  }

  void _onNotified() {
    if (_disposed) return;
    _advance(_editor.currentScene);
  }

  void _advance(Scene scene, {bool newEpoch = false}) {
    if (identical(scene, _observedScene)) return;
    final fingerprint = SceneFingerprint.of(scene);
    _observedScene = scene;
    if (fingerprint == _current.fingerprint) return;
    _current = SceneRevision(
      epoch: newEpoch ? _current.epoch + 1 : _current.epoch,
      revision: _current.revision + 1,
      fingerprint: fingerprint,
    );
  }
}
