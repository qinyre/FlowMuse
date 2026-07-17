import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI 思维导图作为一次场景变更插入并可一次撤销', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    var sceneChanges = 0;
    controller.onSceneChanged = (_, _) => sceneChanges++;

    controller.insertMindmap(
      MindmapNode(
        text: '中心主题',
        children: [
          MindmapNode(text: '分支一'),
          MindmapNode(text: '分支二'),
        ],
      ),
    );

    final elements = controller.editorState.scene.activeElements;
    expect(elements.whereType<RectangleElement>(), hasLength(3));
    expect(elements.whereType<TextElement>(), hasLength(3));
    expect(elements.whereType<ArrowElement>(), hasLength(2));
    expect(sceneChanges, 1);

    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });
}
