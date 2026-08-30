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

/// 窄高单字（竖排场景，宽 30 高 40）。
FreedrawElement char(String id, double x, double y) => FreedrawElement(
  id: ElementId(id),
  x: x,
  y: y,
  width: 30,
  height: 40,
  points: const [Point(0, 0), Point(30, 40)],
);

void main() {
  group('SmartLayoutInkClusterer（v2 全页纯几何聚类）', () {
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

    test('跨会话同线相邻单字簇合并（去会话化的核心收益）', () {
      // 现实场景："图1"被会话边界拆成两笔；v2 无会话概念，几何相邻即合并。
      final clusters = SmartLayoutInkClusterer.cluster([
        char('tu', 0, 100),
        char('yi', 36, 104),
      ]);
      expect(clusters.length, 1);
      expect(clusters.first.length, 2);
    });

    test('竖排窄高列整列不拆（"先头小子"场景）', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        char('xian', 500, 100),
        char('tou', 504, 148),
        char('xiao', 498, 196),
        char('zi', 502, 244),
      ]);
      expect(clusters.length, 1);
      expect(clusters.first.length, 4);
    });

    test('多行横排（行宽远大于列宽）不误判为竖排列，按行拆分', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        char('a', 300, 100),
        char('b', 340, 102),
        char('c', 300, 150),
        char('d', 340, 152),
      ]);
      expect(clusters.length, 2);
    });

    test('带内远距（间隙超过一个字高）拆成两块', () {
      final clusters = SmartLayoutInkClusterer.cluster([
        stroke('left', 0, 100, 20),
        stroke('right', 200, 100, 20), // 间隙 160 > max(16,20)
      ]);
      expect(clusters.length, 2);
    });

    test('同行两个短语间隙 1.1 倍字高拆成两块（阅读序 top→left 保序）', () {
      // Given：同一行写"第1句话""第3句话"两个 4 字短语（字高 40），
      // 组间刻意留白 44pt = 1.1×字高——旧阈值 1.2×字高（48）把两句并成
      // 一块导致阅读序错乱（走查实况：1+3/2+4），新阈值 0.8×字高（32）
      // 拆开；组内字符间隙仅 6pt 不得误拆。
      // When：全页纯几何聚类。
      // Then：拆成两块，块序 = 阅读序（左块在前，先 1 后 3）。
      List<FreedrawElement> phrase(String prefix, double startX) => [
        char('${prefix}1', startX, 100),
        char('${prefix}2', startX + 36, 102),
        char('${prefix}3', startX + 72, 99),
        char('${prefix}4', startX + 108, 101),
      ];
      final clusters = SmartLayoutInkClusterer.cluster([
        ...phrase('a', 0), // 右缘 138
        ...phrase('b', 182), // 间隙 44 = 1.1×40（旧阈值 48 会误并）
      ]);
      expect(clusters.length, 2, reason: '同行的两个短语必须拆成两块');
      expect(clusters.first.map((e) => e.id.value), ['a1', 'a2', 'a3', 'a4']);
      expect(clusters.last.map((e) => e.id.value), ['b1', 'b2', 'b3', 'b4']);
    });

    test('杂散小笔画剔除：孤立的勾/点不产生簇', () {
      final dot = FreedrawElement(
        id: const ElementId('dot'),
        x: 10,
        y: 10,
        width: 5,
        height: 5,
        points: const [Point(0, 0), Point(5, 5)],
      );
      expect(SmartLayoutInkClusterer.cluster([dot]), isEmpty);
    });

    test('杂散小笔画剔除：与大块同页也不混入聚类', () {
      final dot = FreedrawElement(
        id: const ElementId('dot'),
        x: 46,
        y: 108,
        width: 5,
        height: 5,
        points: const [Point(0, 0), Point(5, 5)],
      );
      final clusters = SmartLayoutInkClusterer.cluster([
        stroke('a', 0, 100, 20),
        dot,
      ]);
      expect(clusters.length, 1);
      expect(clusters.first.map((e) => e.id.value), ['a']);
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
