import 'package:flutter/foundation.dart';

import '../editor_core/flow_muse_whiteboard_editor.dart';

enum PressureCurvePreset {
  soft(0.72),
  standard(1.0),
  firm(1.35);

  const PressureCurvePreset(this.exponent);

  final double exponent;
}

@immutable
class EditorPreferences {
  EditorPreferences({
    this.defaultTool = ToolType.select,
    this.defaultBrush = BrushType.fountainPen,
    Map<BrushType, BrushState>? brushStates,
    this.pressureEnabled = true,
    this.pressureCurve = PressureCurvePreset.standard,
    this.palmRejectionEnabled = true,
    this.twoFingerZoomEnabled = true,
    this.singleFingerPanEnabled = true,
  }) : brushStates = Map.unmodifiable({
         ...BrushState.defaults,
         ...?brushStates,
       });

  final ToolType defaultTool;
  final BrushType defaultBrush;
  final Map<BrushType, BrushState> brushStates;
  final bool pressureEnabled;
  final PressureCurvePreset pressureCurve;
  final bool palmRejectionEnabled;
  final bool twoFingerZoomEnabled;
  final bool singleFingerPanEnabled;

  BrushState brushState(BrushType type) =>
      brushStates[type] ?? BrushState.defaults[type]!;

  EditorPreferences copyWith({
    ToolType? defaultTool,
    BrushType? defaultBrush,
    Map<BrushType, BrushState>? brushStates,
    bool? pressureEnabled,
    PressureCurvePreset? pressureCurve,
    bool? palmRejectionEnabled,
    bool? twoFingerZoomEnabled,
    bool? singleFingerPanEnabled,
  }) {
    return EditorPreferences(
      defaultTool: defaultTool ?? this.defaultTool,
      defaultBrush: defaultBrush ?? this.defaultBrush,
      brushStates: brushStates ?? this.brushStates,
      pressureEnabled: pressureEnabled ?? this.pressureEnabled,
      pressureCurve: pressureCurve ?? this.pressureCurve,
      palmRejectionEnabled: palmRejectionEnabled ?? this.palmRejectionEnabled,
      twoFingerZoomEnabled: twoFingerZoomEnabled ?? this.twoFingerZoomEnabled,
      singleFingerPanEnabled:
          singleFingerPanEnabled ?? this.singleFingerPanEnabled,
    );
  }

  Map<String, Object?> toJson() => {
    'defaultTool': defaultTool.name,
    'defaultBrush': defaultBrush.name,
    'brushStates': {
      for (final entry in brushStates.entries)
        entry.key.name: {
          'strokeColor': entry.value.strokeColor,
          'strokeWidth': entry.value.strokeWidth,
          'pressureSensitivity': entry.value.pressureSensitivity,
        },
    },
    'pressureEnabled': pressureEnabled,
    'pressureCurve': pressureCurve.name,
    'palmRejectionEnabled': palmRejectionEnabled,
    'twoFingerZoomEnabled': twoFingerZoomEnabled,
    'singleFingerPanEnabled': singleFingerPanEnabled,
  };

  factory EditorPreferences.fromJson(Map<String, Object?> json) {
    final states = <BrushType, BrushState>{};
    final rawStates = json['brushStates'];
    if (rawStates is Map) {
      for (final brush in BrushType.values) {
        final raw = rawStates[brush.name];
        if (raw is! Map) continue;
        final defaults = BrushState.defaults[brush]!;
        states[brush] = defaults.copyWith(
          strokeColor: raw['strokeColor'] is String
              ? raw['strokeColor'] as String
              : defaults.strokeColor,
          strokeWidth: _double(raw['strokeWidth']),
          pressureSensitivity: _double(
            raw['pressureSensitivity'],
          )?.clamp(0.0, 1.0),
        );
      }
    }

    return EditorPreferences(
      defaultTool: _enumByName(
        ToolType.values,
        json['defaultTool'],
        ToolType.select,
      ),
      defaultBrush: _enumByName(
        BrushType.values,
        json['defaultBrush'],
        BrushType.fountainPen,
      ),
      brushStates: states,
      pressureEnabled: _bool(json['pressureEnabled'], true),
      pressureCurve: _enumByName(
        PressureCurvePreset.values,
        json['pressureCurve'],
        PressureCurvePreset.standard,
      ),
      palmRejectionEnabled: _bool(json['palmRejectionEnabled'], true),
      twoFingerZoomEnabled: _bool(json['twoFingerZoomEnabled'], true),
      singleFingerPanEnabled: _bool(json['singleFingerPanEnabled'], true),
    );
  }
}

double? _double(Object? value) => value is num ? value.toDouble() : null;

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

T _enumByName<T extends Enum>(Iterable<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
