import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单击创建的长文本会在当前画面内换行并保持宽度', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(40, 300);
    controller.canvasSize = const Size(400, 300);
    controller.applyStyleChange(const ElementStyle(fontFamily: 'Excalifont'));
    controller.switchTool(ToolType.text);
    controller.onPointerDown(
      const PointerDownEvent(
        position: Offset(40, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );
    controller.onPointerUp(
      const PointerUpEvent(
        position: Offset(40, 40),
        kind: PointerDeviceKind.mouse,
      ),
    );

    controller.textEditingController.text = List.filled(
      20,
      '这是一段需要自动换行的长文本',
    ).join();
    controller.onTextChanged();

    final text = controller.currentScene.activeElements.single as TextElement;
    expect(text.autoResize, isFalse);
    expect(text.width, greaterThan(200));
    expect(text.x + text.width, lessThanOrEqualTo(363));
    expect(text.height, greaterThan(25));

    final restored = MarkdrawController();
    addTearDown(restored.dispose);
    restored.loadFromContent(
      controller.serializeScene(format: DocumentFormat.excalidraw),
      'note.excalidraw',
    );
    final restoredText =
        restored.currentScene.activeElements.single as TextElement;
    expect(restoredText.autoResize, isFalse);
    expect(restoredText.width, text.width);
  });

  test('手动缩放文本框会关闭自动撑宽', () {
    final id = ElementId('text');
    final element = TextElement(
      id: id,
      x: 0,
      y: 0,
      width: 100,
      height: 40,
      text: 'hello',
    );
    final scene = Scene().addElement(element);
    final context = ToolContext(
      scene: scene,
      viewport: const ViewportState(),
      selectedIds: {id},
    );
    final tool = SelectTool();

    tool.onPointerDown(const Point(106, 46), context);
    final result = tool.onPointerMove(const Point(166, 66), context);
    final resized = switch (result) {
      UpdateElementResult(:final element) => element,
      CompoundResult(:final results) =>
        results.whereType<UpdateElementResult>().first.element,
      _ => null,
    };

    expect(resized, isA<TextElement>());
    expect((resized! as TextElement).autoResize, isFalse);
    expect(resized.width, 160);

    final encoded = ExcalidrawJsonCodec.serialize(
      MarkdrawDocument(
        sections: [
          SketchSection([resized]),
        ],
      ),
    );
    final restored = ExcalidrawJsonCodec.parse(
      encoded,
    ).value.allElements.single;
    expect((restored as TextElement).autoResize, isFalse);
    expect(restored.width, 160);
  });
}
