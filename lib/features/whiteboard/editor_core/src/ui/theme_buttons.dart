library;

import 'package:flutter/material.dart';

/// Theme toggle buttons (light/dark/system).
class ThemeButtons extends StatelessWidget {
  final ThemeMode? currentThemeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final bool dismissOnTap;

  const ThemeButtons({
    super.key,
    this.currentThemeMode,
    this.onThemeModeChanged,
    this.dismissOnTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final current = currentThemeMode ?? ThemeMode.system;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text('Theme', style: TextStyle(color: cs.onSurface)),
          const Spacer(),
          _themeButton(
            context: context,
            icon: Icons.light_mode,
            tooltip: 'Light',
            isActive: current == ThemeMode.light,
            onTap: () => _setTheme(context, ThemeMode.light),
            cs: cs,
          ),
          const SizedBox(width: 4),
          _themeButton(
            context: context,
            icon: Icons.dark_mode,
            tooltip: 'Dark',
            isActive: current == ThemeMode.dark,
            onTap: () => _setTheme(context, ThemeMode.dark),
            cs: cs,
          ),
          const SizedBox(width: 4),
          _themeButton(
            context: context,
            icon: Icons.brightness_auto,
            tooltip: 'System',
            isActive: current == ThemeMode.system,
            onTap: () => _setTheme(context, ThemeMode.system),
            cs: cs,
          ),
        ],
      ),
    );
  }

  void _setTheme(BuildContext context, ThemeMode mode) {
    onThemeModeChanged?.call(mode);
    if (dismissOnTap) {
      Navigator.of(context).pop();
    }
  }

  Widget _themeButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                icon,
                size: 18,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
