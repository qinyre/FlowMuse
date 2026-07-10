import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/local_settings_repository.dart';
import '../app_theme_preset.dart';

final initialThemePresetProvider = Provider<AppThemePreset>(
  (ref) => defaultThemePreset,
);

Future<AppThemePreset> loadSavedThemePreset() async {
  final presetName = await defaultLocalSettingsRepository.readString(
    ThemeViewModel.themePresetKey,
  );
  if (presetName == null) {
    return defaultThemePreset;
  }
  return appThemePresetByName(presetName);
}

class ThemeViewModel extends Notifier<AppThemePreset> {
  static const themePresetKey = 'theme_preset';

  @override
  AppThemePreset build() {
    return ref.watch(initialThemePresetProvider);
  }

  Future<void> restoreSavedPreset() async {
    state = await loadSavedThemePreset();
  }

  Future<void> changePreset(AppThemePreset preset) async {
    state = preset;
    await defaultLocalSettingsRepository.writeString(
      themePresetKey,
      preset.id.name,
    );
  }
}

final themeViewModelProvider = NotifierProvider<ThemeViewModel, AppThemePreset>(
  ThemeViewModel.new,
);
