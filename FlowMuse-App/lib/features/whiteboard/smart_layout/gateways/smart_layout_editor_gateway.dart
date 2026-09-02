import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/foundation.dart' show Listenable;

export 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show Scene, SceneChangeSource, DocumentFormat, ToolResult;

/// 智能排版 v3 订阅场景变化的监听器；与 [MarkdrawController.onSceneChanged]
/// 的单槽回调语义一致，但支持多方订阅。
typedef SmartLayoutSceneChangeListener =
    void Function(Scene scene, SceneChangeSource source);

/// 智能排版 v3 对既有编辑器的唯一入口：窄接口薄封装
/// [MarkdrawController]，只暴露快照、变化观察、草稿基线与已验证提交；
/// 不引入注册表、通用 editor 抽象或第二套 Scene 状态。
class SmartLayoutEditorGateway {
  SmartLayoutEditorGateway(this._controller);

  final MarkdrawController _controller;

  /// 当前权威 Scene（不可变实例，直接持有即快照）。
  Scene get currentScene => _controller.currentScene;

  /// 编辑器是否已释放；释放后提交等副作用必须失败。
  bool get isDisposed => _controller.isDisposed;

  /// 编辑器通知流（视口/选择等非内容变化也会触发）；
  /// 内容级变化请订阅 [addSceneChangeListener]。
  Listenable get changes => _controller;

  /// 序列化当前 Scene，用于快照 fingerprint 与证据留档。
  String serializeScene({
    DocumentFormat format = DocumentFormat.markdraw,
    bool includeDeleted = false,
  }) => _controller.serializeScene(
    format: format,
    includeDeleted: includeDeleted,
  );

  /// 捕获草稿基线：[Scene] 不可变，返回引用即安全快照。
  Scene captureDraftBase() {
    _throwIfDisposed();
    return _controller.currentScene;
  }

  /// 订阅内容级场景变化（本地编辑/undo/redo/重置/远端应用）。
  void addSceneChangeListener(SmartLayoutSceneChangeListener listener) =>
      _controller.sceneChangeListeners.add(listener);

  /// 取消订阅；不存在的监听器为 no-op。
  void removeSceneChangeListener(SmartLayoutSceneChangeListener listener) =>
      _controller.sceneChangeListeners.remove(listener);

  /// 提交一个已通过校验的结果：先保存 undo 快照再应用，
  /// 与 v2 commitSmartLayoutDraft 的落地顺序一致。
  void commitValidated(ToolResult result) {
    _throwIfDisposed();
    _controller.pushHistory();
    _controller.applyResult(result);
  }

  void _throwIfDisposed() {
    if (isDisposed) {
      throw StateError('编辑器已释放');
    }
  }
}
