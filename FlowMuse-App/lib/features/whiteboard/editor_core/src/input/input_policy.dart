// lib/features/whiteboard/editor_core/src/input/input_policy.dart
import 'stroke_input_sample.dart';

/// 单一输入设备的滤波策略。最终渲染算法各端一致，仅输入策略不同。
class InputPolicy {
  const InputPolicy({
    required this.useRealPressure,
    required this.minCutoff,
    required this.beta,
    required this.pressureCutoff,
    required this.minDistance,
    required this.cornerProtectAngleRad,
  });

  /// 本笔是否使用真实压感（down 时锁定）。
  final bool useRealPressure;
  final double minCutoff;
  final double beta;
  final double pressureCutoff;
  /// 最小移动距离门限，低于此距离的 move 被丢弃（去重）。
  final double minDistance;
  /// 转角保护阈值：方向夹角超过此值时临时提高响应速度（弧度）。
  final double cornerProtectAngleRad;

  /// 手写笔：真实压感 + 自适应位置/压感滤波。
  static const stylus = InputPolicy(
    useRealPressure: true,
    minCutoff: 1.0, beta: 0.007,
    pressureCutoff: 1.0,
    minDistance: 0.6,
    cornerProtectAngleRad: 0.9, // ~51°
  );

  /// 手指（未来启用 finger drawing 时）：模拟压感 + 较保守滤波。
  static const touch = InputPolicy(
    useRealPressure: false,
    minCutoff: 1.2, beta: 0.005,
    pressureCutoff: 1.0,
    minDistance: 0.8,
    cornerProtectAngleRad: 0.9,
  );

  /// 鼠标：默认不强滤波，只去重 + 最小距离，避免直线操作拖尾。
  static const mouse = InputPolicy(
    useRealPressure: false,
    minCutoff: 1000, beta: 0.0, // 极高 cutoff ≈ 几乎不滤波
    pressureCutoff: 1000,
    minDistance: 0.5,
    cornerProtectAngleRad: 0.6,
  );
}

class InputPolicySelector {
  const InputPolicySelector();
  InputPolicy select(StrokeInputKind kind) {
    switch (kind) {
      case StrokeInputKind.stylus:
      case StrokeInputKind.invertedStylus:
        return InputPolicy.stylus;
      case StrokeInputKind.touch:
        return InputPolicy.touch;
      case StrokeInputKind.mouse:
        return InputPolicy.mouse;
      case StrokeInputKind.unknown:
        return InputPolicy.mouse; // 未知设备走保守路线
    }
  }
}
