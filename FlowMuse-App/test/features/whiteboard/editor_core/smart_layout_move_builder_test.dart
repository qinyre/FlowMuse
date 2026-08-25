import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/scene/scene.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_move_builder.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/tool_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('移动普通矩形产生一条 UpdateElementResult', () {
    var scene = Scene();
    scene = scene.addElement(
      RectangleElement(
        id: ElementId.generate(),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
      ),
    );
    final element = scene.activeElements.first;
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      element.id: const Offset(5, 7),
    });
    expect(results.length, 1);
    final update = results.first as UpdateElementResult;
    expect(update.element.x, 5);
    expect(update.element.y, 7);
  });

  test('绑定箭头跟随到新端点', () {
    var scene = Scene();
    final box = RectangleElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
    );
    final arrow = ArrowElement(
      id: ElementId.generate(),
      x: 100,
      y: 0,
      width: 50,
      height: 25,
      points: const [Point(0, 0), Point(50, 25)],
      startBinding: PointBinding(
        elementId: box.id.value,
        fixedPoint: const Point(1.0, 0.5),
      ),
    );
    scene = scene.addElement(box);
    scene = scene.addElement(arrow);
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      box.id: const Offset(50, 100),
    });
    final arrowUpdates = results
        .whereType<UpdateElementResult>()
        .where((update) => update.element is ArrowElement)
        .toList();
    expect(arrowUpdates.length, 1);
    // 移动后箭头应重新采样到新 box 位置（起点贴近 box 右缘中点 (150, 125)）
    final moved = arrowUpdates.first.element as ArrowElement;
    expect(moved.points.first.x + moved.x, closeTo(150, 1.0));
    expect(moved.points.first.y + moved.y, closeTo(125, 1.0));
  });

  test('绑定文本跟随父元素位置', () {
    var scene = Scene();
    final box = RectangleElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
    );
    final label = TextElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 100,
      height: 50,
      text: 'label',
      containerId: box.id.value,
    );
    scene = scene.addElement(box);
    scene = scene.addElement(label);
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      box.id: const Offset(30, 40),
    });
    final textUpdates = results
        .whereType<UpdateElementResult>()
        .where((update) => update.element is TextElement)
        .toList();
    expect(textUpdates.length, 1);
    expect(textUpdates.first.element.x, 30);
    expect(textUpdates.first.element.y, 40);
  });

  test('同一元素在 map 中不会产生两条更新（去重）', () {
    var scene = Scene();
    scene = scene.addElement(
      RectangleElement(
        id: ElementId.generate(),
        x: 0,
        y: 0,
        width: 10,
        height: 10,
      ),
    );
    final element = scene.activeElements.first;
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      element.id: const Offset(1, 1),
    });
    final updates = results.whereType<UpdateElementResult>().toList();
    expect(updates.length, 1);
    expect(updates.first.element.x, 1);
    expect(updates.first.element.y, 1);
  });

  test('frame 子元素跟随 frame 平移', () {
    var scene = Scene();
    final frame = FrameElement(
      id: ElementId.generate(),
      x: 0,
      y: 0,
      width: 300,
      height: 200,
    );
    final child = RectangleElement(
      id: ElementId.generate(),
      x: 20,
      y: 20,
      width: 50,
      height: 50,
      frameId: frame.id.value,
    );
    scene = scene.addElement(frame);
    scene = scene.addElement(child);
    final results = SmartLayoutMoveBuilder.buildResults(scene, {
      frame.id: const Offset(100, 0),
    });
    final updates = results.whereType<UpdateElementResult>().toList();
    // frame 本体 + frame 内子元素各一条
    expect(updates.length, 2);
    final childUpdate = updates.firstWhere(
      (update) => update.element.id == child.id,
    );
    expect(childUpdate.element.x, 120);
    expect(childUpdate.element.y, 20);
  });
}
