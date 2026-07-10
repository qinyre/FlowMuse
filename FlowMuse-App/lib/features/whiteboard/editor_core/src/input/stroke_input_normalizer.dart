// lib/features/whiteboard/editor_core/src/input/stroke_input_normalizer.dart
import 'package:flutter/gestures.dart';
import 'stroke_input_sample.dart';

/// 位于 EditorCanvas 的 Listener 边界：PointerEvent → StrokeInputSample。
/// 在 local logical-pixel 坐标完成（screenToScene 由 controller 在 modeler 之后做）。
class StrokeInputNormalizer {
  StrokeInputSample? normalize(PointerEvent e, {required StrokePhase phase}) {
    return StrokeInputSample(
      pointerId: e.pointer,
      x: e.localPosition.dx,
      y: e.localPosition.dy,
      time: e.timeStamp,
      pressure: _reliablePressure(e),
      kind: _mapKind(e.kind),
      phase: phase,
      source: StrokeSampleSource.actual,
    );
  }

  /// 仅设备确实提供可靠压感时返回非 null。
  /// mouse pressure 与无可靠范围的 touch pressure 一律视为 null。
  /// 使用 pressureMin/Max 归一化，吸收现有 `reliableStylusPressure()` 的算法。
  double? _reliablePressure(PointerEvent e) {
    switch (e.kind) {
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
        final range = e.pressureMax - e.pressureMin;
        if (range <= 0) {
          return e.pressure.clamp(0.0, 1.0);
        }
        return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.touch:
      case PointerDeviceKind.trackpad:
      case PointerDeviceKind.unknown:
      default:
        return null;
    }
  }

  StrokeInputKind _mapKind(PointerDeviceKind k) {
    switch (k) {
      case PointerDeviceKind.stylus: return StrokeInputKind.stylus;
      case PointerDeviceKind.invertedStylus: return StrokeInputKind.invertedStylus;
      case PointerDeviceKind.touch: return StrokeInputKind.touch;
      case PointerDeviceKind.mouse: return StrokeInputKind.mouse;
      default: return StrokeInputKind.unknown;
    }
  }
}
