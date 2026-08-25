import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/mindmap/mindmap_layout.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/editor/mindmap/mindmap_tree.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/smart_layout/smart_layout_mindmap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MindmapNode tree() => MindmapNode.fromJson({
        'text': '主题',
        'children': [
          {'text': '分支A', 'children': <Object?>[]},
          {
            'text': '分支B',
            'children': [
              {'text': '子B1', 'children': <Object?>[]},
            ],
          },
        ],
      });

  test('空场景时将整棵树放入内容区且相对位置为确定性布局', () {
    final result = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    expect(result, isNotNull);
    final bounds = result!.bounds;
    expect(bounds.left, greaterThanOrEqualTo(72));
    expect(bounds.top, greaterThanOrEqualTo(72));
    expect(bounds.right, lessThanOrEqualTo(72 + 800));
    expect(bounds.bottom, lessThanOrEqualTo(72 + 600));
    // 节点数量：4 节点 → 4 矩形 + 4 文本 + 3 箭头
    final rects = result.elements.whereType<RectangleElement>();
    final edges = result.elements.whereType<ArrowElement>();
    expect(rects.length, 4);
    expect(edges.length, 3);
  });

  test('内容区被占满时返回 null（整页失败）', () {
    final result = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: [Bounds.fromLTWH(72, 72, 800, 600)],
    );
    expect(result, isNull);
  });

  test('确定性：同一输入两次结果元素坐标相同', () {
    final first = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    final second = MindmapStyleEngine.plan(
      node: tree(),
      contentArea: const Rect.fromLTWH(72, 72, 800, 600),
      occupied: const [],
    );
    expect(first!.elements.length, second!.elements.length);
    for (var i = 0; i < first.elements.length; i++) {
      expect(first.elements[i].x, second.elements[i].x);
      expect(first.elements[i].y, second.elements[i].y);
    }
  });
}
