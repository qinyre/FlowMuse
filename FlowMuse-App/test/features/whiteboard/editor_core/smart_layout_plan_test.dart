import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartLayoutStyle', () {
    test('fromWire 识别四种风格，未知回落 inPlace', () {
      expect(SmartLayoutStyle.fromWire('ppt'), SmartLayoutStyle.ppt);
      expect(SmartLayoutStyle.fromWire('mindmap'), SmartLayoutStyle.mindmap);
      expect(SmartLayoutStyle.fromWire('article'), SmartLayoutStyle.article);
      expect(SmartLayoutStyle.fromWire('in_place'), SmartLayoutStyle.inPlace);
      expect(SmartLayoutStyle.fromWire('diagram'), SmartLayoutStyle.inPlace);
      expect(SmartLayoutStyle.fromWire(null), SmartLayoutStyle.inPlace);
    });

    test('wireName 与 displayName 一一对应', () {
      expect(SmartLayoutStyle.ppt.wireName, 'ppt');
      expect(SmartLayoutStyle.mindmap.wireName, 'mindmap');
      expect(SmartLayoutStyle.inPlace.wireName, 'in_place');
      expect(SmartLayoutStyle.ppt.displayName, 'PPT 式排版');
      expect(SmartLayoutStyle.mindmap.displayName, '思维导图');
    });
  });

  group('SmartLayoutComposeRequest', () {
    test('toJson 包含 elements 与 layoutHint；缺省时不输出', () {
      final request = SmartLayoutComposeRequest(
        pages: const [],
        blocks: const [],
        elements: [
          SmartLayoutElementRef(
            id: 'img-1',
            type: 'image',
            bounds: Bounds.fromLTWH(0, 0, 10, 10),
            pageId: 'p-1',
            groupIds: const ['g-1'],
          ),
        ],
        layoutHint: SmartLayoutStyle.ppt,
      );
      final json = request.toJson();
      expect(json['layoutHint'], 'ppt');
      final elements = json['elements'] as List;
      final element = elements.first as Map;
      expect(element['id'], 'img-1');
      expect(element['type'], 'image');
      expect(element['locked'], isNull); // 未设置不输出
      expect(element['groupIds'], ['g-1']);

      final plain = SmartLayoutComposeRequest(
        pages: const [],
        blocks: const [],
      ).toJson();
      expect(plain.containsKey('elements'), isFalse);
      expect(plain.containsKey('layoutHint'), isFalse);
    });
  });

  group('SmartLayoutLayoutDecision', () {
    test('fromJson 解析 mindmap structure', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'mindmap',
        'confidence': 0.9,
        'structure': {
          'root': {
            'text': '主题',
            'blockIds': ['blk-1'],
            'children': [
              {'text': '分支', 'blockIds': ['blk-2'], 'children': []},
            ],
          },
        },
      });
      expect(decision.style, SmartLayoutStyle.mindmap);
      expect(decision.confidence, closeTo(0.9, 0.001));
      expect(decision.mindmapStructure, isNotNull);
      expect(decision.mindmapStructure!.root.text, '主题');
      expect(decision.mindmapStructure!.root.children.length, 1);
      expect(decision.mindmapStructure!.root.blockIds, ['blk-1']);
      expect(decision.pptStructure, isNull);
    });

    test('fromJson 解析 ppt structure 且未知 role 归为 body', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'ppt',
        'confidence': 2.0, // 钳制
        'structure': {
          'groups': [
            {'role': 'title', 'elementIds': ['blk-1']},
            {'role': 'unknown', 'elementIds': ['img-1']},
          ],
        },
      });
      expect(decision.confidence, 1.0);
      expect(decision.pptStructure, isNotNull);
      expect(decision.pptStructure!.groups.length, 2);
      expect(decision.pptStructure!.groups[1].role, 'body');
    });

    test('未知 style 回落 inPlace 且结构为空', () {
      final decision = SmartLayoutLayoutDecision.fromJson({
        'style': 'diagram',
        'structure': {'root': {'text': 'x'}},
      });
      expect(decision.style, SmartLayoutStyle.inPlace);
      expect(decision.mindmapStructure, isNull);
      expect(decision.pptStructure, isNull);
    });
  });

  group('SmartLayoutResponse', () {
    test('layout 缺失时解析为 null（旧服务端兼容）', () {
      final response = SmartLayoutResponse.fromJson({
        'document': {
          'version': 1,
          'generatedAt': 1,
          'blocks': <Object?>[],
        },
        'pages': <Object?>[],
      });
      expect(response.layout, isNull);
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
