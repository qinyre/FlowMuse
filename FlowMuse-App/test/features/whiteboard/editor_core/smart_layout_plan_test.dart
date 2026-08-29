import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartLayoutTemplateKind', () {
    test('三种模板显示名一一对应', () {
      expect(SmartLayoutTemplateKind.handout.displayName, '图文讲义');
      expect(SmartLayoutTemplateKind.outline.displayName, '要点清单');
      expect(SmartLayoutTemplateKind.inplace.displayName, '原文整理');
    });

    test('枚举恰有三张模板卡', () {
      expect(SmartLayoutTemplateKind.values, hasLength(3));
    });
  });

  group('SmartLayoutRecognizedBlock', () {
    test('fromJson：isSuccess 由 error 决定；边界解析', () {
      final ok = SmartLayoutRecognizedBlock.fromJson({
        'id': 'e0',
        'type': 'text',
        'text': '正文',
        'bounds': {'x': 1, 'y': 2, 'width': 30, 'height': 40},
      });
      expect(ok.isSuccess, isTrue);
      expect(ok.bounds.left, 1);
      expect(ok.bounds.top, 2);

      final failed = SmartLayoutRecognizedBlock.fromJson({
        'id': 'e1',
        'type': 'error',
        'error': 'vlm-no-text',
        'bounds': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      });
      expect(failed.isSuccess, isFalse);
    });
  });

  group('SmartLayoutPlacement.findInsertionBounds', () {
    test('首选点可用时返回首选点', () {
      final area = Rect.fromLTWH(0, 0, 100, 100);
      final result = SmartLayoutPlacement.findInsertionBounds(
        area,
        20,
        20,
        const [],
        preferred: Bounds.fromLTWH(10, 10, 20, 20),
      );
      expect(result!.left, 10);
      expect(result.top, 10);
    });

    test('与占用相交时返回不与占用相交的合法位置', () {
      final area = Rect.fromLTWH(0, 0, 200, 100);
      final occupied = [Bounds.fromLTWH(10, 10, 50, 50)];
      final result = SmartLayoutPlacement.findInsertionBounds(
        area,
        20,
        20,
        occupied,
        preferred: Bounds.fromLTWH(10, 10, 20, 20),
      );
      expect(result, isNotNull);
      final placed = Bounds.fromLTWH(result!.left, result.top, 20, 20);
      expect(placed.left >= area.left, isTrue);
      expect(placed.right <= area.right, isTrue);
      expect(
        occupied.any(placed.intersects),
        isFalse,
        reason: '放置结果不得与占用区相交',
      );
      // 确定性：同一输入重复调用产生相同结果
      final again = SmartLayoutPlacement.findInsertionBounds(
        area,
        20,
        20,
        occupied,
        preferred: Bounds.fromLTWH(10, 10, 20, 20),
      );
      expect(again!.left, result.left);
      expect(again.top, result.top);
    });

    test('区域装不下返回 null', () {
      final result = SmartLayoutPlacement.findInsertionBounds(
        const Rect.fromLTWH(0, 0, 10, 10),
        20,
        20,
        const [],
      );
      expect(result, isNull);
    });
  });

  group('SmartLayoutUtils.mergePageCustomData', () {
    test('合并 pageId 且保留原有 flowMuse 内容', () {
      final merged = SmartLayoutUtils.mergePageCustomData(
        {'flowMuse': {'role': 'mindmap-node'}, 'other': 1},
        'p-1',
      );
      final flowMuse = merged['flowMuse'] as Map<String, Object?>;
      expect(flowMuse['role'], 'mindmap-node');
      expect(flowMuse['pageId'], 'p-1');
      expect(merged['other'], 1);
    });

    test('无 customData 时只创建 flowMuse 映射', () {
      final merged = SmartLayoutUtils.mergePageCustomData(null, 'p-1');
      final flowMuse = merged['flowMuse'] as Map<String, Object?>;
      expect(flowMuse['pageId'], 'p-1');
    });
  });
}
