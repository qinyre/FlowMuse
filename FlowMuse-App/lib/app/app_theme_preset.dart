import 'package:flutter/material.dart';

enum AppThemeId { day, night, system, starryBlue, mistBlue, auroraGreen }

class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.seedColor,
    required this.brightness,
    required this.themeMode,
    required this.backgroundStart,
    required this.backgroundMiddle,
    required this.backgroundEnd,
    required this.canvasBackground,
    required this.wallpaperAsset,
    required this.wallpaperOverlay,
    required this.heroOverlay,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final AppThemeId id;
  final String label;
  final String description;
  final Color seedColor;
  final Brightness brightness;
  final ThemeMode themeMode;
  final Color backgroundStart;
  final Color backgroundMiddle;
  final Color backgroundEnd;
  final String canvasBackground;
  final String? wallpaperAsset;
  final Color wallpaperOverlay;
  final Color heroOverlay;
  final Color secondaryColor;
  final Color tertiaryColor;

  bool get isDark => brightness == Brightness.dark;
  bool get hasWallpaper => wallpaperAsset != null;
  bool get usesMonochromeBackground =>
      id == AppThemeId.day || id == AppThemeId.night || id == AppThemeId.system;
}

const appThemePresets = <AppThemePreset>[
  AppThemePreset(
    id: AppThemeId.day,
    label: '日间',
    description: '白色基底，适合长时间阅读和整理',
    seedColor: Color(0xFF4F8F84),
    brightness: Brightness.light,
    themeMode: ThemeMode.light,
    backgroundStart: Color(0xFFFFFFFF),
    backgroundMiddle: Color(0xFFF7FAF8),
    backgroundEnd: Color(0xFFFDFEFD),
    canvasBackground: '#ffffff',
    wallpaperAsset: null,
    wallpaperOverlay: Color(0x00000000),
    heroOverlay: Color(0x00000000),
    secondaryColor: Color(0xFF5D91B8),
    tertiaryColor: Color(0xFFA56F4E),
  ),
  AppThemePreset(
    id: AppThemeId.night,
    label: '夜间',
    description: '深炭黑基底，降低暗光环境刺激',
    seedColor: Color(0xFF6F8984),
    brightness: Brightness.dark,
    themeMode: ThemeMode.dark,
    backgroundStart: Color(0xFF121212),
    backgroundMiddle: Color(0xFF121212),
    backgroundEnd: Color(0xFF121212),
    canvasBackground: '#121212',
    wallpaperAsset: null,
    wallpaperOverlay: Color(0x00000000),
    heroOverlay: Color(0x00000000),
    secondaryColor: Color(0xFF91A5A1),
    tertiaryColor: Color(0xFFE0B070),
  ),
  AppThemePreset(
    id: AppThemeId.system,
    label: '系统',
    description: '跟随系统日夜变化',
    seedColor: Color(0xFF4F8F84),
    brightness: Brightness.light,
    themeMode: ThemeMode.system,
    backgroundStart: Color(0xFFFFFFFF),
    backgroundMiddle: Color(0xFFF7FAF8),
    backgroundEnd: Color(0xFFFDFEFD),
    canvasBackground: '#ffffff',
    wallpaperAsset: null,
    wallpaperOverlay: Color(0x00000000),
    heroOverlay: Color(0x00000000),
    secondaryColor: Color(0xFF5D91B8),
    tertiaryColor: Color(0xFFA56F4E),
  ),
  AppThemePreset(
    id: AppThemeId.starryBlue,
    label: '星夜蓝',
    description: '暗色蓝调，适合沉浸式创作',
    seedColor: Color(0xFF78A6FF),
    brightness: Brightness.dark,
    themeMode: ThemeMode.dark,
    backgroundStart: Color(0xFF07111F),
    backgroundMiddle: Color(0xFF10223A),
    backgroundEnd: Color(0xFF060A12),
    canvasBackground: '#060a12',
    wallpaperAsset: 'assets/themes/starry-blue.png',
    wallpaperOverlay: Color(0x8A07111F),
    heroOverlay: Color(0x6607111F),
    secondaryColor: Color(0xFF74C7EC),
    tertiaryColor: Color(0xFFCBA6F7),
  ),
  AppThemePreset(
    id: AppThemeId.mistBlue,
    label: '雾蓝',
    description: '日间蓝调，清爽克制',
    seedColor: Color(0xFF5D91B8),
    brightness: Brightness.light,
    themeMode: ThemeMode.light,
    backgroundStart: Color(0xFFEFF7FB),
    backgroundMiddle: Color(0xFFDDEDF6),
    backgroundEnd: Color(0xFFFAFCFD),
    canvasBackground: '#fafcfd',
    wallpaperAsset: 'assets/themes/mist-blue.png',
    wallpaperOverlay: Color(0x4DEFF7FB),
    heroOverlay: Color(0x33EFF7FB),
    secondaryColor: Color(0xFF4E9E9A),
    tertiaryColor: Color(0xFF86789C),
  ),
  AppThemePreset(
    id: AppThemeId.auroraGreen,
    label: '绿霞',
    description: '日间绿调，柔和有生命力',
    seedColor: Color(0xFF66B7A8),
    brightness: Brightness.light,
    themeMode: ThemeMode.light,
    backgroundStart: Color(0xFFF4FBF2),
    backgroundMiddle: Color(0xFFDFF2EA),
    backgroundEnd: Color(0xFFFFFCF6),
    canvasBackground: '#fffcf6',
    wallpaperAsset: 'assets/themes/aurora-green.png',
    wallpaperOverlay: Color(0x4DF4FBF2),
    heroOverlay: Color(0x33F4FBF2),
    secondaryColor: Color(0xFF5E9E6F),
    tertiaryColor: Color(0xFFC18B5D),
  ),
];

AppThemePreset get defaultThemePreset => appThemePresets[0];
AppThemePreset get systemDarkThemePreset => appThemePresets[1];

AppThemePreset effectiveAppThemePreset(
  AppThemePreset preset,
  Brightness platformBrightness,
) {
  if (preset.id == AppThemeId.system && platformBrightness == Brightness.dark) {
    return systemDarkThemePreset;
  }
  return preset;
}

AppThemePreset appThemePresetById(AppThemeId id) {
  return appThemePresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => defaultThemePreset,
  );
}

AppThemePreset appThemePresetByThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => appThemePresetById(AppThemeId.day),
    ThemeMode.dark => appThemePresetById(AppThemeId.night),
    ThemeMode.system => appThemePresetById(AppThemeId.system),
  };
}

AppThemePreset appThemePresetByName(String name) {
  return appThemePresetById(
    AppThemeId.values.firstWhere(
      (id) => id.name == name,
      orElse: () => defaultThemePreset.id,
    ),
  );
}
