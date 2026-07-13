import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme_preset.dart';
import '../../app/view_models/theme_view_model.dart';
import 'app_spacing.dart';

class ThemeHero extends ConsumerWidget {
  const ThemeHero({super.key, required this.semanticLabel});

  final String semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = effectiveAppThemePreset(
      ref.watch(themeViewModelProvider),
      MediaQuery.platformBrightnessOf(context),
    );

    if (!preset.hasWallpaper) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        key: const ValueKey('theme-hero-wallpaper'),
        height: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          image: DecorationImage(
            image: AssetImage(preset.wallpaperAsset!),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              preset.heroOverlay,
              BlendMode.srcOver,
            ),
          ),
        ),
      ),
    );
  }
}
