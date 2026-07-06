import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/whiteboard/models/whiteboard_element.dart';
import 'package:flow_muse/features/whiteboard/view_models/whiteboard_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp() {
  return ProviderScope(child: FlowMuseApp());
}

void main() {
  testWidgets('draws a rectangle element from pointer drag', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_testApp());
    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('whiteboard-tool-rectangle')));
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(320, 260), const Offset(180, 120));
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const ValueKey('whiteboard-canvas')),
    );
    final container = ProviderScope.containerOf(context);
    final state = container.read(whiteboardViewModelProvider);

    expect(state.elements, hasLength(1));
    expect(state.elements.single.type, WhiteboardElementType.rectangle);
    expect(state.canUndo, isTrue);
  });

  testWidgets('zoom controls update the whiteboard zoom level', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('whiteboard-zoom-in')));
    await tester.pumpAndSettle();

    expect(find.text('110%'), findsOneWidget);
  });
}
