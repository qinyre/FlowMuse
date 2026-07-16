import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('语音文字只插入一个可撤销的标准文本元素', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));

    controller.insertPlainText('  语音输入测试  ');

    final elements = controller.editorState.scene.activeElements;
    expect(elements, hasLength(1));
    final element = elements.single as TextElement;
    expect(element.text, '语音输入测试');
    expect(element.width, greaterThanOrEqualTo(20));
    expect(element.height, greaterThan(0));
    expect(element.x, closeTo(400, 0.001));
    expect(element.y, closeTo(300, 0.001));

    final encoded = ExcalidrawJsonCodec.serialize(
      MarkdrawDocument(sections: [SketchSection(elements)]),
    );
    final decoded = ExcalidrawJsonCodec.parse(encoded).value;
    expect((decoded.allElements.single as TextElement).text, '语音输入测试');

    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  test('空白语音结果不修改场景和历史', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);

    controller.insertPlainText('  \n  ');
    controller.undo();

    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  test('AI 多段文字作为一次场景变更插入并可一次撤销', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;

    controller.insertPlainTexts(['总结内容', '待办事项']);

    expect(controller.editorState.scene.activeElements, hasLength(2));
    expect(sceneChanges, 1);
    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });
}
