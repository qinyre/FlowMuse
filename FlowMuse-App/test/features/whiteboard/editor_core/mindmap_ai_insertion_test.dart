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

    final bounds = elements
        .map(
          (element) => Rect.fromLTWH(
            element.x,
            element.y,
            element.width,
            element.height,
          ),
        )
        .reduce((left, right) => left.expandToInclude(right));
    expect(bounds.center.dx, closeTo(400, 0.001));
    expect(bounds.center.dy, closeTo(300, 0.001));

    controller.undo();
    expect(controller.editorState.scene.activeElements, isEmpty);
  });

  test('宽度超过视口时从可见区域左边距开始布局', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);

    controller.insertMindmap(
      MindmapNode(
        text: '第一层',
        children: [
          MindmapNode(
            text: '第二层',
            children: [
              MindmapNode(
                text: '第三层',
                children: [MindmapNode(text: '第四层')],
              ),
            ],
          ),
        ],
      ),
    );

    final left = controller.editorState.scene.activeElements
        .map((element) => element.x)
        .reduce((left, right) => left < right ? left : right);
    expect(left, closeTo(48, 0.001));
  });
}
