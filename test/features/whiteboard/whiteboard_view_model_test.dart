import 'package:flow_muse/features/whiteboard/view_models/whiteboard_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates elements with Excalidraw fractional indexes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final viewModel = container.read(whiteboardViewModelProvider.notifier);
    viewModel.selectTool(WhiteboardTool.rectangle);

    await viewModel.addElementFromDrag(
      startX: 0,
      startY: 0,
      endX: 10,
      endY: 10,
    );
    await viewModel.addElementFromDrag(
      startX: 20,
      startY: 20,
      endX: 40,
      endY: 40,
    );
    await viewModel.addElementFromDrag(
      startX: 50,
      startY: 50,
      endX: 80,
      endY: 80,
    );

    final elements = container.read(whiteboardViewModelProvider).elements;

    expect(elements.map((element) => element.fractionalIndex), [
      'a0',
      'a1',
      'a2',
    ]);
  });
}
