import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/element_renderer.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/rough/rough_canvas_adapter.dart';

// ---------------------------------------------------------------------------
// 自然介质十项冻结指标（铅笔与毛笔重构计划 T0，2026-08-30）。
//
// 本文件是 N2/N3/N5/N6/N8/N11/N12/N13/N16/N18 验收的唯一算式来源：
// T11 只能复用这里的常量与函数，不得重新挑更宽松的口径。修改任何
// 算式或阈值等同修订计划，必须回填计划书并重新过阶段复核门。
//
// 十项指标与计划 T0 工作项编号一一对应：
//  1 渲染底图          NaturalMediaSheetRenderer（白底契约 + 透明底变体）
//  2 着墨像素          NaturalMediaRaster.darkness / isInk
//  3 共同中心带浓度    CenterBandDarkness.commonBandMeanDarkness
//  4 有效宽度          WidthProfile.medianCenterWidth / widthAtArcFraction
//  5 边缘不规则度      EdgeIrregularity.residualRmsOverWidth
//  6 固定周期峰        Periodicity.maxAutocorrelationPeak
//  7 弧长前缀          ArcPrefixMask（"前 90%" 的唯一定义）
//  8 像素差            PixelDiff.differingInkRatio
//  9 SVG 趋势          MetricOrdering.sameOrdering
// 10 分块结构          NaturalMediaPrimitiveRef / multisetDiff / verticesEqual
// ---------------------------------------------------------------------------

/// T0 冻结的全局阈值与口径常量。
class NaturalMediaFrozen {
  NaturalMediaFrozen._();

  // --- 指标 2：着墨像素 ---
  /// 相对亮度权值（Rec.709）。
  static const double lumaR = 0.2126;
  static const double lumaG = 0.7152;
  static const double lumaB = 0.0722;

  /// darkness = 1 - Y/255；darkness >= 16/255 计为着墨。
  static const double inkDarknessThreshold = 16 / 255;

  // --- 指标 3：共同中心带 ---
  /// 中心带弧长范围 40%～60%，取样步长 2%。
  static const double centerBandArcStart = 0.40;
  static const double centerBandArcEnd = 0.60;
  static const double centerBandArcStep = 0.02;

  /// 共同半宽 = 轻/重两笔中位有效宽度较小值的 45%。
  static const double commonBandHalfWidthRatio = 0.45;

  /// 中心带内法向取样步长（逻辑像素）。
  static const double centerBandNormalStep = 0.5;

  // --- 指标 4：有效宽度 ---
  /// 法向扫描步长 1px；扫描半径上限 = max(48, 12×strokeWidth)。
  static const double widthScanStep = 1.0;
  static double widthScanRadius(double strokeWidth) =>
      math.max(48.0, 12 * strokeWidth);

  // --- 指标 5：边缘不规则度 ---
  /// 边缘采样：固定弧长步长 2px，范围 10%～90%（避开起收端帽）。
  static const double edgeArcStart = 0.10;
  static const double edgeArcEnd = 0.90;
  static const double edgeArcStepPx = 2.0;
  static const int edgeMovingAverageWindow = 9;

  // --- 指标 6：固定周期峰 ---
  /// 残差归一化自相关 lag 2～32（样本单位 = edgeArcStepPx 像素）。
  static const int autocorrMinLag = 2;
  static const int autocorrMaxLag = 32;

  // --- 指标 7：弧长前缀 ---
  /// "前 90%" = owned edge 累计原始弧长 <= 0.9 × totalLength。
  static const double arcPrefixFraction = 0.90;

  // --- 指标 8：像素差 ---
  /// |darknessA - darknessB| >= 8/255 计为差异像素；分母为 mask 内
  /// 两图着墨并集。
  static const double pixelDiffThreshold = 8 / 255;

  // --- 指标 10：分块结构 ---
  /// 分块与整笔的切线/包络顶点逐值比较容差（同运行时）。
  static const double vertexTolerance = 1e-9;

