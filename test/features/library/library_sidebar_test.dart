import 'package:flow_muse/features/library/widgets/library_sidebar.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _testSidebar() {
  return ProviderScope(
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
                body: LibrarySidebar(section: ShellSection.folders),
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
}
