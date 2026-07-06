import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme_preset.dart';
import '../../app/view_models/theme_view_model.dart';
import '../../features/library/widgets/library_sidebar.dart';

enum ShellSection { library, search, folders, settings }

const sharedSidebarWidth = 268.0;

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.child,
    this.showSidebar = true,
  });

  final ShellSection section;
  final Widget child;
  final bool showSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreset = ref.watch(themeViewModelProvider);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectivePreset =
        themePreset.id == AppThemeId.system &&
            platformBrightness == Brightness.dark
        ? systemDarkThemePreset
        : themePreset;

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(color: effectivePreset.backgroundEnd),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 820;
              return Row(
                children: [
                  if (showSidebar && !compact) LibrarySidebar(section: section),
                  Expanded(child: child),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