  // -------------------------------------------------------------------
  // T0 校准冻结阈值（由 v1 基线实测 + 纯 Path spike 原型共同标定，
  // natural_media_image_metrics_test.dart 固化失败示例）。
  // -------------------------------------------------------------------

  /// 指标 5：v2 铅笔边缘不规则度 RMS/局部宽度 不得低于此值。
  /// T0 实测（连续段边缘口径）：spike 原型 0.072、v1 0.126——v1 的
  /// 高值来自喷枪式散点链，"不规则度不足"未获指标支持（见 NOTES-v1
  /// P-03）；本门禁的语义是 v2 防退化下限（防"纯半透明钢笔"式光滑
  /// 边缘，光滑带实测 ≈0），不是 v1/v2 区分器。取 spike 值留 30% 余量。
  static const double edgeIrregularityMinRms = 0.05;

  /// 指标 6：残差自相关 lag 2～32 最大正峰不得超过此值。
  /// T0 实测：规则横纹合成样本 > 0.55、spike 原型 0.148、v1 0.278。
  static const double autocorrPeakMax = 0.40;

  /// 指标 8：本地湿墨/远端湿墨像素差门禁由 N12(1%)/N13(2%) 引用，
  /// 此处只冻结差异判定本身。

  /// 采样率稳定性：同一轨迹稀疏/正常/密集三档在恒压下，中心带平均
  /// darkness 相对偏差与中位有效宽度相对偏差上限（v1 实测 < 6%）。
  static const double samplingRateDarknessRelDevMax = 0.12;
  static const double samplingRateWidthRelDevMax = 0.15;
}

/// 指标 1/2 载体：渲染产物栅格与着墨判定。
class NaturalMediaRaster {
  NaturalMediaRaster._(this.width, this.height, this._rgba);

  final int width;
  final int height;
  final ByteData _rgba;

  static Future<NaturalMediaRaster> fromImage(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw StateError('toByteData(rawRgba) 返回 null');
    }
    return NaturalMediaRaster._(image.width, image.height, data);
  }

  bool _inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  /// 指标 2：darkness = 1 - Y/255（透明底像素按 alpha 合成到黑处理：
  /// alpha=0 时 darkness=1 会被误判为全墨，因此对透明像素返回合成到
  /// 白底等价值的 0；本指标族默认在白底上度量）。
  double darkness(int x, int y) {
    if (!_inBounds(x, y)) return 0;
    final o = (y * width + x) * 4;
    final a = _rgba.getUint8(o + 3);
    if (a == 0) return 0;
    final r = _rgba.getUint8(o);
    final g = _rgba.getUint8(o + 1);
    final b = _rgba.getUint8(o + 2);
    final y709 =
        NaturalMediaFrozen.lumaR * r +
        NaturalMediaFrozen.lumaG * g +
        NaturalMediaFrozen.lumaB * b;
    return 1.0 - y709 / 255.0;
  }

  /// 指标 2：darkness >= 16/255 计为着墨。
  bool isInk(int x, int y) =>
      darkness(x, y) >= NaturalMediaFrozen.inkDarknessThreshold;

  /// darkness 的最近像素取样（亚像素坐标四舍五入到像素中心）。
  double darknessAt(double x, double y) => darkness(x.round(), y.round());
}

/// 指标 1：渲染底图契约。
///
/// 白色不透明背景、固定黑色笔、opacity=100%、zoom=1、devicePixelRatio=1。
/// 透明底变体专测 alpha/接缝（背景不铺白，仅清屏）。所有自然介质
/// 像素指标必须经由本契约取栅格，禁止各自另设底图。
class NaturalMediaSheetRenderer {
  NaturalMediaSheetRenderer._();

  static const ui.Color fixedStrokeColor = ui.Color(0xFF000000);

