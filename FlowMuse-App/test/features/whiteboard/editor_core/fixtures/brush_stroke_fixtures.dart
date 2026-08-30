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

// ---------------------------------------------------------------------------
// 自然介质 T0 夹具（铅笔与毛笔重构计划，2026-08-30）。
//
// 与上方 Issue #5 夹具同构：确定性数据、无时间/随机依赖。压感恒压组
// 供 N2/N3/N6 浓淡-宽度口径使用；八笔画供毛笔形态 fixture 使用。
// ---------------------------------------------------------------------------

/// 压感测试共享轨迹：41 点缓波线，弧长约 368，足以容纳弧长 40%～60%
/// 中心带与 2px 步长的边缘采样。
List<Point> _pressureTrajectory() => [
  for (var i = 0; i <= 40; i++) Point(9.0 * i, 12 * math.sin(math.pi * i / 40)),
];

/// 铅笔轻压恒压：N2/N3 口径的轻压端。
final pencilLightStroke = BrushStrokeFixture(
  name: 'pencilLightStroke',
  description: '自然介质压感轨迹，恒压 0.20',
  points: _pressureTrajectory(),
  pressures: List<double>.filled(41, 0.20),
);

/// 铅笔中压恒压：测试纸中压行。
final pencilMediumStroke = BrushStrokeFixture(
  name: 'pencilMediumStroke',
  description: '自然介质压感轨迹，恒压 0.50',
  points: _pressureTrajectory(),
  pressures: List<double>.filled(41, 0.50),
);

/// 铅笔重压恒压：N2/N3 口径的重压端。
final pencilHeavyStroke = BrushStrokeFixture(
  name: 'pencilHeavyStroke',
  description: '自然介质压感轨迹，恒压 0.80',
  points: _pressureTrajectory(),
  pressures: List<double>.filled(41, 0.80),
);

/// 铅笔单调压力坡道：0.15 → 0.85，供坡道滑窗断言（不允许逆压力方向
/// 大幅回落）。
final pencilPressureRamp = BrushStrokeFixture(
  name: 'pencilPressureRamp',
  description: '自然介质压感轨迹，压力 0.15→0.85 单调爬升',
  points: _pressureTrajectory(),
  pressures: [for (var i = 0; i <= 40; i++) 0.15 + 0.70 * i / 40],
);

/// 铅笔慢写（密集采样）：同一几何，点距 ≈ 9。
final pencilSlowTrajectory = BrushStrokeFixture(
  name: 'pencilSlowTrajectory',
  description: '缓波线密集采样（41 点），恒压 0.5',
  points: _pressureTrajectory(),
  pressures: List<double>.filled(41, 0.5),
);

/// 铅笔快写（稀疏采样）：同一几何抽稀 4 倍。
final pencilFastTrajectory = BrushStrokeFixture(
  name: 'pencilFastTrajectory',
  description: '缓波线稀疏采样（11 点），恒压 0.5',
  points: [for (var i = 0; i <= 40; i += 4) _pressureTrajectory()[i]],
  pressures: List<double>.filled(11, 0.5),
);

/// 铅笔 90° 直角折线：转角颗粒覆盖与退化。
final pencilRightAngleCorner = BrushStrokeFixture(
  name: 'pencilRightAngleCorner',
  description: 'L 形 90° 折线，恒压 0.6',
  points: [
    for (var i = 0; i <= 12; i++) Point(10.0 * i, 0),
    for (var i = 1; i <= 12; i++) Point(120.0, 10.0 * i),
  ],
  pressures: List<double>.filled(25, 0.6),
);

/// 铅笔短点：两点微移，验证单点/短划退化。
final pencilShortDot = BrushStrokeFixture(
  name: 'pencilShortDot',
  description: '两点短点（3px），恒压 0.6',
  points: const [Point(0, 0), Point(3, 1)],
  pressures: const [0.6, 0.6],
);

/// 多笔画场景：若干单笔 fixture 按序叠加（交叉排线/重复覆盖等）。
class BrushStrokeScene {
  const BrushStrokeScene({
    required this.name,
    required this.description,
    required this.strokes,
  });

  final String name;
  final String description;
  final List<BrushStrokeFixture> strokes;
}

/// 铅笔交叉排线：3 横 × 3 纵交叉，恒压 0.5，验证交叉处自然加深与
/// 颗粒不因重叠产生周期性花纹。
final pencilCrossHatchScene = BrushStrokeScene(
  name: 'pencilCrossHatchScene',
  description: '3 横 × 3 纵交叉排线，恒压 0.5',
  strokes: [
    for (var row = 0; row < 3; row++)
      BrushStrokeFixture(
        name: 'crossHatchH$row',
        description: '排线横线 $row',
        points: [for (var i = 0; i <= 16; i++) Point(8.0 * i, 22.0 * row)],
        pressures: List<double>.filled(17, 0.5),
      ),
    for (var col = 0; col < 3; col++)
      BrushStrokeFixture(
        name: 'crossHatchV$col',
        description: '排线竖线 $col',
        points: [
          for (var i = 0; i <= 10; i++)
            Point(20.0 + 56.0 * col, -44.0 + 13.0 * i),
        ],
        pressures: List<double>.filled(11, 0.5),
      ),
  ],
);

