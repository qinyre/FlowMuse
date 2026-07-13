import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('场景回调只暴露本次工具结果修改的元素', () {
    final controller = MarkdrawController();
    final unchanged = RectangleElement(
      id: ElementId('unchanged'),
      x: 0,
      y: 0,
      width: 10,
      height: 10,
    );
    final changed = RectangleElement(
      id: ElementId('changed'),
      x: 20,
      y: 20,
      width: 10,
      height: 10,
    );

    controller.applyResult(AddElementResult(unchanged));
    controller.applyResult(AddElementResult(changed));

    expect(controller.lastChangedElements?.map((element) => element.id.value), [
      'changed',
    ]);

    controller.applyResult(RemoveElementResult(changed.id));
    expect(controller.lastChangedElements, hasLength(1));
    expect(controller.lastChangedElements!.single.id, changed.id);
    expect(controller.lastChangedElements!.single.isDeleted, isTrue);
  });
}
