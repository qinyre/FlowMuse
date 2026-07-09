import 'dart:ui';

double? reliableStylusPressure({
  required PointerDeviceKind kind,
  required double pressure,
  required double pressureMin,
  required double pressureMax,
}) {
  if (kind != PointerDeviceKind.stylus &&
      kind != PointerDeviceKind.invertedStylus) {
    return null;
  }

  final range = pressureMax - pressureMin;
  if (range <= 0) {
    return pressure.clamp(0.0, 1.0);
  }
  return ((pressure - pressureMin) / range).clamp(0.0, 1.0);
}