/// 铅笔重复覆盖：同一条线原位重复 3 次，验证 sourceOver 自然变深
/// （N4 口径：1/2/3 次平均 darkness 严格递增）。
final pencilRepeatedOverlayScene = BrushStrokeScene(
  name: 'pencilRepeatedOverlayScene',
  description: '同一水平线原位重复 3 次，恒压 0.5',
  strokes: [
    for (var n = 0; n < 3; n++)
      BrushStrokeFixture(
        name: 'overlay$n',
        description: '重复覆盖第 ${n + 1} 笔',
        points: [for (var i = 0; i <= 30; i++) Point(10.0 * i, 0)],
        pressures: List<double>.filled(31, 0.5),
      ),
  ],
);

// --- 毛笔八笔画（横竖撇捺点折钩提）与补充 fixture ---

/// 平滑压力包络：t∈[0,1] 从 [start] 过渡到 [end]，中段按 [arch] 拱起。
double _pressureEnvelope(double t, double start, double end, double arch) {
  final base = start + (end - start) * t;
  return (base + arch * math.sin(math.pi * t)).clamp(0.02, 1.0);
}

/// 横：起笔轻、中段重、收笔轻的缓拱横画。
List<Point> _hengPoints() => [
  for (var i = 0; i <= 24; i++)
    Point(6.5 * i, 16 - 6 * math.sin(math.pi * i / 24)),
];
final brushHeng = BrushStrokeFixture(
  name: 'brushHeng',
  description: '横：24 点缓拱，压力 0.30→0.75→0.28',
  points: _hengPoints(),
  pressures: [
    for (var i = 0; i <= 24; i++) _pressureEnvelope(i / 24, 0.30, 0.28, 0.45),
  ],
);

/// 横（无尾部降压）：N8 无降压 fixture，尾部压力保持中段水平，
/// v1 固定对称 taper 会在该 fixture 上暴露"无降压仍出长矛尖"。
final brushHengNoTailDrop = BrushStrokeFixture(
  name: 'brushHengNoTailDrop',
  description: '横：同横几何，恒压 0.60（尾部无降压）',
  points: _hengPoints(),
  pressures: List<double>.filled(25, 0.60),
);

/// 竖：悬针竖，尾部压力自然衰减。
final brushShu = BrushStrokeFixture(
  name: 'brushShu',
  description: '竖：20 点直竖，压力 0.50→0.65→0.08',
  points: [for (var i = 0; i <= 20; i++) Point(3.0 * (1 - i / 20), 7.5 * i)],
  pressures: [
    for (var i = 0; i <= 20; i++) _pressureEnvelope(i / 20, 0.50, 0.08, 0.15),
  ],
);

/// 撇：右上向左下出锋撇。
final brushPie = BrushStrokeFixture(
  name: 'brushPie',
  description: '撇：22 点弧撇，压力 0.70→0.05',
  points: [
    for (var i = 0; i <= 22; i++)
      Point(
        64.0 * math.pow(1 - i / 22, 1.35),
        5.5 * i + 6 * math.sin(math.pi * i / 44),
      ),
  ],
  pressures: [
    for (var i = 0; i <= 22; i++) _pressureEnvelope(i / 22, 0.70, 0.05, 0.05),
  ],
);

/// 捺：左上向右下，捺脚加重后出锋（N8 有降压 fixture）。
///
/// 压降包络按 N8 契约设计：峰值在 62% 弧长，其后 2.5 幂衰减，保证
/// "距尾 2×size" 探针处压力 ≤0.10——宽度曲线存在 0.16×base 底
///（§3.5 候选），探针压力不压到该量级则自然收束宽度到不了中段 45%。
final brushNa = BrushStrokeFixture(
  name: 'brushNa',
  description: '捺：26 点，压力 0.20→0.80（62% 处）→0.03 二点五次幂衰减出锋',
  points: [
    for (var i = 0; i <= 26; i++)
      Point(4.6 * i, 4.0 * i + 7 * math.sin(math.pi * i / 26)),
  ],
  pressures: [
    for (var i = 0; i <= 26; i++)
      i / 26 <= 0.62
          ? 0.20 + 0.60 * (i / 26 / 0.62)
          : math.max(0.03, 0.80 * math.pow(1 - (i / 26 - 0.62) / 0.38, 2.5)),
  ],
);

/// 点：短促点画，压力快起快落。
final brushDian = BrushStrokeFixture(
  name: 'brushDian',
  description: '点：10 点短点画，压力 0.30→0.78→0.15',
  points: [for (var i = 0; i <= 10; i++) Point(2.2 * i, 2.6 * i * i / 10)],
  pressures: [
    for (var i = 0; i <= 10; i++) _pressureEnvelope(i / 10, 0.30, 0.15, 0.48),
  ],
);

