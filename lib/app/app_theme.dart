import 'package:flutter/material.dart';

import 'app_theme_preset.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData fromPreset(AppThemePreset preset) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: preset.seedColor,
      brightness: preset.brightness,
    );
    final surface = preset.isDark ? const Color(0xFF111514) : Colors.white;
    final scaffold = preset.isDark
        ? const Color(0xFF090C0B)
        : const Color(0xFFFAFCFA);

    return ThemeData(
      useMaterial3: true,
      brightness: preset.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: 'serif',
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.primary.withValues(alpha: 0.045),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          selectedForegroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.28)),
        ),
      ),
    );
  }
}
