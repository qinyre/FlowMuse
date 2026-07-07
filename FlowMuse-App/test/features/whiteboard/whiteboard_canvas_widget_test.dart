import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp() {
  return ProviderScope(child: FlowMuseApp());
}

void main() {
  testWidgets('opens markdraw editor for new whiteboard', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp());
    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('flowmuse-markdraw-editor')),
      findsOneWidget,
    );
    expect(find.text('未命名白板'), findsOneWidget);
  });

  testWidgets('keeps collaboration controls outside the markdraw editor', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp());
    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();

    expect(find.text('本地白板'), findsOneWidget);
    expect(find.text('创建房间'), findsOneWidget);
  });
}
