import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_library_index_notifier.dart';

Widget _testApp() {
  return ProviderScope(
    overrides: [
      libraryIndexProvider.overrideWith(TestLibraryIndexNotifier.new),
    ],
    child: FlowMuseApp(),
  );
}

void main() {
  testWidgets('opens the current note setup flow', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('新建笔记'), findsOneWidget);
  });

  testWidgets('shows the collaboration entry in the library', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump();

    expect(find.text('加入房间'), findsWidgets);
  });
}
