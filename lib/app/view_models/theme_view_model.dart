import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const defaultThemeColor = Color(0xFF66B7A8);

class ThemeViewModel extends Notifier<Color> {
  static const _themeColorKey = 'theme_color';

  @override
  Color build() {
    _restore();
    return defaultThemeColor;
  }

  Future<void> _restore() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getInt(_themeColorKey);
    if (value != null) {
      state = Color(value);
    }
  }

  Future<void> changeColor(Color color) async {
    state = color;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_themeColorKey, color.toARGB32());
  }
}

final themeViewModelProvider = NotifierProvider<ThemeViewModel, Color>(
  ThemeViewModel.new,
);
