// lib/features/whiteboard/editor_core/src/input/stroke_input_modeler.dart
import 'dart:math' as math;
import '../core/math/point.dart';
import 'one_euro_filter.dart';
import 'input_policy.dart';
import 'stroke_input_sample.dart';

enum StrokeModelDecision { emitted, dropped, reset }

class StrokeModelResult {
  final Point? point;
  final double? pressure;
  final StrokeModelDecision decision;
  final String? reason;

  const StrokeModelResult._({
    this.point,
    this.pressure,
    required this.decision,
    this.reason,
  });
  const StrokeModelResult.emitted(Point point, double? pressure)
    : point = point,
      pressure = pressure,
      decision = StrokeModelDecision.emitted,
      reason = null;
  const StrokeModelResult.dropped(String this.reason)
    : point = null,
      pressure = null,
      decision = StrokeModelDecision.dropped;
  const StrokeModelResult.reset({String? reason})
    : point = null,
      pressure = null,
      decision = StrokeModelDecision.reset,
      this.reason = reason;
}

/// 平台无关输入建模器：OneEuro 位置滤波 + 独立 pressure 滤波 + 转角保护 + 终点 flush。
///
/// 单个活动 stroke：down 获取 pointer 所有权，up/cancel 释放。无 Flutter 依赖。
class StrokeInputModeler {
  StrokeInputModeler(this.policy);

  static const _maxSamplingGap = Duration(milliseconds: 200);

  final InputPolicy policy;

  OneEuroFilter? _xFilter;
  OneEuroFilter? _yFilter;
  OneEuroFilter? _pressureFilter;

  int? _ownerPointerId;
  Point? _lastEmitted;
  double? _lastPressure; // 真实模式下沿用最后有效值
  Duration? _lastTime;
  Point? _lastDir; // 上一段方向向量（转角保护用）

  bool get _isActive => _ownerPointerId != null;

  StrokeModelResult process(StrokeInputSample sample) {
    if (_isActive && sample.phase == StrokePhase.down) {
      return const StrokeModelResult.dropped('stroke already active');
    }
    if (_isActive && sample.pointerId != _ownerPointerId) {
      return const StrokeModelResult.dropped('not owner');
    }
    switch (sample.phase) {
      case StrokePhase.down:
        _initialize(sample);
        return StrokeModelResult.emitted(
          Point(sample.x, sample.y),
          _pressureOut(sample.pressure),
        );
      case StrokePhase.move:
        return _move(sample);
      case StrokePhase.up:
        return _up(sample);
      case StrokePhase.cancel:
        reset(reason: 'cancel');
        return const StrokeModelResult.reset(reason: 'cancel');
    }
  }

  void reset({String? reason}) {
    _xFilter = null;
    _yFilter = null;
    _pressureFilter = null;
    _ownerPointerId = null;
    _lastEmitted = null;
    _lastPressure = null;
    _lastTime = null;
    _lastDir = null;
  }

  void _initialize(StrokeInputSample s) {
    _ownerPointerId = s.pointerId;
    _xFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _yFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _pressureFilter = OneEuroFilter(
      minCutoff: policy.pressureCutoff,
      beta: 0.0,
    );
    _lastEmitted = Point(s.x, s.y);
    _lastPressure = policy.useRealPressure ? s.pressure : null;
    _lastTime = s.time;
    _lastDir = null;
    // 种子滤波器：第一个 move 到达时已有状态，避免绕过滤波直出原始值。
    _xFilter!.filter(s.x, s.time);
    _yFilter!.filter(s.y, s.time);
  }

