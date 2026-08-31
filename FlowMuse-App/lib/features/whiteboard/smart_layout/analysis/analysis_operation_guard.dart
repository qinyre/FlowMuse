import '../session/smart_layout_operation_guard.dart';
import '../session/smart_layout_session.dart';

/// 分析操作的 continuation 守卫（V3-203A）：把 V3-106A 的
/// operation/page/revision/disposed 四检复用为仓库侧统一入口。
///
/// 发送前与每次重试/响应落地前各检一次——迟到响应、取消、离页、
/// 远端内容变化都不得写入新 session 状态。
class AnalysisOperationGuard {
  const AnalysisOperationGuard();

  /// 通过返回 null；否则返回守卫拒绝原因。
  String? check(SmartLayoutSession session, SmartLayoutOperationTicket ticket) {
    final decision = session.checkContinuation(ticket);
    return switch (decision) {
      SmartLayoutGuardAllowed() => null,
      SmartLayoutGuardRejected(:final reason) => reason,
    };
  }
}
