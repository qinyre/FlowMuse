import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flow_muse/app/flow_muse_app.dart';

Widget _testApp() {
  return const ProviderScope(child: FlowMuseApp());
}

void main() {
  testWidgets('shows the componentized library shell with sample notebooks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    expect(find.text('全部笔记'), findsWidgets);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);
    expect(find.text('LectureNotes'), findsOneWidget);
  });

  testWidgets('filters PDF notebooks through the library view model', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('library-filter-tabs')),
        matching: find.text('PDF'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LectureNotes'), findsOneWidget);
    expect(find.text('操作系统'), findsNothing);
  });

  testWidgets('opens the whiteboard route from the create card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();

    expect(find.text('未命名白板'), findsOneWidget);
    expect(find.text('白板工作台'), findsOneWidget);
  });
}
