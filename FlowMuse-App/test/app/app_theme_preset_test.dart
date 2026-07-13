import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only featured presets declare local wallpapers', () {
    final featured = appThemePresets.where((preset) => preset.hasWallpaper);

    expect(featured.map((preset) => preset.id), {
      AppThemeId.starryBlue,
      AppThemeId.mistBlue,
      AppThemeId.auroraGreen,
    });
    expect(appThemePresetById(AppThemeId.day).wallpaperAsset, isNull);
    expect(appThemePresetById(AppThemeId.night).wallpaperAsset, isNull);
    expect(appThemePresetById(AppThemeId.system).wallpaperAsset, isNull);
  });
}
