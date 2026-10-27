import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_library_index_notifier.dart';

void main() {
  testWidgets('首页启动后显示全部笔记且没有框架异常', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryIndexProvider.overrideWith(TestLibraryIndexNotifier.new),
        ],
        child: FlowMuseApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('全部笔记'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