  /// 契约的画布侧实现：白底（或透明底清屏）+ 逐元素渲染。
  /// renderScene 与结构计数（调用方用 SpyCanvas 包装 canvas 后转发的
  /// 是同一入口）共用本方法，保证指标栅格与 draw 统计来自同一份
  /// 绘制指令，禁止测试自建第二套底图。
  static void paintScene(
    ui.Canvas canvas,
    ui.Size size,
    List<FreedrawElement> elements, {
    bool opaqueWhiteBackground = true,
  }) {
    if (opaqueWhiteBackground) {
      canvas.drawRect(
        ui.Offset.zero & size,
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }
    for (final element in elements) {
      ElementRenderer.render(canvas, element, RoughCanvasAdapter());
    }
  }

  /// 按 T0 冻结底图契约渲染并光栅化。返回指标栅格。
  static Future<NaturalMediaRaster> renderScene({
    required List<FreedrawElement> elements,
    required ui.Size size,
    bool opaqueWhiteBackground = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    paintScene(
      canvas,
      size,
      elements,
      opaqueWhiteBackground: opaqueWhiteBackground,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    final raster = await NaturalMediaRaster.fromImage(image);
    image.dispose();
    return raster;
  }
}

/// 弧长几何：折线累计弧长与弧长比例处的位置/单位切线。
///
/// "前 90%"（指标 7）以本类的原始弧长为唯一定义：累计弧长终点
/// <= 0.9 × totalLength 的 owned edge 集合，不是图片像素排序。
class StrokeArcGeometry {
  StrokeArcGeometry(this.points) : _cum = _cumulative(points);

  final List<Point> points;
  final List<double> _cum;

  static List<double> _cumulative(List<Point> pts) {
    final cum = List<double>.filled(pts.length, 0);
    for (var i = 1; i < pts.length; i++) {
      cum[i] = cum[i - 1] + pts[i - 1].distanceTo(pts[i]);
    }
    return cum;
  }

  double get totalLength => _cum.isEmpty ? 0 : _cum.last;

  /// 弧长比例 [t] 处的位置。
  Point pointAtFraction(double t) {
    if (points.isEmpty) return Point.zero;
    final want = totalLength * t.clamp(0.0, 1.0);
    for (var i = 1; i < points.length; i++) {
      if (_cum[i] >= want || i == points.length - 1) {
        final seg = _cum[i] - _cum[i - 1];
        final u = seg <= 0 ? 0.0 : ((want - _cum[i - 1]) / seg).clamp(0.0, 1.0);
        final a = points[i - 1];
        final b = points[i];
        return Point(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u);
      }
    }
    return points.last;
  }

  /// 弧长比例 [t] 处的单位切线（±2% 弧长差分）。
  Point tangentAtFraction(double t) {
    final q = pointAtFraction((t + 0.02).clamp(0.0, 1.0));
    final r = pointAtFraction((t - 0.02).clamp(0.0, 1.0));
    final dx = q.x - r.x;
    final dy = q.y - r.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) return const Point(1, 0);
    return Point(dx / len, dy / len);
  }

  /// 弧长比例 [t] 处的单位法线（切线逆时针旋转 90°）。
  Point normalAtFraction(double t) {
    final tan = tangentAtFraction(t);
    return Point(-tan.y, tan.x);
  }

  /// 指标 7：像素中心是否落在"前 [prefixFraction] 弧长"内
  ///（距折线最近点的弧长参数 <= prefix）。O(points)/像素，仅测试用。
  bool pixelInArcPrefix(int x, int y, {double? prefixFraction}) {
    final prefix = prefixFraction ?? NaturalMediaFrozen.arcPrefixFraction;
    return arcFractionOfPixel(x, y) <= prefix;
  }

  /// 像素中心到折线最近点的弧长参数（0~1）。
  double arcFractionOfPixel(int x, int y) {
    if (points.length < 2 || totalLength <= 0) return 0;
    var bestDist = double.infinity;
    var bestArc = 0.0;
    final px = x + 0.5;
    final py = y + 0.5;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final ex = b.x - a.x;
      final ey = b.y - a.y;
      final len2 = ex * ex + ey * ey;
      final u = len2 <= 0
          ? 0.0
          : (((px - a.x) * ex + (py - a.y) * ey) / len2).clamp(0.0, 1.0);
      final cx = a.x + ex * u;
      final cy = a.y + ey * u;
      final d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
      if (d < bestDist) {
        bestDist = d;
        bestArc = _cum[i - 1] + (len2 <= 0 ? 0 : math.sqrt(len2) * u);
      }
    }
    return bestArc / totalLength;
  }
}

/// 指标 4：有效宽度（弧长 40%～60% 每 2% 法向扫描，取中位数）。
class WidthProfile {
  WidthProfile._();

