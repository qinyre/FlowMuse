import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/library/widgets/library_sidebar.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _testSidebar({AppThemePreset? initialPreset}) {
  return ProviderScope(
    overrides: [
      if (initialPreset != null)
        initialThemePresetProvider.overrideWithValue(initialPreset),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/library',
        routes: [
          GoRoute(
            path: '/library',
            builder: (context, state) {
              return const Scaffold(
                body: LibrarySidebar(section: ShellSection.library),
              );
            },
          ),
          GoRoute(
            path: '/folders',
            builder: (context, state) {
              return const Scaffold(
                body: LibrarySidebar(section: ShellSection.notebooks),
              );
            },
          ),
          GoRoute(
            path: '/tags',
            builder: (context, state) {
              return const Scaffold(
                body: LibrarySidebar(section: ShellSection.tags),
              );
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('collapses uncategorized and untagged under all notes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testSidebar());

    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('未标签'), findsOneWidget);

    await tester.tap(find.byTooltip('全部笔记展开收起'));
    await tester.pumpAndSettle();

    expect(find.text('未分类'), findsNothing);
    expect(find.text('未标签'), findsNothing);
  });

  testWidgets('creates and collapses folders and tags from sidebar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testSidebar());

    expect(find.text('暂无文件夹'), findsOneWidget);
    expect(find.text('暂无标签'), findsOneWidget);
    expect(find.byTooltip('文件夹展开收起'), findsNothing);
    expect(find.byTooltip('标签展开收起'), findsNothing);

    await tester.tap(find.byTooltip('新建文件夹'));
    await tester.pumpAndSettle();

    expect(find.text('新建文件夹 1'), findsOneWidget);
    expect(find.text('暂无文件夹'), findsNothing);
    expect(find.byTooltip('文件夹展开收起'), findsOneWidget);

    await tester.tap(find.byTooltip('文件夹展开收起'));
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹 1'), findsNothing);

    await tester.tap(find.byTooltip('新建标签'));
    await tester.pumpAndSettle();

    expect(find.text('新建标签 1'), findsOneWidget);
    expect(find.text('暂无标签'), findsNothing);
    expect(find.byTooltip('标签展开收起'), findsOneWidget);

    await tester.tap(find.byTooltip('标签展开收起'));
    await tester.pumpAndSettle();
    expect(find.text('新建标签 1'), findsNothing);
  });

  testWidgets('overlays featured wallpaper at the sidebar bottom', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testSidebar(initialPreset: appThemePresetById(AppThemeId.starryBlue)),
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

  testWidgets('does not overlay wallpaper for a base theme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testSidebar(initialPreset: appThemePresetById(AppThemeId.day)),
    );

    expect(
      find.byKey(const ValueKey('sidebar-bottom-wallpaper')),
      findsNothing,
    );
  });
}
