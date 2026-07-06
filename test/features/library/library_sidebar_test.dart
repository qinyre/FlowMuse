import 'package:flow_muse/features/library/widgets/library_sidebar.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testSidebar() {
  return const MaterialApp(
    home: Scaffold(body: LibrarySidebar(section: ShellSection.library)),
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
}