  /// 单次法向扫描：沿 ±normal 以 1px 步进找最 outer 着墨像素，
  /// 宽度 = 两侧最远着墨像素距离之和。无墨返回 0。
  static double widthAtArcFraction(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry,
    double t, {
    required double strokeWidth,
  }) {
    final c = geometry.pointAtFraction(t);
    final n = geometry.normalAtFraction(t);
    final maxR = NaturalMediaFrozen.widthScanRadius(strokeWidth);
    double farthest(int dir) {
      var far = 0.0;
      for (var d = 0.0; d <= maxR; d += NaturalMediaFrozen.widthScanStep) {
        final x = (c.x + n.x * d * dir).round();
        final y = (c.y + n.y * d * dir).round();
        if (raster.isInk(x, y)) far = d;
      }
      return far;
    }

    return farthest(1) + farthest(-1);
  }

  /// 中心带（40%～60%，步长 2%）各扫描点的宽度序列。
  static List<double> centerBandWidths(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double strokeWidth,
  }) {
    final out = <double>[];
    for (
      var t = NaturalMediaFrozen.centerBandArcStart;
      t <= NaturalMediaFrozen.centerBandArcEnd + 1e-9;
      t += NaturalMediaFrozen.centerBandArcStep
    ) {
      out.add(
        widthAtArcFraction(
          raster,
          geometry,
          t.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
        ),
      );
    }
    return out;
  }

  /// 中位有效宽度（N3/N6 口径）。
  static double medianCenterWidth(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double strokeWidth,
  }) {
    final widths = centerBandWidths(raster, geometry, strokeWidth: strokeWidth)
      ..sort();
    if (widths.isEmpty) return 0;
    final mid = widths.length ~/ 2;
    return widths.length.isOdd
        ? widths[mid]
        : (widths[mid - 1] + widths[mid]) / 2;
  }
}

/// 指标 3：共同中心带浓度。
class CenterBandDarkness {
  CenterBandDarkness._();

  /// 共同半宽 = 轻/重两笔中位有效宽度较小值的 45%。
  static double commonHalfWidth(double widthA, double widthB) =>
      math.min(widthA, widthB) * NaturalMediaFrozen.commonBandHalfWidthRatio;

