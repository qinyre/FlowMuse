import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';
import '../editor_core/flow_muse_whiteboard_editor.dart';
import '../models/editor_preferences.dart';

class EditorPreferencesViewModel extends AsyncNotifier<EditorPreferences> {
  static const settingsKey = 'whiteboard.editor_preferences.v1';

  @override
  Future<EditorPreferences> build() async {
    final raw = await defaultLocalSettingsRepository.readString(settingsKey);
    if (raw == null) return EditorPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return EditorPreferences.fromJson(decoded);
      }
    } catch (error) {
      debugPrint('[FlowMuseCreateNote] editor preferences ignored: $error');
    }
    return EditorPreferences();
  }

  Future<void> setDefaultTool(ToolType value) =>
      _save(_current.copyWith(defaultTool: value));

  Future<void> setDefaultBrush(BrushType value) =>
      _save(_current.copyWith(defaultBrush: value));

  Future<void> updateBrushState(BrushType type, BrushState value) {
    return _save(
      _current.copyWith(brushStates: {..._current.brushStates, type: value}),
    );
  }

  Future<void> setPressureEnabled(bool value) =>
      _save(_current.copyWith(pressureEnabled: value));

  Future<void> setPressureCurve(PressureCurvePreset value) =>
      _save(_current.copyWith(pressureCurve: value));

  Future<void> setPalmRejectionEnabled(bool value) =>
      _save(_current.copyWith(palmRejectionEnabled: value));

  Future<void> setTwoFingerZoomEnabled(bool value) =>
      _save(_current.copyWith(twoFingerZoomEnabled: value));

  Future<void> setSingleFingerPanEnabled(bool value) =>
      _save(_current.copyWith(singleFingerPanEnabled: value));

  Future<void> setFingerDrawingEnabled(bool value) =>
      _save(_current.copyWith(fingerDrawingEnabled: value));

  Future<void> setAutosaveInterval(AutosaveInterval value) =>
      _save(_current.copyWith(autosaveInterval: value));

  Future<void> setDefaultLayoutType(CanvasLayoutType value) =>
      _save(_current.copyWith(defaultLayoutType: value));

  Future<void> setDefaultPageTemplate(CanvasPageTemplate value) =>
      _save(_current.copyWith(defaultPageTemplate: value));

  Future<void> setDefaultPageFlow(CanvasPageFlow value) =>
      _save(_current.copyWith(defaultPageFlow: value));

  EditorPreferences get _current => state.value ?? EditorPreferences();

  Future<void> _save(EditorPreferences value) async {
    state = AsyncData(value);
    await defaultLocalSettingsRepository.writeString(
      settingsKey,
      jsonEncode(value.toJson()),
    );
  }
}

final editorPreferencesProvider =
    AsyncNotifierProvider<EditorPreferencesViewModel, EditorPreferences>(
      EditorPreferencesViewModel.new,
    );
