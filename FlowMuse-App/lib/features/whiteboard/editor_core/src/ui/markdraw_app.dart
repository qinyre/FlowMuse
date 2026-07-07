/// Convenience [MaterialApp] wrapper with built-in theme state management.
library;

import 'package:flutter/material.dart';

/// A [MaterialApp] wrapper that manages [ThemeMode] state internally.
///
/// Eliminates the common boilerplate of wiring up a [ValueNotifier] and
/// [ValueListenableBuilder] just to support light/dark/system theme switching.
///
/// The [home] builder receives the current [ThemeMode] and a callback to
/// change it, so that [MarkdrawEditor] can be wired up easily:
///
/// ```dart
/// MarkdrawApp(
///   home: (context, themeMode, onThemeModeChanged) => MarkdrawEditor(
///     currentThemeMode: themeMode,
///     onThemeModeChanged: onThemeModeChanged,
///   ),
/// )
/// ```
class MarkdrawApp extends StatefulWidget {
  const MarkdrawApp({
    super.key,
    required this.home,
    this.title = 'Markdraw',
    this.initialThemeMode = ThemeMode.system,
    this.colorSchemeSeed = Colors.blue,
    this.debugShowCheckedModeBanner = false,
  });

  /// Builder that provides [ThemeMode] state and a setter callback.
  final Widget Function(
    BuildContext context,
    ThemeMode themeMode,
    void Function(ThemeMode) onThemeModeChanged,
  )
  home;

  final String title;
  final ThemeMode initialThemeMode;
  final Color colorSchemeSeed;
  final bool debugShowCheckedModeBanner;

  @override
  State<MarkdrawApp> createState() => _MarkdrawAppState();
}

class _MarkdrawAppState extends State<MarkdrawApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.initialThemeMode;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.title,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: widget.colorSchemeSeed,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: widget.colorSchemeSeed,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      home: Builder(
        builder: (context) => widget.home(
          context,
          _themeMode,
          (mode) => setState(() => _themeMode = mode),
        ),
      ),
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
    );
  }
}