  /// 中心带平均 darkness：弧长 40%～60% 每 2% 取样，法向 ±commonHalfWidth
  /// 每 0.5px 取样 darkness，全部样本取算术平均（弧长/法向双均匀取样，
  /// 等价区域平均）。N2 只用本口径，禁止用总 coverage。
  static double commonBandMeanDarkness(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double commonHalfWidth,
  }) {
    var sum = 0.0;
    var count = 0;
    for (
      var t = NaturalMediaFrozen.centerBandArcStart;
      t <= NaturalMediaFrozen.centerBandArcEnd + 1e-9;
      t += NaturalMediaFrozen.centerBandArcStep
    ) {
      final c = geometry.pointAtFraction(t.clamp(0.0, 1.0));
      final n = geometry.normalAtFraction(t.clamp(0.0, 1.0));
      for (
        var o = -commonHalfWidth;
        o <= commonHalfWidth + 1e-9;
        o += NaturalMediaFrozen.centerBandNormalStep
      ) {
        sum += raster.darknessAt(c.x + n.x * o, c.y + n.y * o);
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }
}

/// 指标 5/6：边缘不规则度与固定周期峰。
///
/// 边缘取法（T0 校准冻结）：从中心沿法向找"连续着墨段"的最远点，
/// 允许 1px 抗锯齿孔，遇到 ≥2px 空隙即止——孤立喷洒颗粒不属于
/// 笔画本体边缘。这样指标度量的是本体边缘的破碎/粗糙程度：光滑
/// 外观（v1 perfect_freehand 轮廓）RMS 接近 0，破碎石墨边缘 RMS 高。
/// 宽度指标（指标 4/N3/N6）仍取最外着墨像素，两者口径不同是有意
/// 的：命中/擦除关心最外缘，纹理关心本体边缘。
class EdgeIrregularity {
  EdgeIrregularity._();

  static double _contiguousEdge(
    NaturalMediaRaster raster,
    Point c,
    Point n,
    int dir,
    double maxR,
  ) {
    var far = 0.0;
    var gap = 0;
    for (var d = 0.0; d <= maxR; d += NaturalMediaFrozen.widthScanStep) {
      if (raster.isInk(
        (c.x + n.x * d * dir).round(),
        (c.y + n.y * d * dir).round(),
      )) {
        far = d;
        gap = 0;
      } else {
        gap++;
        if (gap >= 2) break; // 连续段终止：孤立颗粒不算本体边缘
      }
    }
    return far;
  }

  /// 边缘序列采样：弧长 10%～90%，固定 2px 弧长步长，左右两侧
  /// 各记录"中心 → 本体边缘（连续着墨段最远点）"的单侧距离。
  static EdgeSeries sampleEdges(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double strokeWidth,
  }) {
    final step =
        NaturalMediaFrozen.edgeArcStepPx /
        (geometry.totalLength <= 0 ? 1 : geometry.totalLength);
    final left = <double>[];
    final right = <double>[];
    final maxR = NaturalMediaFrozen.widthScanRadius(strokeWidth);
    for (
      var t = NaturalMediaFrozen.edgeArcStart;
      t <= NaturalMediaFrozen.edgeArcEnd + 1e-9;
      t += step
    ) {
      final tc = t.clamp(0.0, 1.0);
      final c = geometry.pointAtFraction(tc);
      final n = geometry.normalAtFraction(tc);
      left.add(_contiguousEdge(raster, c, n, 1, maxR));
      right.add(_contiguousEdge(raster, c, n, -1, maxR));
    }
    return EdgeSeries(left, right);
  }

  /// 9 样本中心移动平均（窗口不完整的端部样本不产出残差）。
  static List<double> movingAverageResiduals(List<double> series) {
    final w = NaturalMediaFrozen.edgeMovingAverageWindow;
    final half = w ~/ 2;
    final out = <double>[];
    for (var i = half; i < series.length - half; i++) {
      var sum = 0.0;
      for (var j = -half; j <= half; j++) {
        sum += series[i + j];
      }
      out.add(series[i] - sum / w);
    }
    return out;
  }

  /// 残差 RMS / 局部宽度（局部宽度 = 该笔中位有效宽度）。左右两侧
  /// 残差合并计算。返回 0 表示边缘完全平滑（v1 钢笔式边缘的特征）。
  static double residualRmsOverWidth(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double strokeWidth,
  }) {
    final edges = sampleEdges(raster, geometry, strokeWidth: strokeWidth);
    final residuals = [
      ...movingAverageResiduals(edges.left),
      ...movingAverageResiduals(edges.right),
    ];
    if (residuals.isEmpty) return 0;
    var sumSq = 0.0;
    for (final r in residuals) {
      sumSq += r * r;
    }
    final localWidth = WidthProfile.medianCenterWidth(
      raster,
      geometry,
      strokeWidth: strokeWidth,
    );
    if (localWidth <= 0) return 0;
    return math.sqrt(sumSq / residuals.length) / localWidth;
  }
}

/// 边缘序列（左右单侧距离，弧长 2px 步长）。
class EdgeSeries {
  const EdgeSeries(this.left, this.right);

  final List<double> left;
  final List<double> right;
}

