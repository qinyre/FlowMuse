import '../snapshot/scene_revision.dart';

/// 一次智能排版操作的操作票据：continuation 四检的对照基准。
class SmartLayoutOperationTicket {
  const SmartLayoutOperationTicket({
    required this.operationId,
    required this.pageId,
    required this.baseRevision,
  });

  final String operationId;
  final String pageId;

  /// 操作开始时的 SceneRevision；远端/本地内容变化即失配。
  final SceneRevision baseRevision;
}

/// 守卫裁定。
sealed class SmartLayoutGuardDecision {
  const SmartLayoutGuardDecision();
}

class SmartLayoutGuardAllowed extends SmartLayoutGuardDecision {
  const SmartLayoutGuardAllowed();
}

class SmartLayoutGuardRejected extends SmartLayoutGuardDecision {
  const SmartLayoutGuardRejected(this.reason);

  final String reason;

  @override
  String toString() => 'SmartLayoutGuardRejected($reason)';
}

/// continuation 守卫的活真值来源（由 session 提供/更新）。
///
/// 四检+取消固定顺序：disposed → operation → cancel → page → revision。
/// 任一失配即拒绝——取消、离页、远端变化、迟到回调都不得污染新 session。
class SmartLayoutGuardTruth {
  const SmartLayoutGuardTruth({
    required this.isDisposed,
    required this.currentOperationId,
    required this.isOperationCancelled,
    required this.activePageId,
    required this.currentRevision,
  });

  final bool isDisposed;
  final String? currentOperationId;
  final bool isOperationCancelled;
  final String? activePageId;
  final SceneRevision? currentRevision;
}

/// 操作级四检守卫（V3-106A）：所有异步续作（分析回调、应用提交、
/// 迟到响应）在写入任何会话/Scene 状态前必须通过本守卫。
class SmartLayoutOperationGuard {
  const SmartLayoutOperationGuard();

  SmartLayoutGuardDecision check(
    SmartLayoutOperationTicket ticket,
    SmartLayoutGuardTruth truth,
  ) {
    if (truth.isDisposed) {
      return const SmartLayoutGuardRejected('disposed');
    }
    if (truth.currentOperationId == null ||
        ticket.operationId != truth.currentOperationId) {
      return SmartLayoutGuardRejected(
        'operation-mismatch(${ticket.operationId})',
      );
    }
    if (truth.isOperationCancelled) {
      return const SmartLayoutGuardRejected('cancelled');
    }
    if (truth.activePageId == null || ticket.pageId != truth.activePageId) {
      return SmartLayoutGuardRejected('page-changed(${ticket.pageId})');
    }
    final current = truth.currentRevision;
    if (current == null ||
        current.fingerprint != ticket.baseRevision.fingerprint) {
      return const SmartLayoutGuardRejected('revision-changed');
    }
    return const SmartLayoutGuardAllowed();
  }
}
