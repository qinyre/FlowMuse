import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MindmapLayout.treeToElements', () {
    test('single root produces one node + no edges', () {
      final tree = MindmapNode(text: '根');
      final elements = MindmapLayout.treeToElements(tree);

      final rects = elements.where((e) => e.type == 'rectangle').toList();
      final arrows = elements.whereType<ArrowElement>().toList();
      expect(rects.length, 1);
      expect(arrows, isEmpty);
    });

    test('root with one child has 1 rect + 1 text + 1 edge', () {
      final tree = MindmapNode(
        text: '根',
        children: [MindmapNode(text: '子1')],
      );
      final elements = MindmapLayout.treeToElements(tree);

      expect(elements.where((e) => e.type == 'rectangle').length, 2);
      expect(elements.where((e) => e.type == 'text').length, 2);
      expect(elements.whereType<ArrowElement>().length, 1);
    });

    test('parent is vertically centred over its children', () {
      // Root with 3 leaf children. The children occupy 3*nodeHeight + 2*vGap.
      // The root should sit at the vertical midpoint of that block.
      final tree = MindmapNode(
        text: '根',
        children: [
          MindmapNode(text: 'A'),
          MindmapNode(text: 'B'),
          MindmapNode(text: 'C'),
        ],
      );
      const originY = 100.0;
      final elements = MindmapLayout.treeToElements(
        tree,
        origin: const Point(50, originY),
      );

      final rects = elements.where((e) => e.type == 'rectangle').toList();
      final root = rects.firstWhere(
        (e) => MindmapUtils.isMindmapNode(e) && e.x == 50.0,
      );
      final children = rects
          .where((e) => MindmapUtils.isMindmapNode(e) && e.x != 50.0)
          .toList()
        ..sort((a, b) => a.y.compareTo(b.y));

      // Children block spans from first child y to last child y + height.
      final blockTop = children.first.y;
      final blockBottom = children.last.y + MindmapLayout.nodeHeight;
      final blockMid = (blockTop + blockBottom) / 2;
      final rootMid = root.y + MindmapLayout.nodeHeight / 2;

      // Root centre should equal children-block centre (within rounding).
      expect((rootMid - blockMid).abs(), lessThan(1.0),
          reason: 'root should be centred over its children');
    });
  });

  group('MindmapLayout.reflowTree', () {
    test('returns UpdateElementResult positions for existing nodes', () {
      // Build a small existing tree, then reflow it with the same root pos.
      final tree = MindmapNode(
        text: '根',
        sourceId: 'root-id',
        children: [
          MindmapNode(text: 'A', sourceId: 'a-id'),
          MindmapNode(text: 'B', sourceId: 'b-id'),
        ],
      );
      final plan = MindmapLayout.reflowTree(
        tree,
        origin: const Point(0, 0),
      );

      // All three nodes carry sourceId, so all appear in nodeUpdates and none
      // in newElements.
      expect(plan.nodeUpdates.length, 3);
      expect(plan.newElements, isEmpty);

      final rootUpdate = plan.nodeUpdates.firstWhere(
        (u) => u.nodeId == 'root-id',
      );
      final aUpdate = plan.nodeUpdates.firstWhere((u) => u.nodeId == 'a-id');
      final bUpdate = plan.nodeUpdates.firstWhere((u) => u.nodeId == 'b-id');

      // Root stays at origin x, centred vertically over A and B.
      expect(rootUpdate.x, 0.0);
      // Children are to the right of the root.
      expect(aUpdate.x, MindmapLayout.nodeWidth + MindmapLayout.hGap);
      expect(bUpdate.x, MindmapLayout.nodeWidth + MindmapLayout.hGap);
      // B sits below A.
      expect(bUpdate.y, greaterThan(aUpdate.y));
    });

    test('new child (no sourceId) appears in newElements with an edge', () {
      // Existing root + one child; reflow with a second child that has no id.
      final tree = MindmapNode(
        text: '根',
        sourceId: 'root-id',
        children: [
          MindmapNode(text: 'A', sourceId: 'a-id'),
          MindmapNode(text: 'newB'), // no sourceId → new node
        ],
      );
      final plan = MindmapLayout.reflowTree(
        tree,
        origin: const Point(0, 0),
      );

      // root + A are updates; newB is a new element (rect + text + edge).
      expect(plan.nodeUpdates.length, 2);
      expect(plan.nodeUpdates.any((u) => u.nodeId == 'root-id'), isTrue);
      expect(plan.nodeUpdates.any((u) => u.nodeId == 'a-id'), isTrue);

      final newRects = plan.newElements.where((e) => e.type == 'rectangle');
      expect(newRects.length, 1);
      final newEdges = plan.newElements.whereType<ArrowElement>();
      expect(newEdges.length, 1);
    });

    test('depth-based styling differs across levels', () {
      final (rootBg, _, _, _) = MindmapLayout.styleForNode(
        depth: 0,
        branchIndex: -1,
      );
      final (branchBg, _, _, _) = MindmapLayout.styleForNode(
        depth: 1,
        branchIndex: 0,
      );
      final (leafBg, _, _, _) = MindmapLayout.styleForNode(
        depth: 2,
        branchIndex: 0,
      );

      // Root uses the deep blue level style; branch uses palette[0] (red);
      // leaf is a lightened tint of the branch colour — all distinct.
      expect(rootBg, '#1971c2');
      expect(branchBg, '#fa5252');
      expect(leafBg, isNot(branchBg));
      expect(leafBg, isNot(rootBg));
    });

    test('different branches get different colours', () {
      final (bg0, _, _, _) = MindmapLayout.styleForNode(
        depth: 1,
        branchIndex: 0,
      );
      final (bg1, _, _, _) = MindmapLayout.styleForNode(
        depth: 1,
        branchIndex: 1,
      );
      expect(bg0, isNot(bg1));
    });

    test('adding a child re-centres the parent over all children', () {
      // Simulate the auto-reflow: a root with one existing child, then a
      // second child is appended. After reflow the root should sit at the
      // vertical midpoint of BOTH children (not just the first).
      const originY = 0.0;

      // Before: root + 1 child.
      final before = MindmapLayout.reflowTree(
        MindmapNode(
          text: '根',
          sourceId: 'root',
          children: [MindmapNode(text: 'A', sourceId: 'a')],
        ),
        origin: const Point(0, originY),
      );
      final rootBefore = before.nodeUpdates.firstWhere((u) => u.nodeId == 'root');

      // After: root + 2 children (B added, no sourceId).
      final after = MindmapLayout.reflowTree(
        MindmapNode(
          text: '根',
          sourceId: 'root',
          children: [
            MindmapNode(text: 'A', sourceId: 'a'),
            MindmapNode(text: 'B'),
          ],
        ),
        origin: const Point(0, originY),
      );
      final rootAfter = after.nodeUpdates.firstWhere((u) => u.nodeId == 'root');
      final aAfter = after.nodeUpdates.firstWhere((u) => u.nodeId == 'a');

      // With 2 children, the root should move down to stay centred.
      expect(rootAfter.y, greaterThan(rootBefore.y),
          reason: 'root should shift down when a second child is added');
      // Root centre should match the midpoint of A and B.
      final bRect = after.newElements.firstWhere((e) => e.type == 'rectangle');
      final aMid = aAfter.y + MindmapLayout.nodeHeight / 2;
      final bMid = bRect.y + MindmapLayout.nodeHeight / 2;
      final rootMid = rootAfter.y + MindmapLayout.nodeHeight / 2;
      expect((rootMid - (aMid + bMid) / 2).abs(), lessThan(1.0),
          reason: 'root centre should equal children midpoint');
    });
  });

  group('MindmapNode', () {
    test('fromJson accepts text/topic/title keys', () {
      expect(MindmapNode.fromJson({'text': 'a'}).text, 'a');
      expect(MindmapNode.fromJson({'topic': 'b'}).text, 'b');
      expect(MindmapNode.fromJson({'title': 'c'}).text, 'c');
    });

    test('fromJson parses nested children', () {
      final tree = MindmapNode.fromJson({
        'text': 'root',
        'children': [
          {'topic': 'child1'},
          {
            'title': 'child2',
            'children': [
              {'text': 'grandchild'},
            ],
          },
        ],
      });
      expect(tree.text, 'root');
      expect(tree.children.length, 2);
      expect(tree.children[0].text, 'child1');
      expect(tree.children[1].children.length, 1);
      expect(tree.children[1].children[0].text, 'grandchild');
    });

    test('toJson round-trips through fromJson', () {
      final original = MindmapNode(
        text: 'r',
        children: [MindmapNode(text: 'c')],
      );
      final roundTripped = MindmapNode.fromJson(original.toJson());
      expect(roundTripped.text, 'r');
      expect(roundTripped.children.length, 1);
      expect(roundTripped.children[0].text, 'c');
    });
  });
}