/// 指标 6：残差归一化自相关，lag 2～32 内最大正峰。
class Periodicity {
  Periodicity._();

  /// c(k) = Σ r[i]·r[i+k] / Σ r[i]²（有效重叠窗口）。r 全零（完全
  /// 平滑）返回 0。返回 lag 2～32 内的最大正值。
  static double maxAutocorrelationPeak(List<double> residuals) {
    if (residuals.length <= NaturalMediaFrozen.autocorrMinLag) return 0;
    var denom = 0.0;
    for (final r in residuals) {
      denom += r * r;
    }
    if (denom <= 0) return 0;
    var peak = 0.0;
    for (
      var k = NaturalMediaFrozen.autocorrMinLag;
      k <= NaturalMediaFrozen.autocorrMaxLag && k < residuals.length;
      k++
    ) {
      var sum = 0.0;
      for (var i = 0; i + k < residuals.length; i++) {
        sum += residuals[i] * residuals[i + k];
      }
      if (sum > 0) {
        final c = sum / denom;
        if (c > peak) peak = c;
      }
    }
    return peak;
  }

  /// 便捷入口：对栅格先做边缘采样再算峰值。
  static double maxEdgeAutocorrelationPeak(
    NaturalMediaRaster raster,
    StrokeArcGeometry geometry, {
    required double strokeWidth,
  }) {
    final edges = EdgeIrregularity.sampleEdges(
      raster,
      geometry,
      strokeWidth: strokeWidth,
    );
    return math.max(
      maxAutocorrelationPeak(
        EdgeIrregularity.movingAverageResiduals(edges.left),
      ),
      maxAutocorrelationPeak(
        EdgeIrregularity.movingAverageResiduals(edges.right),
      ),
    );
  }
}

/// 指标 7：弧长前缀 mask 的像素集版本（供指标 8 限定区域）。
class ArcPrefixMask {
  ArcPrefixMask(this.geometry, this.prefixFraction);

  final StrokeArcGeometry geometry;
  final double prefixFraction;

  factory ArcPrefixMask.default90(StrokeArcGeometry geometry) =>
      ArcPrefixMask(geometry, NaturalMediaFrozen.arcPrefixFraction);

  bool containsPixel(int x, int y) =>
      geometry.pixelInArcPrefix(x, y, prefixFraction: prefixFraction);
}

/// 指标 8：像素差。
class PixelDiff {
  PixelDiff._();

  /// |darknessA-darknessB| >= 8/255 的像素数 / mask 内两图着墨并集。
  /// mask 为 null 时覆盖全图。两图尺寸不一致时抛错。
  static double differingInkRatio(
    NaturalMediaRaster a,
    NaturalMediaRaster b, {
    bool Function(int x, int y)? mask,
  }) {
    if (a.width != b.width || a.height != b.height) {
      throw ArgumentError('像素差要求同尺寸栅格');
    }
    var differing = 0;
    var union = 0;
    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        if (mask != null && !mask(x, y)) continue;
        final ia = a.isInk(x, y);
        final ib = b.isInk(x, y);
        if (ia || ib) union++;
        if ((a.darkness(x, y) - b.darkness(x, y)).abs() >=
            NaturalMediaFrozen.pixelDiffThreshold) {
          differing++;
        }
      }
    }
    return union == 0 ? 0 : differing / union;
  }
}

/// 指标 9：排序一致性（Canvas vs Chromium SVG 的轻重趋势）。
enum MetricOrdering { increasing, decreasing, equal }

MetricOrdering orderingOf(double light, double heavy) {
  final delta = heavy - light;
  if (delta > 1e-12) return MetricOrdering.increasing;
  if (delta < -1e-12) return MetricOrdering.decreasing;
  return MetricOrdering.equal;
}

/// 两组轻/重值排序方向一致（"看起来同向"不算数）。相等序只与相等序
/// 匹配；一端相等另一端不等视为不一致。
bool sameOrdering(double aLight, double aHeavy, double bLight, double bHeavy) {
  final oa = orderingOf(aLight, aHeavy);
  final ob = orderingOf(bLight, bHeavy);
  if (oa == MetricOrdering.equal || ob == MetricOrdering.equal) {
    return oa == ob;
  }
  return oa == ob;
}