/// 折：横后急转向下的折画（转角 fixture）。
final brushZhe = BrushStrokeFixture(
  name: 'brushZhe',
  description: '折：横 12 点 + 竖 10 点，90° 折角，恒压 0.60',
  points: [
    for (var i = 0; i <= 12; i++)
      Point(7.0 * i, 14 - 4 * math.sin(math.pi * i / 12)),
    for (var i = 1; i <= 10; i++) Point(84.0, 10.0 + 8.5 * i),
  ],
  pressures: List<double>.filled(23, 0.60),
);

/// 钩：竖末向左上挑钩，钩段压力快速衰减。
/// 钩点位相对竖终点 (0,112) 向左上挑——必须与竖尾连续，断点会生成
/// 意外的横向连接边（视觉预审在 spike 上暴露过一次）。
final brushGou = BrushStrokeFixture(
  name: 'brushGou',
  description: '钩：竖 14 点 + 钩 6 点（连续），压力 0.55→0.60→0.08',
  points: [
    for (var i = 0; i <= 14; i++) Point(2.0 * (1 - i / 14), 8.0 * i),
    for (var i = 1; i <= 6; i++) Point(-4.6 * i, 112.0 - 3.4 * i),
  ],
  pressures: [
    for (var i = 0; i <= 14; i++) _pressureEnvelope(i / 14, 0.55, 0.60, 0.05),
    for (var i = 1; i <= 6; i++) 0.60 * (1 - 0.9 * i / 6),
  ],
);

/// 提：左下向右上提笔出锋。
final brushTi = BrushStrokeFixture(
  name: 'brushTi',
  description: '提：16 点上挑，压力 0.75→0.10',
  points: [
    for (var i = 0; i <= 16; i++)
      Point(5.2 * i, 88 - 4.4 * i - 4 * math.sin(math.pi * i / 16)),
  ],
  pressures: [
    for (var i = 0; i <= 16; i++) _pressureEnvelope(i / 16, 0.75, 0.10, 0.05),
  ],
);

/// 毛笔压力坡道：轻→重，供 N6 提按口径。
final brushPressureRamp = BrushStrokeFixture(
  name: 'brushPressureRamp',
  description: '水平线，压力 0.15→0.85 单调爬升',
  points: [for (var i = 0; i <= 40; i++) Point(9.0 * i, 0)],
  pressures: [for (var i = 0; i <= 40; i++) 0.15 + 0.70 * i / 40],
);

/// 毛笔 S 曲线：连续两个反向弯，验证方向滞后无振荡。
final brushSCurve = BrushStrokeFixture(
  name: 'brushSCurve',
  description: 'S 曲线 33 点，压力 0.30+0.40·sin(2πt)',
  points: [
    for (var i = 0; i <= 32; i++)
      Point(11.0 * i, 26 * math.sin(2 * math.pi * i / 32)),
  ],
  pressures: [
    for (var i = 0; i <= 32; i++) 0.30 + 0.40 * math.sin(2 * math.pi * i / 32),
  ],
);

/// 毛笔短点：N9 单点/短划退化。
final brushShortDot = BrushStrokeFixture(
  name: 'brushShortDot',
  description: '两点短点（5px），恒压 0.55',
  points: const [Point(0, 0), Point(4, 5)],
  pressures: const [0.55, 0.55],
);

/// 毛笔八笔画全集（供测试纸遍历）。
final List<BrushStrokeFixture> brushCalligraphyStrokes = [
  brushHeng,
  brushShu,
  brushPie,
  brushNa,
  brushDian,
  brushZhe,
  brushGou,
  brushTi,
];

/// 按目标点距对 fixture 做线性重采样（采样率稳定性 fixture 生成器）。
///
/// 沿折线以 [targetStep] 弧长步长线性插值取点，压力同步线性插值；
/// 首尾点始终保留。稀疏/正常/密集三种采样率由此生成，防止效果依赖
/// 设备事件频率（T0 工作项 5）。
BrushStrokeFixture resampleFixture(BrushStrokeFixture f, double targetStep) {
  final src = f.points;
  final out = <Point>[src.first];
  final outP = <double>[f.pressures.first];
  var carry = 0.0;
  for (var i = 0; i < src.length - 1; i++) {
    final a = src[i];
    final b = src[i + 1];
    final seg = a.distanceTo(b);
    if (seg <= 0) continue;
    var traveled = 0.0;
    while (carry + (seg - traveled) >= targetStep) {
      final need = targetStep - carry;
      traveled += need;
      final u = traveled / seg;
      out.add(Point(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u));
      final pa = f.pressures[i];
      final pb = f.pressures[i + 1];
      outP.add(pa + (pb - pa) * u);
      carry = 0.0;
    }
    carry += seg - traveled;
  }
  if (out.last != src.last) {
    out.add(src.last);
    outP.add(f.pressures.last);
  }
  return BrushStrokeFixture(
    name: '${f.name}@step${targetStep.toStringAsFixed(1)}',
    description: '${f.description}（重采样步长 $targetStep）',
    points: out,
    pressures: outP,
  );
}
