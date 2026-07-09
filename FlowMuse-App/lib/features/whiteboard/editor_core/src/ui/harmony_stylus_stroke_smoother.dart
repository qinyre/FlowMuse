import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../core/math/point.dart';
import '../editor/tool_type.dart';

class HarmonyStylusStrokeSample {
  const HarmonyStylusStrokeSample({
    required this.point,
    required this.pressure,
    required this.isSmoothed,
  });

  final Point point;
  final double? pressure;
  final bool isSmoothed;
}

class HarmonyStylusStrokeSmoother {
  HarmonyStylusStrokeSmoother({
    this.minDistance = 0.6,
    this.positionAlpha = 0.35,
    this.pressureAlpha = 0.45,
  });

  final double minDistance;
  final double positionAlpha;
  final double pressureAlpha;

  Point? _lastPoint;
  double? _lastPressure;
  bool _active = false;

  HarmonyStylusStrokeSample? down({
    required Point point,
    required double? pressure,
    required TargetPlatform platform,
    required PointerDeviceKind kind,
    required ToolType activeToolType,
  }) {
    _active = _shouldSmooth(
      platform: platform,
      kind: kind,
      activeToolType: activeToolType,
    );
    _lastPoint = point;
    _lastPressure = pressure;
    return HarmonyStylusStrokeSample(
      point: point,
      pressure: pressure,
      isSmoothed: _active,
    );
  }

  HarmonyStylusStrokeSample? move({
    required Point point,
    required double? pressure,
    required TargetPlatform platform,
    required PointerDeviceKind kind,
    required ToolType activeToolType,
  }) {
    if (!_shouldSmooth(
      platform: platform,
      kind: kind,
      activeToolType: activeToolType,
    )) {
      return HarmonyStylusStrokeSample(
        point: point,
        pressure: pressure,
        isSmoothed: false,
      );
    }
    return _emitSmoothed(point: point, pressure: pressure);
  }

  HarmonyStylusStrokeSample? up({
    required Point point,
    required double? pressure,
    required TargetPlatform platform,
    required PointerDeviceKind kind,
    required ToolType activeToolType,
  }) {
    if (!_shouldSmooth(
      platform: platform,
      kind: kind,
      activeToolType: activeToolType,
    )) {
      reset();
      return HarmonyStylusStrokeSample(
        point: point,
        pressure: pressure,
        isSmoothed: false,
      );
    }

    final smoothedPressure = _smoothPressure(pressure);
    reset();
    return HarmonyStylusStrokeSample(
      point: point,
      pressure: smoothedPressure,
      isSmoothed: true,
    );
  }

  void reset() {
    _lastPoint = null;
    _lastPressure = null;
    _active = false;
  }

  HarmonyStylusStrokeSample? _emitSmoothed({
    required Point point,
    required double? pressure,
  }) {
    if (!_active) {
      _lastPoint = point;
      _lastPressure = pressure;
      return HarmonyStylusStrokeSample(
        point: point,
        pressure: pressure,
        isSmoothed: false,
      );
    }

    final lastPoint = _lastPoint;
    if (lastPoint == null) {
      _lastPoint = point;
      _lastPressure = pressure;
      return HarmonyStylusStrokeSample(
        point: point,
        pressure: pressure,
        isSmoothed: true,
      );
    }

    if (point.distanceTo(lastPoint) < minDistance) {
      return null;
    }

    final smoothedPoint = Point(
      lastPoint.x + (point.x - lastPoint.x) * positionAlpha,
      lastPoint.y + (point.y - lastPoint.y) * positionAlpha,
    );
    final smoothedPressure = _smoothPressure(pressure);
    _lastPoint = smoothedPoint;
    _lastPressure = smoothedPressure;
    return HarmonyStylusStrokeSample(
      point: smoothedPoint,
      pressure: smoothedPressure,
      isSmoothed: true,
    );
  }

  double? _smoothPressure(double? pressure) {
    final lastPressure = _lastPressure;
    if (pressure == null) {
      return lastPressure;
    }
    if (lastPressure == null) {
      return pressure;
    }
    return lastPressure + (pressure - lastPressure) * pressureAlpha;
  }

  bool _shouldSmooth({
    required TargetPlatform platform,
    required PointerDeviceKind kind,
    required ToolType activeToolType,
  }) {
    return platform == TargetPlatform.ohos &&
        (kind == PointerDeviceKind.stylus ||
            kind == PointerDeviceKind.invertedStylus) &&
        activeToolType == ToolType.freedraw;
  }
}
