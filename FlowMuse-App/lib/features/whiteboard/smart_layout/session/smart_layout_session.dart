import '../gateways/smart_layout_editor_gateway.dart';
import '../snapshot/scene_revision.dart';
import 'smart_layout_operation_guard.dart';
import 'smart_layout_session_state.dart';

/// 智能排版会话门面：reducer（状态）+ guard（四检）+ editor gateway
///（提交）的唯一接线点。
///
/// 关键安全性质：对外不暴露任何绕过守卫的 Scene 写入——
/// [completeApply] 是唯一提交入口，先四检后 [SmartLayoutEditorGateway.commitValidated]；
/// [advance] 只做纯状态迁移，非法迁移在副作用前抛出。
class SmartLayoutSession {
  SmartLayoutSession({
    required SmartLayoutEditorGateway editor,
    required SceneRevisionTracker revisions,
    required String pageId,
    SmartLayoutSessionReducer reducer = const SmartLayoutSessionReducer(),
    SmartLayoutOperationGuard guard = const SmartLayoutOperationGuard(),
  }) : _editor = editor,
       _revisions = revisions,
       _activePageId = pageId,
       _reducer = reducer,
       _guard = guard;

  final SmartLayoutEditorGateway _editor;
  final SceneRevisionTracker _revisions;
  final SmartLayoutSessionReducer _reducer;
  final SmartLayoutOperationGuard _guard;

  SmartLayoutSessionState _state = const SessionIdle();
  String? _activeOperationId;
  bool _operationCancelled = false;
  String? _activePageId;
  int _operationCounter = 0;

  SmartLayoutSessionState get state => _state;
  String? get activeOperationId => _activeOperationId;
  String? get activePageId => _activePageId;

  /// 用户切换页面（离页防线：旧票据续作被拒）。
  void setActivePage(String pageId) {
    _activePageId = pageId;
  }

  /// 开始一次分析操作：idle→analyzing，签发操作票据。
  SmartLayoutOperationTicket beginOperation() {
    _state = _reducer.reduce(
      _state,
      SmartLayoutSessionEvent(
        SmartLayoutSessionEventKind.analysisStarted,
        operationId: 'op-${++_operationCounter}',
      ),
    );
    _activeOperationId = _state.operationId;
    _operationCancelled = false;
    return SmartLayoutOperationTicket(
      operationId: _activeOperationId!,
      pageId: _activePageId!,
      baseRevision: _revisions.current,
    );
  }

  /// 当前活真值（守卫输入）。
  SmartLayoutGuardTruth currentTruth() => SmartLayoutGuardTruth(
    isDisposed: _editor.isDisposed,
    currentOperationId: _activeOperationId,
    isOperationCancelled: _operationCancelled,
    activePageId: _activePageId,
    currentRevision: _revisions.isDisposed ? null : _revisions.current,
  );

  /// continuation 四检入口。
  SmartLayoutGuardDecision checkContinuation(
    SmartLayoutOperationTicket ticket,
  ) => _guard.check(ticket, currentTruth());

  /// 纯状态迁移（无 Scene 副作用）；非法迁移抛
  /// [SmartLayoutSessionInvalidTransition]，当前状态不被污染。
  void advance(SmartLayoutSessionEvent event) {
    _state = _reducer.reduce(_state, event);
  }

  /// 取消当次操作（幂等；对已终态操作为 no-op 迁移失败外的软路径）。
  void cancelOperation({String reason = 'cancelled'}) {
    if (_state.phase == SmartLayoutSessionPhase.analyzing ||
        _state.phase == SmartLayoutSessionPhase.reviewing ||
        _state.phase == SmartLayoutSessionPhase.applying) {
      _operationCancelled = true;
      _state = _reducer.reduce(
        _state,
        SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.cancelRequested,
          reason: reason,
        ),
      );
    }
  }

  /// 终态复位到 idle（新会话入口）。
  void reset() {
    _state = _reducer.reduce(
      _state,
      const SmartLayoutSessionEvent(SmartLayoutSessionEventKind.sessionReset),
    );
    _activeOperationId = null;
    _operationCancelled = false;
  }

  /// 唯一提交入口：四检 → reducer（applying→applied）→ editor commit。
  ///
  /// 返回被拒原因时不产生任何 Scene/History 副作用；
  /// 先 chosen（reviewing→applying）再本方法，或对 reviewing 态直接
  /// chosen+apply 组合调用。
  SmartLayoutGuardDecision completeApply(
    SmartLayoutOperationTicket ticket, {
    required String candidateId,
    required ToolResult result,
  }) {
    if (_state.phase == SmartLayoutSessionPhase.reviewing) {
      advance(
        SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.candidateChosen,
          candidateId: candidateId,
        ),
      );
    }
    if (_state.phase != SmartLayoutSessionPhase.applying) {
      return const SmartLayoutGuardRejected('session-not-applying');
    }
    final decision = checkContinuation(ticket);
    if (decision is SmartLayoutGuardRejected) {
      // 门禁失败：状态回 failed，Scene 零副作用。
      advance(
        SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.applyFailed,
          reason: decision.reason,
        ),
      );
      return decision;
    }
    _editor.commitValidated(result);
    advance(
      SmartLayoutSessionEvent(
        SmartLayoutSessionEventKind.applySucceeded,
        candidateId: candidateId,
      ),
    );
    return const SmartLayoutGuardAllowed();
  }
}
