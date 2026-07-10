import 'dart:math' as math;

/// 1€ Filter (Casiez et al., CHI 2012)：速度自适应低通滤波。
///
/// 低速强滤波抑制手抖，高速弱滤波减少延迟。单轴；位置 X/Y 各用一实例。
/// 参考: https://doi.org/10.1145/2207676.2208639
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double _prevValue = 0;
  double _prevDeriv = 0;
  Duration? _prevTime;

  /// 对 [value] 在时刻 [now] 滤波，返回滤波后的值。
  /// 当 dt <= 0（时间非单调）时旁路，直接返回 [value]。
  double filter(double value, Duration now) =>
      filterWithCutoff(value, now, overrideCutoff: null);

  /// 同 [filter]，但允许用 [overrideCutoff] 临时替换位置滤波的截止频率。
  ///
  /// 用于转角保护：复用本实例的状态（_prevValue/_prevDeriv/_prevTime 正常更新），
  /// 仅本帧用 overrideCutoff 代替 `minCutoff + beta*|deriv|`。传 null 等价于 [filter]。
  /// 这样转角帧结束后回到 [filter] 不会因状态断裂产生跳跃。
  double filterWithCutoff(double value, Duration now, {required double? overrideCutoff}) {
    final prev = _prevTime;
    if (prev == null) {
      _prevValue = value;
      _prevDeriv = 0;
      _prevTime = now;
      return value;
    }

    final dt = (now - prev).inMicroseconds / 1e6;
    if (dt <= 0) {
      // 时间非单调或零间隔：旁路，直接返回原始值并同步状态。
      _prevValue = value;
      _prevTime = now;
      return value;
    }

    final deriv = (value - _prevValue) / dt;
    final dAlpha = _alpha(dCutoff, dt);
    final filteredDeriv = _prevDeriv + dAlpha * (deriv - _prevDeriv);

    final cutoff = overrideCutoff ?? (minCutoff + beta * filteredDeriv.abs());
    final alpha = _alpha(cutoff, dt);
    final filteredValue = _prevValue + alpha * (value - _prevValue);

    _prevValue = filteredValue;
    _prevDeriv = filteredDeriv;
    _prevTime = now;
    return filteredValue;
  }

  void reset() {
    _prevValue = 0;
    _prevDeriv = 0;
    _prevTime = null;
  }

  // 低通系数 alpha，来自一阶低通的离散形式。
  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return dt / (tau + dt);
  }
}
