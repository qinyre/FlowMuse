import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';

/// 五组固定笔迹输入（Issue #5 T0 基线夹具）。
///
/// 全部为确定性数据：不依赖时间、随机数或设备 DPR。pressures 与 points
/// 等长（真压感路径）；模拟压感路径由调用方传 null pressures。
class BrushStrokeFixture {
  const BrushStrokeFixture({
    required this.name,
    required this.description,
    required this.points,
    required this.pressures,
  });

  final String name;
  final String description;
  final List<Point> points;
  final List<double> pressures;

  /// 原始输入点折线总长（未插值、未 streamline）。
  double get rawPolylineLength {
    var total = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      final dx = points[i + 1].x - points[i].x;
      final dy = points[i + 1].y - points[i].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }
}

/// 短水平线：验证起收端帽与最短笔迹门控。
final shortHorizontal = BrushStrokeFixture(
  name: 'shortHorizontal',
  description: '3 点短横线，恒压 0.5',
  points: const [Point(0, 0), Point(8, 0), Point(16, 0)],
  pressures: const [0.5, 0.5, 0.5],
);

/// 慢速弧线：密集采样（点距小 ≈ 慢写）。
final slowArc = BrushStrokeFixture(
  name: 'slowArc',
  description: '21 点半圆弧，恒压 0.5，密集采样',
  points: [
    for (var i = 0; i <= 20; i++)
      Point(-40 + 4.0 * i, -40 * math.sin(math.pi * i / 20)),
  ],
  pressures: List<double>.filled(21, 0.5),
);

/// 快速弧线：同一几何、稀疏采样（点距大 ≈ 快写）。
final fastArc = BrushStrokeFixture(
  name: 'fastArc',
  description: '5 点半圆弧，恒压 0.5，稀疏采样',
  points: [
    for (var i = 0; i <= 4; i++)
      Point(-40 + 20.0 * i, -40 * math.sin(math.pi * i / 4)),
  ],
  pressures: List<double>.filled(5, 0.5),
);

/// 压力曲线：轻→重→轻，用于压感差异断言（A2/A3）。
final pressureRamp = BrushStrokeFixture(
  name: 'pressureRamp',
  description: '16 点水平线，压力 0.15→1.0→0.15',
  points: [for (var i = 0; i < 16; i++) Point(8.0 * i, 0)],
  pressures: [
    for (var i = 0; i < 16; i++) 0.15 + 0.85 * math.sin(math.pi * i / 15),
  ],
);

/// 拐角折线：两个急转角，验证转角处轮廓行为。
final cornerPolyline = BrushStrokeFixture(
  name: 'cornerPolyline',
  description: '7 点折线，两个急转角，恒压 0.6',
  points: const [
    Point(0, 0),
    Point(30, 30),
    Point(60, 0),
    Point(90, 30),
    Point(120, 0),
    Point(150, 30),
    Point(180, 0),
  ],
  pressures: List<double>.filled(7, 0.6),
);

/// 全部夹具（供遍历型基线测试）。
final List<BrushStrokeFixture> allBrushStrokeFixtures = [
  shortHorizontal,
  slowArc,
  fastArc,
  pressureRamp,
  cornerPolyline,
];
