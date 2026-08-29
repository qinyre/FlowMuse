import 'package:flutter/foundation.dart';

import 'stroke_input_sample.dart';

/// Device-specific sampling policy. Rendering remains platform-neutral; only
/// the treatment of raw input differs between stylus, touch, and mouse.
class InputPolicy {
  const InputPolicy({
    required this.useRealPressure,
    required this.minCutoff,
    required this.beta,
    required this.pressureCutoff,
    this.pressureFloor = 0.0,
    this.pressureCeiling = 1.0,
    this.pressureAttackMs = 0,
    this.pressureAttackLevel = 0.0,
    required this.minDistance,
    required this.cornerProtectAngleRad,
  });

  final bool useRealPressure;
  final double minCutoff;
  final double beta;
  final double pressureCutoff;
  final double pressureFloor;
  final double pressureCeiling;

  /// 起笔攻击补偿窗口（毫秒）。真机手写笔起笔 0.5-1s 内压力从 ~0.2 爬升
  /// 到 ~0.5+（自然发力过程），如实渲染会让压感笔形前段过细、压力到位
  /// 瞬间整笔增宽（用户感知为"闪变"）。窗口内输出压力不低于从
  /// [pressureAttackLevel] 线性衰减到 [pressureFloor] 的包络；0 = 关闭。
  /// **窗口必须长于起笔压力爬升期**（实测 0.5-1.2s → 取 1500ms）：补偿
  /// 先于实测压力到位而撤退，会在每笔产生"粗起笔收窄成尖"的凹谷。
  final int pressureAttackMs;

  /// 攻击水位（映射域 [pressureFloor, pressureCeiling] 内的取值）。
  final double pressureAttackLevel;

  final double minDistance;
  final double cornerProtectAngleRad;

  /// Stylus input is smoothed once before reaching perfect_freehand. The high
  /// cutoff avoids visible lag while perfect_freehand supplies final contour
  /// smoothing. Pressure is compressed to prevent device spikes from becoming
  /// disproportionate width jumps.
  static const stylus = InputPolicy(
    useRealPressure: true,
    minCutoff: 8.0,
    beta: 0.02,
    pressureCutoff: 50.0,
    pressureFloor: 0.18,
    pressureCeiling: 0.82,
    pressureAttackMs: 1500,
    pressureAttackLevel: 0.50,
    minDistance: 0.6,
    cornerProtectAngleRad: 0.9,
  );

  /// Android pointer batches can be sparse during small, fast circles.
  /// Keep the corner bypass for only near-reversal turns on that platform.
  static const androidStylus = InputPolicy(
    useRealPressure: true,
    minCutoff: 8.0,
    beta: 0.02,
    pressureCutoff: 50.0,
    pressureFloor: 0.18,
    pressureCeiling: 0.82,
    pressureAttackMs: 1500,
    pressureAttackLevel: 0.50,
    minDistance: 0.6,
    cornerProtectAngleRad: 2.1,
  );

  static const touch = InputPolicy(
    useRealPressure: false,
    minCutoff: 1.2,
    beta: 0.005,
    pressureCutoff: 1.0,
    minDistance: 0.8,
    cornerProtectAngleRad: 0.9,
  );

  static const mouse = InputPolicy(
    useRealPressure: false,
    minCutoff: 1000,
    beta: 0.0,
    pressureCutoff: 1000,
    minDistance: 0.5,
    cornerProtectAngleRad: 0.6,
  );
}

class InputPolicySelector {
  const InputPolicySelector({TargetPlatform? platform}) : _platform = platform;

  final TargetPlatform? _platform;

  InputPolicy select(StrokeInputKind kind) {
    return switch (kind) {
      StrokeInputKind.stylus || StrokeInputKind.invertedStylus =>
        (_platform ?? defaultTargetPlatform) == TargetPlatform.android
            ? InputPolicy.androidStylus
            : InputPolicy.stylus,
      StrokeInputKind.touch => InputPolicy.touch,
      StrokeInputKind.mouse || StrokeInputKind.unknown => InputPolicy.mouse,
    };
  }
}
