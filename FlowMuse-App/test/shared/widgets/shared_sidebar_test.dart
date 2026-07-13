import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(AppThemePreset preset, {bool showWallpaper = true}) {
  return ProviderScope(
    overrides: [initialThemePresetProvider.overrideWithValue(preset)],
    child: MaterialApp(
      home: Scaffold(
        body: SharedSidebar(
          showWallpaper: showWallpaper,
          header: SizedBox.shrink(),
          children: [Text('Sidebar item')],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('overlays featured wallpaper at the sidebar bottom', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(appThemePresetById(AppThemeId.starryBlue)),
    );

    final wallpaper = find.byKey(const ValueKey('sidebar-bottom-wallpaper'));
    expect(wallpaper, findsOneWidget);
    expect(
      find.ancestor(
        of: wallpaper,
        matching: find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.ignoring,
        ),
      ),
      findsOneWidget,
    );

    final image =
        (tester.widget<Container>(wallpaper).decoration as BoxDecoration)
            .image!;
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, Alignment.bottomRight);
  });

  testWidgets('does not overlay wallpaper for a base theme', (tester) async {
    await tester.pumpWidget(_testApp(appThemePresetById(AppThemeId.day)));

    expect(
      find.byKey(const ValueKey('sidebar-bottom-wallpaper')),
      findsNothing,
    );
  });

  testWidgets('adds scroll extent only for featured sidebar artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(appThemePresetById(AppThemeId.starryBlue)),
    );
    expect(
      (tester.widget<ListView>(find.byType(ListView)).padding as EdgeInsets)
          .bottom,
      180,
    );

    await tester.pumpWidget(
      _testApp(appThemePresetById(AppThemeId.starryBlue), showWallpaper: false),
    );
    expect(
      find.byKey(const ValueKey('sidebar-bottom-wallpaper')),
      findsNothing,
    );
    expect(
      (tester.widget<ListView>(find.byType(ListView)).padding as EdgeInsets)
          .bottom,
      0,
    );
  });
}
