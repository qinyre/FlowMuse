/// 会话阶段（sealed 状态机的相位维度）。
enum SmartLayoutSessionPhase {
  idle,
  analyzing,
  reviewing,
  applying,
  applied,
  cancelled,
  failed,
}

/// 会话事件种类。
enum SmartLayoutSessionEventKind {
  analysisStarted,
  analysisSucceeded,
  analysisFailed,
  candidateChosen,
  applySucceeded,
  applyFailed,
  cancelRequested,
  sessionReset,
}

/// 智能排版会话状态（sealed；迁移只经 [SmartLayoutSessionReducer]）。
sealed class SmartLayoutSessionState {
  const SmartLayoutSessionState({
    required this.phase,
    required this.operationId,
  });

  final SmartLayoutSessionPhase phase;

  /// 空闲态为 null；进入 analyzing 后固定为当次操作 id。
  final String? operationId;
}

class SessionIdle extends SmartLayoutSessionState {
  const SessionIdle()
    : super(phase: SmartLayoutSessionPhase.idle, operationId: null);
}

class SessionAnalyzing extends SmartLayoutSessionState {
  const SessionAnalyzing({required String operationId})
    : super(phase: SmartLayoutSessionPhase.analyzing, operationId: operationId);
}

class SessionReviewing extends SmartLayoutSessionState {
  const SessionReviewing({
    required String operationId,
    required this.candidateCount,
  }) : super(
         phase: SmartLayoutSessionPhase.reviewing,
         operationId: operationId,
       );

  final int candidateCount;
}

class SessionApplying extends SmartLayoutSessionState {
  const SessionApplying({
    required String operationId,
    required this.candidateId,
  }) : super(phase: SmartLayoutSessionPhase.applying, operationId: operationId);

  final String candidateId;
}

class SessionApplied extends SmartLayoutSessionState {
  const SessionApplied({required String operationId, required this.candidateId})
    : super(phase: SmartLayoutSessionPhase.applied, operationId: operationId);

  final String candidateId;
}

class SessionCancelled extends SmartLayoutSessionState {
  const SessionCancelled({required String operationId, required this.reason})
    : super(phase: SmartLayoutSessionPhase.cancelled, operationId: operationId);

  final String reason;
}

class SessionFailed extends SmartLayoutSessionState {
  const SessionFailed({required String operationId, required this.reason})
    : super(phase: SmartLayoutSessionPhase.failed, operationId: operationId);

  final String reason;
}

/// 会话事件（携带迁移所需最小负载）。
class SmartLayoutSessionEvent {
  const SmartLayoutSessionEvent(
    this.kind, {
    this.operationId,
    this.candidateCount,
    this.candidateId,
    this.reason,
  });

  final SmartLayoutSessionEventKind kind;

  /// analysisStarted 必带（由 session 分配）。
  final String? operationId;
  final int? candidateCount;
  final String? candidateId;
  final String? reason;
}

/// 非法迁移：在产生任何新状态（副作用）之前抛出。
class SmartLayoutSessionInvalidTransition implements Exception {
  const SmartLayoutSessionInvalidTransition(this.phase, this.kind);

  final SmartLayoutSessionPhase phase;
  final SmartLayoutSessionEventKind kind;

  @override
  String toString() => 'SmartLayoutSessionInvalidTransition($phase, $kind)';
}

/// 纯 reducer：唯一合法迁移表。
///
/// idle→analyzing→(reviewing→applying→applied | …)→终态→(reset→idle)；
/// cancel 在 analyzing/reviewing/applying 合法；applied/cancelled/failed
/// 只能 reset。其余组合一律 [SmartLayoutSessionInvalidTransition]。
class SmartLayoutSessionReducer {
  const SmartLayoutSessionReducer();

  SmartLayoutSessionState reduce(
    SmartLayoutSessionState state,
    SmartLayoutSessionEvent event,
  ) {
    final allowed = _transitions[state.phase];
    if (allowed == null || !allowed.contains(event.kind)) {
      throw SmartLayoutSessionInvalidTransition(state.phase, event.kind);
    }
    final operationId = state.operationId;
    return switch (event.kind) {
      SmartLayoutSessionEventKind.analysisStarted => SessionAnalyzing(
        operationId:
            event.operationId ??
            (throw ArgumentError('analysisStarted 必带 operationId')),
      ),
      SmartLayoutSessionEventKind.analysisSucceeded => SessionReviewing(
        operationId: operationId!,
        candidateCount: event.candidateCount ?? 0,
      ),
      SmartLayoutSessionEventKind.analysisFailed => SessionFailed(
        operationId: operationId!,
        reason: event.reason ?? 'analysis-failed',
      ),
      SmartLayoutSessionEventKind.candidateChosen => SessionApplying(
        operationId: operationId!,
        candidateId: event.candidateId ?? '',
      ),
      SmartLayoutSessionEventKind.applySucceeded => SessionApplied(
        operationId: operationId!,
        candidateId: event.candidateId ?? '',
      ),
      SmartLayoutSessionEventKind.applyFailed => SessionFailed(
        operationId: operationId!,
        reason: event.reason ?? 'apply-failed',
      ),
      SmartLayoutSessionEventKind.cancelRequested => SessionCancelled(
        operationId: operationId!,
        reason: event.reason ?? 'cancelled',
      ),
      SmartLayoutSessionEventKind.sessionReset => const SessionIdle(),
    };
  }
}

const Map<SmartLayoutSessionPhase, Set<SmartLayoutSessionEventKind>>
_transitions = {
  SmartLayoutSessionPhase.idle: {SmartLayoutSessionEventKind.analysisStarted},
  SmartLayoutSessionPhase.analyzing: {
    SmartLayoutSessionEventKind.analysisSucceeded,
    SmartLayoutSessionEventKind.analysisFailed,
    SmartLayoutSessionEventKind.cancelRequested,
  },
  SmartLayoutSessionPhase.reviewing: {
    SmartLayoutSessionEventKind.candidateChosen,
    SmartLayoutSessionEventKind.cancelRequested,
  },
  SmartLayoutSessionPhase.applying: {
    SmartLayoutSessionEventKind.applySucceeded,
    SmartLayoutSessionEventKind.applyFailed,
    SmartLayoutSessionEventKind.cancelRequested,
  },
  SmartLayoutSessionPhase.applied: {SmartLayoutSessionEventKind.sessionReset},
  SmartLayoutSessionPhase.cancelled: {SmartLayoutSessionEventKind.sessionReset},
  SmartLayoutSessionPhase.failed: {SmartLayoutSessionEventKind.sessionReset},
};
