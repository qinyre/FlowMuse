import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter_test/flutter_test.dart';

FreedrawElement stroke(String id, double x, double y, double h) =>
    FreedrawElement(
      id: ElementId(id),
      x: x,
      y: y,
      width: 40,
      height: h,
      points: const [Point(0, 0), Point(40, 20)],
    );

void main() {
  group('SmartLayoutInkClusterer', () {
    test('同一行的多笔合成一个簇', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        stroke('a', 0, 100, 20),
        stroke('b', 60, 102, 20),
        stroke('c', 120, 99, 20),
      ]);
      expect(clusters.length, 1);
      expect(clusters.first.length, 3);
    });

    test('不同行的笔迹拆成多个簇（按中心 y）', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        stroke('a', 0, 100, 20), // 行1
        stroke('b', 0, 140, 20), // 行2（距 30 > 阈值 max(14,12)）
        stroke('c', 0, 200, 20), // 行3
      ]);
      expect(clusters.length, 3);
    });

    test('同会话三句话（间隔 40）被拆为 3 簇', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        stroke('a', 0, 100, 20),
        stroke('city', 0, 145, 20),
        stroke('ppt', 0, 190, 20),
      ]);
      expect(clusters.length, 3);
    });

    test('单笔或空输入保持单簇', () {
      expect(SmartLayoutInkClusterer.cluster([]).length, 0);
      expect(SmartLayoutInkClusterer.cluster([stroke('a', 0, 0, 20)]).length, 1);
    });

    test('竖排列（x 窄 y 长）判定为竖排', () {
      expect(SmartLayoutInkClusterer.isVerticalColumn([
        stroke('a', 500, 100, 40),
        stroke('b', 505, 150, 40),
        stroke('c', 498, 200, 40),
      ]), isTrue);
    });

    test('宽横排多行（行宽远大于行距）不判为竖排', () {
      expect(SmartLayoutInkClusterer.isVerticalColumn([
        stroke('a', 0, 100, 20),
        stroke('b', 80, 145, 20),
        stroke('c', 160, 190, 20),
      ]), isFalse);
    });

    test('横排多行（每行较宽）不判为竖排', () {
      expect(SmartLayoutInkClusterer.isVerticalColumn([
        stroke('a', 0, 100, 20),
        stroke('b', 60, 145, 20),
        stroke('c', 30, 190, 20),
      ]), isFalse);
    });

    test('确定性：随机输入顺序结果一致', () {
      final input = [
        stroke('a', 0, 100, 20),
        stroke('b', 0, 145, 20),
        stroke('c', 0, 190, 20),
      ];
      final reversed = input.reversed.toList();
      final first = SmartLayoutInkClusterer.cluster(input);
      final second = SmartLayoutInkClusterer.cluster(reversed);
      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(
          first[i].map((e) => e.id.value).toList(),
          second[i].map((e) => e.id.value).toList(),
        );
      }
    });
  });
}
