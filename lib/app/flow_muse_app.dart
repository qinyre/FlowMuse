import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'app_theme.dart';
import 'app_theme_preset.dart';
import 'view_models/theme_view_model.dart';

class FlowMuseApp extends ConsumerWidget {
  FlowMuseApp({super.key}) : _router = createAppRouter();

  final RouterConfig<Object> _router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreset = ref.watch(themeViewModelProvider);
    final darkThemePreset = themePreset.id == AppThemeId.system
        ? systemDarkThemePreset
        : themePreset;

    return MaterialApp.router(
      title: 'FlowMuse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromPreset(themePreset),
      darkTheme: AppTheme.fromPreset(darkThemePreset),
      themeMode: themePreset.themeMode,
      routerConfig: _router,
    );
  }
}
