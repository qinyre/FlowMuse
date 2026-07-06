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

  bool get isDark => brightness == Brightness.dark;
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
  ),
  AppThemePreset(
    id: AppThemeId.night,
    label: '夜间',
    description: '黑色基底，降低暗光环境刺激',
    seedColor: Color(0xFF7BAFA8),
    brightness: Brightness.dark,
    themeMode: ThemeMode.dark,
    backgroundStart: Color(0xFF0D1110),
    backgroundMiddle: Color(0xFF141918),
    backgroundEnd: Color(0xFF090C0B),
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
  ),
];

AppThemePreset get defaultThemePreset => appThemePresets[0];
AppThemePreset get systemDarkThemePreset => appThemePresets[1];

AppThemePreset appThemePresetById(AppThemeId id) {
  return appThemePresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => defaultThemePreset,
  );
}

AppThemePreset appThemePresetByName(String name) {
  return appThemePresetById(
    AppThemeId.values.firstWhere(
      (id) => id.name == name,
      orElse: () => defaultThemePreset.id,
    ),
  );
}
