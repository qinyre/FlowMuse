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
    required this.minDistance,
    required this.cornerProtectAngleRad,
  });

  final bool useRealPressure;
  final double minCutoff;
  final double beta;
  final double pressureCutoff;
  final double pressureFloor;
  final double pressureCeiling;
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
    minDistance: 0.6,
    cornerProtectAngleRad: 0.9,
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
  const InputPolicySelector();

  InputPolicy select(StrokeInputKind kind) {
    return switch (kind) {
      StrokeInputKind.stylus ||
      StrokeInputKind.invertedStylus => InputPolicy.stylus,
      StrokeInputKind.touch => InputPolicy.touch,
      StrokeInputKind.mouse || StrokeInputKind.unknown => InputPolicy.mouse,
    };
  }
}