/// 指标 10：分块结构比较的 primitive 引用。
///
/// key 三元组 (edgeStartIndex, sampleOrdinal, channel) 唯一确定一个
/// primitive；paint bucket / 几何参数由 T2 的 plan 携带，此处冻结比较
/// 语义：key multiset 相等 AND channel/paint bucket 逐项相等 AND
/// 边界切线/包络顶点逐值相等（容差 1e-9）。
class NaturalMediaPrimitiveRef {
  const NaturalMediaPrimitiveRef({
    required this.edgeStartIndex,
    required this.sampleOrdinal,
    required this.channel,
    this.paintBucket,
  });

  final int edgeStartIndex;
  final int sampleOrdinal;
  final int channel;
  final String? paintBucket;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaturalMediaPrimitiveRef &&
          edgeStartIndex == other.edgeStartIndex &&
          sampleOrdinal == other.sampleOrdinal &&
          channel == other.channel;

  @override
  int get hashCode => Object.hash(edgeStartIndex, sampleOrdinal, channel);

  @override
  String toString() =>
      'Primitive(edge:$edgeStartIndex,ord:$sampleOrdinal,'
      'ch:$channel${paintBucket == null ? '' : ',bucket:$paintBucket'})';
}

/// multiset 差异描述：null = 完全一致；否则返回人读的差异摘要。
/// 只按 key 三元组 (edge, ordinal, channel) 计数——key 相等不能代替
/// bucket/几何相等，后者由 [bucketMappingEqual]/[verticesEqual] 分别判定。
String? multisetDiff(
  Iterable<NaturalMediaPrimitiveRef> a,
  Iterable<NaturalMediaPrimitiveRef> b,
) {
  final countA = <NaturalMediaPrimitiveRef, int>{};
  final countB = <NaturalMediaPrimitiveRef, int>{};
  for (final ref in a) {
    countA[ref] = (countA[ref] ?? 0) + 1;
  }
  for (final ref in b) {
    countB[ref] = (countB[ref] ?? 0) + 1;
  }
  final problems = <String>[];
  for (final entry in countA.entries) {
    final other = countB[entry.key] ?? 0;
    if (other != entry.value) {
      problems.add('${entry.key} 数量不一致: A ${entry.value} vs B $other');
    }
  }
  for (final key in countB.keys) {
    if (!countA.containsKey(key)) {
      problems.add('仅 B 有 ${countB[key]}× $key');
    }
  }
  if (problems.isEmpty) return null;
  return problems.take(8).join('; ');
}

/// paint bucket 映射一致性：同 key 的 bucket 逐对相等。
/// 任一侧 bucket 为 null（未提供）时不判不等，由调用方保证输入完整。
bool bucketMappingEqual(
  Iterable<NaturalMediaPrimitiveRef> a,
  Iterable<NaturalMediaPrimitiveRef> b,
) {
  final bucketsA = <NaturalMediaPrimitiveRef, String?>{};
  final bucketsB = <NaturalMediaPrimitiveRef, String?>{};
  for (final ref in a) {
    bucketsA[ref] = ref.paintBucket;
  }
  for (final ref in b) {
    bucketsB[ref] = ref.paintBucket;
  }
  if (bucketsA.length != bucketsB.length) return false;
  for (final entry in bucketsA.entries) {
    if (!bucketsB.containsKey(entry.key)) return false;
    if (entry.value != bucketsB[entry.key]) return false;
  }
  return true;
}

/// 顶点序列逐值相等（容差 1e-9）；长度不等直接 false。
bool verticesEqual(
  List<ui.Offset> a,
  List<ui.Offset> b, {
  double tolerance = NaturalMediaFrozen.vertexTolerance,
}) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).distance > tolerance) return false;
  }
  return true;
}
