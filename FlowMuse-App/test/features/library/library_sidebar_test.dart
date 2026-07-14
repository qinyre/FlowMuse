import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/widgets/library_sidebar.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/test_library_index_notifier.dart';

Widget _testSidebar({AppThemePreset? initialPreset}) {
  return ProviderScope(
    overrides: [
      libraryIndexProvider.overrideWith(TestLibraryIndexNotifier.new),
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
    await tester.pump();
    await tester.pump();

    expect(find.text('未归入笔记本'), findsOneWidget);
    expect(find.text('未标签'), findsOneWidget);

    await tester.tap(find.byTooltip('全部笔记展开收起'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('empty-all-notes')), findsOneWidget);
  });

  testWidgets('shows empty notebook and tag actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testSidebar());
    await tester.pump();
    await tester.pump();

    expect(find.text('暂无笔记本'), findsOneWidget);
    expect(find.text('暂无标签'), findsOneWidget);
    expect(find.byTooltip('笔记本展开收起'), findsNothing);
    expect(find.byTooltip('标签展开收起'), findsNothing);
    expect(find.byTooltip('新建笔记本'), findsOneWidget);
    expect(find.byTooltip('新建标签'), findsOneWidget);
  });

  testWidgets('overlays featured wallpaper at the sidebar bottom', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testSidebar(initialPreset: appThemePresetById(AppThemeId.starryBlue)),
    );
    await tester.pump();
    await tester.pump();

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
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('sidebar-bottom-wallpaper')),
      findsNothing,
    );
  });
}
