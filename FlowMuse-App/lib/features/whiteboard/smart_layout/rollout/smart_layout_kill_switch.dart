/// V3-700B：智能排版 v3 kill switch（合并原 V3-700B~D）。
///
/// 语义：本地信号关闭 v3 入口；**只关不换**——trip 后入口保持关闭，
/// 绝不提供也不触发任何 v2 回退路径（断网/配置故障同样只降为 off）。
/// 可观测告警（[SmartLayoutObservability]）达到阈值时经 [trip] 关闭。
library;

import 'smart_layout_capability.dart';

class SmartLayoutKillSwitch {
  SmartLayoutKillSwitch({this.maxTripCount = _unbounded});

  static const int _unbounded = -1;

  /// 最大连续 trip 次数（-1 不限）；达到后 [isLatched] 永久锁定，
  /// [reset] 不再生效（人工介入口径，V3-700A 生产包接收）。
  final int maxTripCount;

  String? _reason;
  int _tripCount = 0;
  bool _latched = false;

  /// 是否处于关闭态（trip 或锁定）。
  bool get isTripped => _reason != null || _latched;

  /// 当前关闭原因（null=未关闭）。
  String? get reason => _latched ? (_reason ?? 'latched') : _reason;

  bool get isLatched => _latched;

  int get tripCount => _tripCount;

  /// 关闭入口。已锁定或超次数时进入锁定态。
  void trip(String cause) {
    if (_latched) return;
    _reason = cause;
    _tripCount++;
    if (maxTripCount != _unbounded && _tripCount >= maxTripCount) {
      _latched = true;
    }
  }

  /// 解除（未锁定时可用；锁定后只能等生产批准包流程）。
  void reset() {
    if (_latched) return;
    _reason = null;
  }

  /// 组合判定：capability 阳性且 kill switch 未跳闸才放行。
  /// off 时调用方必须零请求（fail closed，不回退 v2）。
  SmartLayoutCapabilityDecision combine(SmartLayoutCapabilityDecision decision) {
    if (decision.enabled && isTripped) {
      return SmartLayoutCapabilityDecision(
        enabled: false,
        reason: decision.reason,
        expiresAtMs: decision.expiresAtMs,
      );
    }
    return decision;
  }
}
