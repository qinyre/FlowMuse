import 'package:flutter_test/flutter_test.dart';

import 'package:flow_muse/main.dart';

void main() {
  testWidgets('shows the library shell with sample notebooks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlowMuseApp());

    expect(find.text('全部笔记'), findsWidgets);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);
    expect(find.text('LectureNotes'), findsOneWidget);
  });

  testWidgets('opens the whiteboard placeholder from the create card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FlowMuseApp());

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    expect(find.text('未命名白板'), findsOneWidget);
    expect(find.text('白板工作台'), findsOneWidget);
  });
}