  StrokeModelResult _move(StrokeInputSample s) {
    if (!_isActive) {
      return const StrokeModelResult.dropped('not active');
    }
    final last = _lastEmitted;
    if (last == null) {
      // 防御：_isActive 为 true 但 _lastEmitted 为 null（理论上 _initialize 已设置）。
      // 按 down 处理：直接发射原始点并初始化滤波器状态。
      _initializeAfterGap(s);
      return StrokeModelResult.emitted(
        Point(s.x, s.y),
        _pressureOut(s.pressure),
      );
    }
    // 最小距离门限（相对上一个发射点）
    final raw = Point(s.x, s.y);
    final previousTime = _lastTime;
    final elapsedUs = previousTime == null
        ? 0
        : (s.time - previousTime).inMicroseconds;
    if (elapsedUs <= 0 || elapsedUs > _maxSamplingGap.inMicroseconds) {
      // 时间倒退或报点中断后直接发射原始点，并用它重新播种滤波状态。
      _xFilter!.filter(raw.x, s.time);
      _yFilter!.filter(raw.y, s.time);
      _lastEmitted = raw;
      _lastDir = null;
      final pressure = _pressureOut(s.pressure);
      _lastTime = s.time;
      return StrokeModelResult.emitted(raw, pressure);
    }
    if (raw.distanceTo(last) < policy.minDistance) {
      return const StrokeModelResult.dropped('minDistance');
    }
    final out = _filterPosition(
      s,
      raw,
      boostForCorner: _detectCornerBoost(raw, last),
    );
    _lastEmitted = out;
    _lastTime = s.time;
    return StrokeModelResult.emitted(out, _pressureOut(s.pressure));
  }

  void _initializeAfterGap(StrokeInputSample s) {
    _xFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _yFilter = OneEuroFilter(minCutoff: policy.minCutoff, beta: policy.beta);
    _pressureFilter = OneEuroFilter(
      minCutoff: policy.pressureCutoff,
      beta: 0.0,
    );
    _lastEmitted = Point(s.x, s.y);
    _lastTime = s.time;
    // 种子滤波器：下一个 move 到达时已有状态。
    _xFilter!.filter(s.x, s.time);
    _yFilter!.filter(s.y, s.time);
  }

  StrokeModelResult _up(StrokeInputSample s) {
    if (!_isActive) {
      return const StrokeModelResult.dropped('up without active stroke');
    }
    // 终点 flush：直接用真实抬笔点，不做低通截短。
    final real = Point(s.x, s.y);
    _lastTime = s.time;
    // 若真实终点已通过 move 进入点列，调用方负责去重（见 controller 改造）。
    final result = StrokeModelResult.emitted(real, _pressureOut(s.pressure));
    reset(reason: 'up');
    return result;
  }

  /// 位置滤波。转角保护通过 filterWithCutoff 复用主滤波器状态、仅临时提高 cutoff，
  /// 避免新建实例导致状态断裂（见 OneEuroFilter.filterWithCutoff 注释）。
  Point _filterPosition(
    StrokeInputSample s,
    Point raw, {
    required bool boostForCorner,
  }) {
    final override = boostForCorner ? policy.minCutoff * 8 : null;
    final fx = _xFilter!.filterWithCutoff(
      raw.x,
      s.time,
      overrideCutoff: override,
    );
    final fy = _yFilter!.filterWithCutoff(
      raw.y,
      s.time,
      overrideCutoff: override,
    );
    return Point(fx, fy);
  }

  bool _detectCornerBoost(Point raw, Point last) {
    final dir = raw - last;
    if (dir == Point.zero) return false;
    final prev = _lastDir;
    _lastDir = dir;
    if (prev == null || prev == Point.zero) return false;
    final angle = _absAngleBetween(prev, dir);
    return angle > policy.cornerProtectAngleRad;
  }

  /// 两方向向量的绝对夹角 [0, π]。只关心转弯幅度，不关心方向（故用 det.abs()）。
  double _absAngleBetween(Point a, Point b) {
    final dot = a.x * b.x + a.y * b.y;
    final det = a.x * b.y - a.y * b.x;
    return math.atan2(det.abs(), dot);
  }

  double? _pressureOut(double? raw) {
    if (!policy.useRealPressure) return null; // 模拟模式：始终 null，交 perfect_freehand
    if (raw != null) {
      _lastPressure = _pressureFilter!.filter(raw, _lastTime ?? Duration.zero);
    }
    return _lastPressure; // 偶发缺失沿用最后有效值
  }
}
