import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/shared/widgets/theme_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(AppThemePreset preset) {
  return ProviderScope(
    overrides: [initialThemePresetProvider.overrideWithValue(preset)],
    child: const MaterialApp(
      home: Scaffold(body: ThemeHero(semanticLabel: '资料库主题横幅')),
    ),
  );
}

void main() {
  testWidgets('theme hero renders only for a featured preset', (tester) async {
    await tester.pumpWidget(_testApp(appThemePresetById(AppThemeId.starryBlue)));

    expect(find.byKey(const ValueKey('theme-hero-wallpaper')), findsOneWidget);
  });

  testWidgets('theme hero hides for a base preset', (tester) async {
    await tester.pumpWidget(_testApp(appThemePresetById(AppThemeId.day)));

    expect(find.byKey(const ValueKey('theme-hero-wallpaper')), findsNothing);
  });
}
