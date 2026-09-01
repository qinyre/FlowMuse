import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_obstacle.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/oriented_layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/smart_layout_geometry_kernel.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-301A 预算验收：3000 笔画障碍 + 100 排版块查询。
/// 预算断言用确定性评估计数（evaluationCount），不依赖墙上时钟；
/// 正确性用逐块暴力 oracle（3000×100 次闭盒求交）交叉验证零漏检。
void main() {
  // 确定性 LCG（种子固定，双跑一致）。
  int lcg(int state) => (1103515245 * state + 12345) & 0x7fffffff;

  test('3000 笔画/100 块：评估计数在预算内且逐块 oracle 零漏检', () {
    var state = 20260901;
    final strokes = <LayoutObstacle>[];
    // 3000 笔画：页 4000×3000，笔画盒 30~80（确定性参数化）。
    for (var i = 0; i < 3000; i++) {
      state = lcg(state);
      final x = (state % 4000).toDouble();
      state = lcg(state);
      final y = (state % 3000).toDouble();
      state = lcg(state);
      final w = 30.0 + (state % 50);
      state = lcg(state);
      final h = 12.0 + (state % 40);
      strokes.add(LayoutObstacle(
        id: 'ink-$i',
        conservativeBounds: LayoutRect(left: x, top: y, width: w, height: h),
        obb: _axisAlignedObb(x, y, w, h),
      ));
    }
    final index = SmartLayoutGeometryKernel.buildIndex(strokes);

    final blocks = <LayoutRect>[];
    for (var i = 0; i < 100; i++) {
      state = lcg(state);
      final x = (state % 3700).toDouble();
      state = lcg(state);
      final y = (state % 2700).toDouble();
      blocks.add(LayoutRect(left: x, top: y, width: 260, height: 180));
    }

    final evaluationsBefore = index.evaluationCount;
    var totalOracleHits = 0;
    for (final block in blocks) {
      final hits = index.queryIntersecting(block).map((o) => o.id).toSet();
      // 暴力 oracle：全量 3000 笔画闭盒求交，零漏检对照。
      for (final stroke in strokes) {
        if (block.intersects(stroke.conservativeBounds)) {
          totalOracleHits++;
          expect(hits, contains(stroke.id),
              reason: '块 ${block.toString()} 漏掉 ${stroke.id}');
        }
      }
    }
    final used = index.evaluationCount - evaluationsBefore;

    // 预算：100 块总评估必须远小于全配对 3000×100=300000；
    // 上界 24000（每块平均 240 次评估，覆盖 cell 半径内少量笔画）。
    expect(used, lessThan(24000),
        reason: '总评估 $used 超预算（全配对为 300000）');
    // 防退化：真实命中存在且评估确实发生（索引不是空转）。
    expect(totalOracleHits, greaterThan(0));
    expect(used, greaterThanOrEqualTo(100));
    // ignore: avoid_print
    print('budget: evaluations=$used oracleHits=$totalOracleHits '
        'avgPerQuery=${(used / 100).toStringAsFixed(1)}');
  });

  test('聚集分布压力：局部密集页仍零漏检', () {
    var state = 777;
    int next(int mod) {
      state = lcg(state);
      return state % mod;
    }
    // 1500 笔画挤在 600×600 区域（密集 cell），100 块查询同区域。
    final strokes = <LayoutObstacle>[];
    for (var i = 0; i < 1500; i++) {
      final x = next(560).toDouble();
      final y = next(560).toDouble();
      strokes.add(LayoutObstacle(
        id: 'dense-$i',
        conservativeBounds: LayoutRect(left: x, top: y, width: 40, height: 25),
        obb: _axisAlignedObb(x, y, 40, 25),
      ));
    }
    final index = SmartLayoutGeometryKernel.buildIndex(strokes);
    for (var i = 0; i < 100; i++) {
      final block = LayoutRect(
        left: next(500).toDouble(),
        top: next(500).toDouble(),
        width: 100,
        height: 100,
      );
      final hits = index.queryIntersecting(block).map((o) => o.id).toSet();
      for (final stroke in strokes) {
        if (block.intersects(stroke.conservativeBounds)) {
          expect(hits, contains(stroke.id));
        }
      }
    }
  });
}

/// 手工障碍的轴对齐 OBB（与保守盒重合）。
OrientedLayoutRect _axisAlignedObb(double x, double y, double w, double h) =>
    OrientedLayoutRect(
      centerX: x + w / 2,
      centerY: y + h / 2,
      halfWidth: w / 2,
      halfHeight: h / 2,
    );
