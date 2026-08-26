import 'dart:ui' show Offset, Size;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/collaboration_element_owner.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/creator_stamping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const alice = CollaborationCreator(
    creatorKey: 'user:a',
    displayName: 'A',
    isGuest: false,
  );
  const bob = CollaborationCreator(
    creatorKey: 'user:b',
    displayName: 'B',
    isGuest: false,
  );

  RectangleElement rect({
    String id = 'r',
    String? frameId,
    Map<String, Object?>? customData,
  }) => RectangleElement(
    id: ElementId(id),
    x: 0,
    y: 0,
    width: 5,
    height: 5,
    frameId: frameId,
    customData: customData,
  );

  test('Add 普通元素覆盖为当前 creator（即使传入自带旧 owner）', () {
    final result = AddElementResult(withCreator(rect(), bob));
    final stamped = stampCreatorOnResult(result, Scene(), alice);
    expect(
      readCreator((stamped as AddElementResult).element)?.creatorKey,
      'user:a',
    );
  });

  test('Add 系统元素（page/pdfBackground）不写 owner', () {
    final page = rect(
      customData: const {
        'flowMuse': {'role': 'page', 'pageId': 'p1'},
      },
    );
    final stamped = stampCreatorOnResult(
      AddElementResult(page),
      Scene(),
      alice,
    );
    expect(readCreator((stamped as AddElementResult).element), isNull);

    final pdf = rect(
      customData: const {
        'flowMuse': {'pageId': 'p1', 'pdfBackground': true},
      },
    );
    final stampedPdf = stampCreatorOnResult(
      AddElementResult(pdf),
      Scene(),
      alice,
    );
    expect(readCreator((stampedPdf as AddElementResult).element), isNull);
  });

  test('Add 绑定文字：父在同批 CompoundResult 中 → 继承父 owner', () {
    final parent = withCreator(rect(id: 'arrow1'), alice);
    final boundText = TextElement(
      id: const ElementId('t1'),
      x: 0,
      y: 0,
      width: 5,
      height: 5,
      text: 'label',
      containerId: 'arrow1',
    );
    final stamped =
        stampCreatorOnResult(
              CompoundResult([
                AddElementResult(parent),
                AddElementResult(boundText),
              ]),
              Scene(),
              bob,
            )
            as CompoundResult;
    // v4 §5.2：普通 Add 覆盖为当前操作者 bob；绑定文字继承盖章后的父元素。
    expect(
      readCreator((stamped.results[0] as AddElementResult).element)?.creatorKey,
      'user:b',
    );
    expect(
      readCreator((stamped.results[1] as AddElementResult).element)?.creatorKey,
      'user:b',
    );
  });

  test('Add 绑定文字：父在当前 Scene 且无 owner → 绑定文字也无 owner', () {
    final scene = Scene().addElement(rect(id: 'arrow2'));
    final boundText = TextElement(
      id: const ElementId('t2'),
      x: 0,
      y: 0,
      width: 5,
      height: 5,
      text: 'label',
      containerId: 'arrow2',
    );
    // 传入自带 owner 也要被清掉
    final stamped =
        stampCreatorOnResult(
              AddElementResult(withCreator(boundText, bob)),
              scene,
              bob,
            )
            as AddElementResult;
    expect(readCreator(stamped.element), isNull);
  });

  test('Update：Scene 中已有 owner 强制保留，忽略更新对象中的 owner 变化', () {
    final existing = withCreator(rect(id: 'r9'), alice);
    final scene = Scene().addElement(existing);
    final stamped =
        stampCreatorOnResult(
              UpdateElementResult(withCreator(rect(id: 'r9'), bob)),
              scene,
              bob,
            )
            as UpdateElementResult;
    expect(readCreator(stamped.element)?.creatorKey, 'user:a');
  });

  test('Update：历史元素（无 owner）继续无 owner，即使更新对象携带 owner', () {
    final scene = Scene().addElement(rect(id: 'r10'));
    final stamped =
        stampCreatorOnResult(
              UpdateElementResult(withCreator(rect(id: 'r10'), bob)),
              scene,
              bob,
            )
            as UpdateElementResult;
    expect(readCreator(stamped.element), isNull);
  });

  test('Remove/Selection/Clipboard/Viewport/SwitchTool/SetSmartLayout 不处理', () {
    final untouched = <ToolResult>[
      RemoveElementResult(const ElementId('x')),
      SetSelectionResult({}),
      UpdateViewportResult(const ViewportState(zoom: 1, offset: Offset.zero)),
      SwitchToolResult(ToolType.select),
      SetSmartLayoutResult(null),
    ];
    for (final result in untouched) {
      expect(
        identical(stampCreatorOnResult(result, Scene(), alice), result),
        isTrue,
      );
    }
  });

  test('controller.applyResult 经过 onPrepareLocalResult 且顺序在剪贴板副作用之前', () {
    final controller = MarkdrawController();
    final order = <String>[];
    controller.onPrepareLocalResult = (result, scene) {
      order.add('prepare');
      return stampCreatorOnResult(result, scene, alice);
    };
    controller.applyResult(AddElementResult(rect(id: 'via-apply')));
    expect(order, ['prepare']);
    final added = controller.editorState.scene.elements.single;
    expect(readCreator(added)?.creatorKey, 'user:a');
    controller.dispose();
  });

  test('undo/redo 保留原归属（不重新盖章、不丢 owner）', () {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    controller.lastCanvasSize = const Size(800, 600);
    controller.onPrepareLocalResult = (result, scene) =>
        stampCreatorOnResult(result, scene, alice);
    controller.insertMindmap(
      MindmapNode(
        text: '中心主题',
        children: [MindmapNode(text: '分支一')],
      ),
    );
    final created = controller.editorState.scene.activeElements
        .where((element) => !element.isCanvasPage)
        .toList();
    expect(created, isNotEmpty);
    for (final element in created) {
      expect(readCreator(element)?.creatorKey, 'user:a');
    }
    controller.undo();
    expect(
      controller.editorState.scene.activeElements.where(
        (element) => !element.isCanvasPage,
      ),
      isEmpty,
    );
    controller.redo();
    final restored = controller.editorState.scene.activeElements
        .where((element) => !element.isCanvasPage)
        .toList();
    for (final element in restored) {
      expect(
        readCreator(element)?.creatorKey,
        'user:a',
        reason: 'redo 恢复原元素及其原归属（v4 §3.1）',
      );
    }
  });

  test('CompoundResult 中绑定文字排在父元素之前也能继承父 owner（两遍处理）', () {
    final parent = withCreator(rect(id: 'arrow3'), alice);
    final boundText = TextElement(
      id: const ElementId('t3'),
      x: 0,
      y: 0,
      width: 5,
      height: 5,
      text: 'label',
      containerId: 'arrow3',
    );
    final stamped =
        stampCreatorOnResult(
              CompoundResult([
                AddElementResult(boundText),
                AddElementResult(parent),
              ]),
              Scene(),
              bob,
            )
            as CompoundResult;
    // v4 §5.2：父元素覆盖为 bob，绑定文字（两遍处理后）继承同一值。
    expect(
      readCreator((stamped.results[0] as AddElementResult).element)?.creatorKey,
      'user:b',
    );
    expect(
      readCreator((stamped.results[1] as AddElementResult).element)?.creatorKey,
      'user:b',
    );
  });
}
