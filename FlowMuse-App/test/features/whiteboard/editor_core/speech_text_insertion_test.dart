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

  test('长语音文字复用自适应布局并自动换行', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));

    controller.insertPlainText(
      List.filled(200, '语音文字').join(),
      adaptiveLayout: true,
    );

    final element =
        controller.editorState.scene.activeElements.single as TextElement;
    expect(element.autoResize, isFalse);
    expect(element.width, lessThan(800));
    expect(element.height, greaterThan(element.fontSize * element.lineHeight));
  });

  test('AI 多段文字作为一次场景变更插入并可一次撤销', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;

    controller.insertPlainTexts(['总结内容', '待办事项'], adaptiveLayout: true);

    expect(controller.editorState.scene.activeElements, hasLength(2));
    expect(sceneChanges, 1);
    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  test('AI 长文本按可用宽度换行而不是生成单行超长文本框', () {
    final controller = MarkdrawController(
      config: MarkdrawEditorConfig(
        initialLayout: CanvasLayout(
          type: CanvasLayoutType.paged,
          pages: [
            CanvasPage(
              id: 'page-1',
              index: 0,
              bounds: Rect.fromLTWH(0, 0, 400, 800),
              template: CanvasPageTemplate.blank,
            ),
          ],
        ),
      ),
    );
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));

    controller.insertPlainTexts([
      List.filled(300, '长文本').join(),
    ], adaptiveLayout: true);

    final element = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .single;
    expect(element.autoResize, isFalse);
    expect(element.x, greaterThanOrEqualTo(72));
    expect(element.x + element.width, lessThanOrEqualTo(328));
    expect(element.height, greaterThan(element.fontSize * element.lineHeight));
  });

  test('AI 文本优先放入当前视口的空闲区域', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('occupied'),
          x: 32,
          y: 32,
          width: 340,
          height: 200,
        ),
      ),
    );

    controller.insertPlainTexts(['AI 总结'], adaptiveLayout: true);

    final element = controller.editorState.scene.activeElements
        .whereType<TextElement>()
        .single;
    expect(element.x, greaterThanOrEqualTo(448));
  });
}
