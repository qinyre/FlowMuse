import 'package:flutter/material.dart';

import 'app_theme_preset.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData fromPreset(AppThemePreset preset) {
    final usesMutedDarkAccents =
        preset.usesMonochromeBackground && preset.isDark;
    final seededScheme = ColorScheme.fromSeed(
      seedColor: preset.seedColor,
      brightness: preset.brightness,
    );
    final colorScheme = seededScheme.copyWith(
      primary: usesMutedDarkAccents ? const Color(0xFF96ABA7) : null,
      onPrimary: usesMutedDarkAccents ? const Color(0xFF18211F) : null,
      primaryContainer: usesMutedDarkAccents
          ? const Color(0xFF34433F)
          : null,
      onPrimaryContainer: usesMutedDarkAccents
          ? const Color(0xFFC7D7D3)
          : null,
      secondary: usesMutedDarkAccents
          ? const Color(0xFF91A5A1)
          : preset.secondaryColor,
      onSecondary: usesMutedDarkAccents ? const Color(0xFF17201E) : null,
      secondaryContainer: usesMutedDarkAccents
          ? const Color(0xFF34433F)
          : null,
      onSecondaryContainer: usesMutedDarkAccents
          ? const Color(0xFFC5D6D1)
          : null,
      tertiary: preset.tertiaryColor,
      surface: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF121212) : Colors.white)
          : null,
      surfaceContainerLowest: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF121212) : Colors.white)
          : null,
      surfaceContainerLow: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF191919) : const Color(0xFFF8F8F8))
          : null,
      surfaceContainer: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF202020) : const Color(0xFFF2F2F2))
          : null,
      surfaceContainerHigh: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF282828) : const Color(0xFFEBEBEB))
          : null,
      surfaceContainerHighest: preset.usesMonochromeBackground
          ? (preset.isDark ? const Color(0xFF303030) : const Color(0xFFE5E5E5))
          : null,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: preset.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'serif',
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        titleTextStyle: TextStyle(color: colorScheme.onSurface),
        contentTextStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHighest),
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
