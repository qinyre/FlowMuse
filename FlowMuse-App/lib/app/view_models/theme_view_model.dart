import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/local_settings_repository.dart';
import '../app_theme_preset.dart';

class ThemeViewModel extends Notifier<AppThemePreset> {
  static const _themePresetKey = 'theme_preset';

  @override
  AppThemePreset build() {
    _restore();
    return defaultThemePreset;
  }

  Future<void> _restore() async {
    final settings = defaultLocalSettingsRepository;
    final presetName = await settings.readString(_themePresetKey);

    if (presetName != null) {
      state = appThemePresetByName(presetName);
      return;
    }
  }

  Future<void> changePreset(AppThemePreset preset) async {
    state = preset;
    await defaultLocalSettingsRepository.writeString(
      _themePresetKey,
      preset.id.name,
    );
  }
}

final themeViewModelProvider = NotifierProvider<ThemeViewModel, AppThemePreset>(
  ThemeViewModel.new,
);
