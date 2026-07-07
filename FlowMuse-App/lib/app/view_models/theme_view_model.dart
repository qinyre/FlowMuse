import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme_preset.dart';

class ThemeViewModel extends Notifier<AppThemePreset> {
  static const _themePresetKey = 'theme_preset';
  static const _legacyThemeColorKey = 'theme_color';

  @override
  AppThemePreset build() {
    _restore();
    return defaultThemePreset;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final presetName = preferences.getString(_themePresetKey);

    if (presetName != null) {
      state = appThemePresetByName(presetName);
      return;
    }

    if (preferences.containsKey(_legacyThemeColorKey)) {
      state = appThemePresetById(AppThemeId.auroraGreen);
    }
  }

  Future<void> changePreset(AppThemePreset preset) async {
    state = preset;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_themePresetKey, preset.id.name);
  }
}

final themeViewModelProvider = NotifierProvider<ThemeViewModel, AppThemePreset>(
  ThemeViewModel.new,
);
