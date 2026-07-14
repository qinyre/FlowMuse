import 'package:flutter/foundation.dart';

import '../editor_core/flow_muse_whiteboard_editor.dart';

enum PressureCurvePreset {
  soft(0.72),
  standard(1.0),
  firm(1.35);

  const PressureCurvePreset(this.exponent);

  final double exponent;
}

/// Auto-save debounce interval for local drafts. `off` disables the
/// debounce timer — drafts are only flushed on exit/lifecycle pause.
enum AutosaveInterval {
  halfSecond(Duration(milliseconds: 500)),
  oneSecond(Duration(seconds: 1)),
  threeSeconds(Duration(seconds: 3)),
  fiveSeconds(Duration(seconds: 5)),
  off(null);

  const AutosaveInterval(this.duration);

  /// The debounce duration, or null when auto-save is disabled.
  final Duration? duration;
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
    this.autosaveInterval = AutosaveInterval.halfSecond,
    this.defaultLayoutType = CanvasLayoutType.paged,
    this.defaultPageTemplate = CanvasPageTemplate.blank,
    this.defaultPageFlow = CanvasPageFlow.topToBottom,
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

  /// Local-draft auto-save debounce interval.
  final AutosaveInterval autosaveInterval;
  final CanvasLayoutType defaultLayoutType;
  final CanvasPageTemplate defaultPageTemplate;
  final CanvasPageFlow defaultPageFlow;

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
    AutosaveInterval? autosaveInterval,
    CanvasLayoutType? defaultLayoutType,
    CanvasPageTemplate? defaultPageTemplate,
    CanvasPageFlow? defaultPageFlow,
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
      autosaveInterval: autosaveInterval ?? this.autosaveInterval,
      defaultLayoutType: defaultLayoutType ?? this.defaultLayoutType,
      defaultPageTemplate: defaultPageTemplate ?? this.defaultPageTemplate,
      defaultPageFlow: defaultPageFlow ?? this.defaultPageFlow,
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
    'autosaveInterval': autosaveInterval.name,
    'defaultLayoutType': defaultLayoutType.name,
    'defaultPageTemplate': defaultPageTemplate.name,
    'defaultPageFlow': defaultPageFlow.name,
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
      autosaveInterval: _enumByName(
        AutosaveInterval.values,
        json['autosaveInterval'],
        AutosaveInterval.halfSecond,
      ),
      defaultLayoutType: _enumByName(
        CanvasLayoutType.values,
        json['defaultLayoutType'],
        CanvasLayoutType.paged,
      ),
      defaultPageTemplate: _enumByName(
        CanvasPageTemplate.values,
        json['defaultPageTemplate'],
        CanvasPageTemplate.blank,
      ),
      defaultPageFlow: _enumByName(
        CanvasPageFlow.values,
        json['defaultPageFlow'],
        CanvasPageFlow.topToBottom,
      ),
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
