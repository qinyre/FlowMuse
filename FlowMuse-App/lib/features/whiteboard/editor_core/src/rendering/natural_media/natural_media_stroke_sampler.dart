import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../core/elements/elements.dart';
import '../../core/math/math.dart';
import 'deterministic_stroke_seed.dart';
import 'natural_media_stroke_plan.dart';

// ---------------------------------------------------------------------------
// 确定性共享采样器（计划 §3.3/§3.4/§3.6/§3.7 的几何真源）。
//
// 不变量：
//  1. 输出只由（strokeId, points, pressures, strokeWidth, brushType,
//     isComplete, owned 边范围, tuning）决定——与分块级别、调用次数、
//     运行时（VM/dart2js）无关；
//  2. 每 edge 的 primitive 只依赖该边与其 stencil/context 邻边，
//     禁止依赖整笔长度等全局量（分块一致性）；
//  3. 所有随机量经 §3.3 种子（mul32 栈），无 Random/hashCode；
//  4. 采样/颗粒/毫丝有硬上限与稳定降采样（保首尾与压力极值段）；
//  5. 单遍 O(n + cappedParticles)，禁止每采样点从头扫折线。
//
// 曲线常数（§3.5 候选）暂以静态曲线提供，T3 收进 BrushRenderProfile
// 单一真源后由 profile 注入 tuning。
// ---------------------------------------------------------------------------

/// 采样/几何调参（T0 spike 校准值；T3/T4/T5 经 profile 提供）。
class NaturalMediaTuning {
  const NaturalMediaTuning({
    this.sampleStepPx = 2.0,
    this.particleCap = 4096,
    this.sampleCap = 100000,
    this.stencilWeights = const [0.5, 0.3, 0.2],
    this.miterLimit = 1.5,
    this.pencilScatterRatio = BrushRenderProfile.pencilV2ScatterRatio,
    this.pencilGrainBuckets = defaultPencilGrainBuckets,
    this.brushStrandMinHalfWidth = 2.6,
    this.brushSharpTurnRad = 75 * math.pi / 180.0,
  });

  final double sampleStepPx;
  final int particleCap;
  final int sampleCap;
  final List<double> stencilWeights;
  final double miterLimit;
  final double pencilScatterRatio;
  final List<PencilGrainBucket> pencilGrainBuckets;
  final double brushStrandMinHalfWidth;
  final double brushSharpTurnRad;

  static const defaultPencilGrainBuckets = [
    PencilGrainBucket(
      channel: 1,
      minPressure: 0.00,
      spacingA: 3.4,
      spacingB: 1.6,
      minSpacing: 1.6,
    ),
    PencilGrainBucket(
      channel: 2,
      minPressure: 0.30,
      spacingA: 6.0,
      spacingB: 5.0,
      minSpacing: 2.2,
    ),
    PencilGrainBucket(
      channel: 3,
      minPressure: 0.65,
      spacingA: 7.5,
      spacingB: 6.0,
      minSpacing: 2.6,
    ),
  ];
}

/// 铅笔密度桶（spike 校准；T4 由 profile 冻结）。
class PencilGrainBucket {
  const PencilGrainBucket({
    required this.channel,
    required this.minPressure,
    required this.spacingA,
    required this.spacingB,
    required this.minSpacing,
  });

  final int channel;
  final double minPressure;
  final double spacingA;
  final double spacingB;
  final double minSpacing;

  double spacingAt(double pressure) =>
      math.max(minSpacing, spacingA - spacingB * pressure);
}

/// §3.5 响应曲线入口：定义单点维护在 BrushRenderProfile（T3 收编），
/// 本处仅按笔形选曲线并缓存 profile 实例（热路径避免逐点 forType）。
abstract final class NaturalMediaResponseCurves {
  static final BrushRenderProfile _pencil = BrushRenderProfile.forType(
    BrushType.pencil,
  );
  static final BrushRenderProfile _brushPen = BrushRenderProfile.forType(
    BrushType.brushPen,
  );

  static double pencilLocalWidth(double base, double p) =>
      _pencil.pencilNaturalMediaLocalWidth(base, p);

  static double pencilDensity(double p) => _pencil.pencilNaturalMediaDensity(p);

  static double brushContactHalfWidth(double base, double p) =>
      _brushPen.brushNaturalMediaContactHalfWidth(base, p);
}

class NaturalMediaStrokeSampler {
  const NaturalMediaStrokeSampler._();

  /// 采样主入口。[points]/[pressures] 为同一坐标系下的原始序列
  ///（绝对或相对一致即可）；[ownedEdgeStart]/[ownedEdgeEndExclusive]
  /// 以原始边索引（第 i 条边连接 points[i-1]→points[i]，i 从 1 起）
  /// 指定本分段拥有的边范围，范围外的点仅作 stencil context。
  /// [edgeIndexOffset]：远端分段渲染把边索引平移到全局笔迹索引
  ///（offset = 段起点 − leading 点数），使 primitive key 与整笔一致。
  static NaturalMediaStrokePlan sample({
    required String strokeId,
    required List<Point> points,
    required List<double> pressures,
    required double strokeWidth,
    required BrushType brushType,
    bool isComplete = true,
    int? ownedEdgeStart,
    int? ownedEdgeEndExclusive,
    int edgeIndexOffset = 0,
    NaturalMediaTuning tuning = const NaturalMediaTuning(),
  }) {
    final seed = strokeSeedOf(strokeId);
    final n = math.min(points.length, pressures.length);

    // 1) 校验与拷贝：丢非有限点（计数），非有限压力按 0.5 兜底并计数。
    final valid = <int>[];
    var dropped = 0;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      final q = i < pressures.length ? pressures[i] : double.nan;
      if (p.x.isFinite && p.y.isFinite) {
        if (!q.isFinite) dropped++;
        valid.add(i);
      } else {
        dropped++;
      }
    }

    double pressureAt(int idx) {
      final raw = idx < pressures.length ? pressures[idx] : 0.5;
      if (!raw.isFinite) return 0.5;
      return raw.clamp(0.0, 1.0);
    }

    final pts = [for (final i in valid) Point(points[i].x, points[i].y)];
    final prs = [for (final i in valid) pressureAt(i)];

    // 2) 有效边（跳过零长；index 用原始 i 保持跨分块 key 一致）。
    final edges = <NaturalMediaEdge>[];
    var arc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final len = a.distanceTo(b);
      if (len < 1e-9) continue;
      edges.add(
        NaturalMediaEdge(
          index: valid[i] + edgeIndexOffset,
          from: a,
          to: b,
          length: len,
          arcStart: arc,
          pressure: ((prs[i - 1] + prs[i]) / 2).clamp(0.0, 1.0),
        ),
      );
      arc += len;
    }

    // 3) 三 edge 固定窗口滤波切线（缺槽复用最早有效边切线）。
    final filtered = List<Point>.generate(
      edges.length,
      (_) => const Point(1, 0),
      growable: false,
    );
    for (var k = 0; k < edges.length; k++) {
      var sx = 0.0;
      var sy = 0.0;
      var applied = 0;
      for (var j = 0; j < tuning.stencilWeights.length && k - j >= 0; j++) {
        sx += tuning.stencilWeights[j] * _tx(edges[k - j]);
        sy += tuning.stencilWeights[j] * _ty(edges[k - j]);
        applied++;
      }
      for (var j = applied; j < tuning.stencilWeights.length; j++) {
        sx += tuning.stencilWeights[j] * _tx(edges.first);
        sy += tuning.stencilWeights[j] * _ty(edges.first);
      }
      final len = math.sqrt(sx * sx + sy * sy);
      filtered[k] = len < 1e-9
          ? Point(_tx(edges[k]), _ty(edges[k]))
          : Point(sx / len, sy / len);
    }

    // 4) owned 范围（原始边索引，安全钳制，不越界）。
    final ownStart = ownedEdgeStart ?? (edges.isEmpty ? 0 : edges.first.index);
    final ownEndExclusive =
        ownedEdgeEndExclusive ?? (edges.isEmpty ? 0 : edges.last.index + 1);
    final owned = <int>[
      for (var k = 0; k < edges.length; k++)
        if (edges[k].index >= ownStart && edges[k].index < ownEndExclusive) k,
    ];

    // 5) 边内等距采样。终点槽（s == edge.length）只属于拥有整笔末边
    // 的分段（尾部块/整笔）；内部分块不含终点，交界由较后 edge 的
    // ordinal 0 拥有——否则分块并集会多出整笔没有的边界 key
    //（计划 §3.4 所有权规则）。
    final ownsStrokeTail =
        edges.isNotEmpty && ownEndExclusive > edges.last.index;
    final samples = <NaturalMediaSample>[];
    for (var oi = 0; oi < owned.length; oi++) {
      final k = owned[oi];
      final e = edges[k];
      final isLastOwned = oi == owned.length - 1;
      final includeEndPoint = isLastOwned && ownsStrokeTail;
      var curvature = 0.0;
      if (k > 0) {
        final turn = _signedAngle(filtered[k - 1], filtered[k]);
        final dArc = e.arcStart - edges[k - 1].arcStart;
        if (dArc > 1e-9) curvature = turn / dArc;
      }
      var s = 0.0;
      var ordinal = 0;
      while (s < e.length || (includeEndPoint && s <= e.length + 1e-9)) {
        final u = (s / e.length).clamp(0.0, 1.0);
        samples.add(
          NaturalMediaSample(
            edgeIndex: e.index,
            ordinal: ordinal,
            s: s,
            position: Point(
              e.from.x + (e.to.x - e.from.x) * u,
              e.from.y + (e.to.y - e.from.y) * u,
            ),
            tangent: e.tangent,
            filteredTangent: filtered[k],
            pressure: (e.pressure).clamp(0.0, 1.0), // 边内匀压：边平均已含端点信息
            curvature: curvature,
          ),
        );
        ordinal++;
        s += tuning.sampleStepPx;
      }
    }
    var hitSampleCap = false;
    var keptSamples = samples;
    if (samples.length > tuning.sampleCap) {
      hitSampleCap = true;
      final stride = samples.length / tuning.sampleCap;
      keptSamples = [
        for (var i = 0; i < tuning.sampleCap; i++)
          samples[(i * stride).floor()],
      ]..[tuning.sampleCap - 1] = samples.last;
    }

    // 6) primitive 发射（按笔形；只依赖 owned 边与其 context）。
    final primitives = <NaturalMediaPrimitive>[];
    var bounds = ui.Rect.zero;
    var hitParticleCap = false;

    void absorb(ui.Rect r) {
      bounds = bounds.isEmpty ? r : bounds.expandToInclude(r);
    }

    if (edges.isEmpty || pts.length < 2) {
      // 单点退化：dot/teardrop（不虚构方向）。
      if (pts.isNotEmpty) {
        final hw =
            NaturalMediaResponseCurves.brushContactHalfWidth(
              strokeWidth,
              prs.first,
            ) *
            1.3;
        final c = pts.first;
        final r = ui.Rect.fromCircle(center: ui.Offset(c.x, c.y), radius: hw);
        absorb(r);
        primitives.add(
          NaturalMediaPrimitive(
            kind: NaturalMediaPrimitiveKind.brushTeardrop,
            edgeIndex: valid.isEmpty ? 0 : valid.first,
            ordinal: 0,
            channel: NaturalMediaChannel.brushBody,
            paintBucket: 'brushTeardrop',
            bounds: r,
            center: c,
            halfLength: hw,
          ),
        );
      }
    } else if (brushType == BrushType.brushPen) {
      // 短线退化（§3.7：短划专门 teardrop，不做单边包络+帽子）。
      // 尺寸按整笔平均压力（短点无起收可言），1.3× 放大形成笔肚感。
      // 仅整笔调用：远端分段的"leading+少量点"列表可能很短，中途
      // 冻结成 teardrop 会在后续点到达时跳变；分段恒走包络路径。
      final totalLen = edges.fold<double>(0.0, (a, e) => a + e.length);
      if (totalLen < 2 * strokeWidth && ownedEdgeStart == null) {
        final pAvg = (edges.first.pressure + edges.last.pressure) / 2;
        final hw =
            NaturalMediaResponseCurves.brushContactHalfWidth(
              strokeWidth,
              pAvg,
            ) *
            1.3;
        final c = Point(
          (edges.first.from.x + edges.last.to.x) / 2,
          (edges.first.from.y + edges.last.to.y) / 2,
        );
        final r = ui.Rect.fromCircle(center: ui.Offset(c.x, c.y), radius: hw);
        absorb(r);
        primitives.add(
          NaturalMediaPrimitive(
            kind: NaturalMediaPrimitiveKind.brushTeardrop,
            edgeIndex: edges.first.index,
            ordinal: 0,
            channel: NaturalMediaChannel.brushBody,
            paintBucket: 'brushTeardrop',
            bounds: r,
            center: c,
            halfLength: hw,
            tangent: edges.last.tangent,
          ),
        );
      } else {
        _emitBrush(
          primitives,
          absorb,
          seed,
          edges,
          filtered,
          owned,
          ownEndExclusive,
          strokeWidth,
          tuning,
        );
      }
    } else if (brushType == BrushType.pencil) {
      hitParticleCap = _emitPencil(
        primitives,
        absorb,
        seed,
        edges,
        filtered,
        owned,
        strokeWidth,
        tuning,
      );
    }

    var particleCount = 0;
    var plannedPaths = 0;
    final activeChannels = <int>{};
    for (final p in primitives) {
      if (p.kind == NaturalMediaPrimitiveKind.pencilGrain ||
          p.kind == NaturalMediaPrimitiveKind.brushStrand) {
        particleCount++;
      }
      activeChannels.add(p.channel);
    }
    plannedPaths = brushType == BrushType.brushPen
        ? (activeChannels.isEmpty
              ? 0
              : 1 +
                    (activeChannels.contains(NaturalMediaChannel.brushStrand)
                        ? 1
                        : 0))
        : math.min(1 + activeChannels.length, 4);

    return NaturalMediaStrokePlan(
      strokeSeed: seed,
      edges: List.unmodifiable(edges),
      samples: List.unmodifiable(keptSamples),
      primitives: List.unmodifiable(primitives),
      bounds: bounds,
      stats: NaturalMediaPlanStats(
        inputPointCount: points.length,
        validPointCount: pts.length,
        edgeCount: edges.length,
        sampleCount: keptSamples.length,
        primitiveCount: primitives.length,
        particleCount: particleCount,
        plannedPathCount: plannedPaths,
        hitParticleCap: hitParticleCap,
        hitSampleCap: hitSampleCap,
        droppedNonFinite: dropped,
      ),
    );
    // isComplete 不参与采样几何：收笔形状由渲染层在最终 owned 边上
    // 依尾部压力决定（§3.7），整笔完成态不改变已确认 primitive。
  }

  static double _tx(NaturalMediaEdge e) => e.tangent.x;
  static double _ty(NaturalMediaEdge e) => e.tangent.y;

  static double _signedAngle(Point a, Point b) {
    final dot = a.x * b.x + a.y * b.y;
    final det = a.x * b.y - a.y * b.x;
    return math.atan2(det, dot);
  }

  /// 铅笔：基底带（channel 0，边局部）+ 三个密度桶颗粒。
  /// 返回是否命中粒子上限。
  static bool _emitPencil(
    List<NaturalMediaPrimitive> out,
    void Function(ui.Rect) absorb,
    int seed,
    List<NaturalMediaEdge> edges,
    List<Point> filtered,
    List<int> owned,
    double strokeWidth,
    NaturalMediaTuning tuning,
  ) {
    // 基底带：每条 owned 边一段（key = (edge, 0, base)）。
    for (final k in owned) {
      final e = edges[k];
      final w = NaturalMediaResponseCurves.pencilLocalWidth(
        strokeWidth,
        e.pressure,
      );
      final half = w / 2 * 1.15; // 基底抖动上界（spike：wob 0.85~1.15）
      final r = ui.Rect.fromLTRB(
        math.min(e.from.x, e.to.x) - half,
        math.min(e.from.y, e.to.y) - half,
        math.max(e.from.x, e.to.x) + half,
        math.max(e.from.y, e.to.y) + half,
      );
      absorb(r);
      out.add(
        NaturalMediaPrimitive(
          kind: NaturalMediaPrimitiveKind.pencilBase,
          edgeIndex: e.index,
          ordinal: 0,
          channel: NaturalMediaChannel.base,
          paintBucket: 'pencilBase',
          bounds: r,
        ),
      );
    }

    // 颗粒：先收集再统一限流（稳定步长 + 保首尾与压力极值段）。
    final grains = <NaturalMediaPrimitive>[];
    final grainPressures = <double>[];
    for (final k in owned) {
      final e = edges[k];
      final t = e.tangent;
      final nx = -t.y;
      final ny = t.x;
      final w = NaturalMediaResponseCurves.pencilLocalWidth(
        strokeWidth,
        e.pressure,
      );
      for (final bucket in tuning.pencilGrainBuckets) {
        if (e.pressure < bucket.minPressure) continue;
        final spacing = bucket.spacingAt(e.pressure);
        var ordinal = 0;
        for (var s = 0.0; s < e.length; s += spacing) {
          final gseed = mix32(seed, e.index, ordinal, bucket.channel);
          final alongJitter = (rand01(gseed, 0x11) - 0.5) * spacing * 0.6;
          final sJit = (s + alongJitter).clamp(0.0, e.length);
          final normalOffset =
              (rand01(gseed, 0x22) * 2 - 1) * w * tuning.pencilScatterRatio;
          final cx = e.from.x + t.x * sJit + nx * normalOffset;
          final cy = e.from.y + t.y * sJit + ny * normalOffset;
          final halfLen = math.max(
            0.55,
            w *
                (BrushRenderProfile.pencilV2GrainHalfLenBase +
                    BrushRenderProfile.pencilV2GrainHalfLenSpan *
                        rand01(gseed, 0x33)),
          );
          final halfThick = math.max(
            0.45,
            BrushRenderProfile.pencilV2GrainHalfThickBase * w +
                BrushRenderProfile.pencilV2GrainHalfThickAbs *
                    rand01(gseed, 0x44),
          );
          final r = ui.Rect.fromLTRB(
            cx - halfLen - halfThick,
            cy - halfLen - halfThick,
            cx + halfLen + halfThick,
            cy + halfLen + halfThick,
          );
          grains.add(
            NaturalMediaPrimitive(
              kind: NaturalMediaPrimitiveKind.pencilGrain,
              edgeIndex: e.index,
              ordinal: ordinal,
              channel: bucket.channel,
              paintBucket: 'pencil${bucket.channel}',
              bounds: r,
              center: Point(cx, cy),
              halfLength: halfLen,
              halfThickness: halfThick,
              tangent: t,
            ),
          );
          grainPressures.add(e.pressure);
          ordinal++;
        }
      }
    }

    var capped = grains;
    var hitCap = false;
    if (grains.length > tuning.particleCap) {
      hitCap = true;
      // 优先保留：首、尾、压力局部极值段（窗口 3，防降采样抹掉浓淡
      // 差异——N2 在 16k 上限触发时仍必须成立）；余量按稳定步长补齐；
      // 总量严格 ≤ particleCap。
      final keep = <int>{0, grains.length - 1};
      for (var i = 1; i < grains.length - 1; i++) {
        final p = grainPressures[i];
        if ((p > grainPressures[i - 1] && p > grainPressures[i + 1]) ||
            (p < grainPressures[i - 1] && p < grainPressures[i + 1])) {
          keep.add(i);
        }
      }
      final sortedKeep = (keep.toList()..sort());
      if (sortedKeep.length >= tuning.particleCap) {
        // 极值过多（噪声压力）时对保留集本身稳定降采样。
        final stride = sortedKeep.length / tuning.particleCap;
        sortedKeep.clear();
        for (var i = 0; i < tuning.particleCap; i++) {
          sortedKeep.add(keep.elementAt((i * stride).floor()));
        }
        sortedKeep.sort();
      } else {
        final budget = tuning.particleCap - sortedKeep.length;
        final stride = grains.length / budget;
        for (var i = 0; i < budget; i++) {
          sortedKeep.add((i * stride).floor());
        }
        sortedKeep.sort();
      }
      final finalKeep = sortedKeep.toSet().toList()..sort();
      capped = [for (final i in finalKeep) grains[i]];
    }
    for (final g in capped) {
      absorb(g.bounds);
      out.add(g);
    }
    return hitCap;
  }

  /// 毛笔：包络顶点（每采样槽一个，channel 4）+ join（归较后边）+
  /// 毫丝（channel 5，激活只依赖边局部量）。
  static void _emitBrush(
    List<NaturalMediaPrimitive> out,
    void Function(ui.Rect) absorb,
    int seed,
    List<NaturalMediaEdge> edges,
    List<Point> filtered,
    List<int> owned,
    int ownedEndExclusive,
    double strokeWidth,
    NaturalMediaTuning tuning,
  ) {
    // 包络顶点：直接复用 owned 边的等距采样规则（与 samples 同 grid，
    // 终点槽只归整笔末边的拥有者）。
    final ownsStrokeTail =
        edges.isNotEmpty && ownedEndExclusive > edges.last.index;
    for (var oi = 0; oi < owned.length; oi++) {
      final k = owned[oi];
      final e = edges[k];
      final includeEndPoint = oi == owned.length - 1 && ownsStrokeTail;
      final hw = NaturalMediaResponseCurves.brushContactHalfWidth(
        strokeWidth,
        e.pressure,
      );
      final f = filtered[k];
      var s = 0.0;
      var ordinal = 0;
      while (s < e.length || (includeEndPoint && s <= e.length + 1e-9)) {
        final u = (s / e.length).clamp(0.0, 1.0);
        final cx = e.from.x + (e.to.x - e.from.x) * u;
        final cy = e.from.y + (e.to.y - e.from.y) * u;
        final r = ui.Rect.fromCenter(
          center: ui.Offset(cx, cy),
          width: 2 * hw,
          height: 2 * hw,
        );
        absorb(r);
        out.add(
          NaturalMediaPrimitive(
            kind: NaturalMediaPrimitiveKind.brushEnvelopeVertex,
            edgeIndex: e.index,
            ordinal: ordinal,
            channel: NaturalMediaChannel.brushBody,
            paintBucket: 'brushBody',
            bounds: r,
            center: Point(cx, cy),
            halfThickness: hw,
            tangent: f,
          ),
        );
        ordinal++;
        s += tuning.sampleStepPx;
      }

      // 顶点 join（§3.4 较后 edge 拥有）：
      // 1) 块首边与前一非 owned 边的入口 join——归本边（否则前块不
      //    发（无下一 owned 边）、后块不发（join 不在其内部邻接对里），
      //    并集会缺 key）；
      // 2) 内部相邻 owned 边对。
      if (oi == 0 && k > 0 && !owned.contains(k - 1)) {
        // 入界 join 与内部 join 同口径：hw 取 from 边（k-1）的接触
        // 半宽，保证分块/整笔/合并三种路径的 join 逐值一致。
        _emitBrushJoin(
          out,
          absorb,
          edges[k - 1],
          e,
          filtered[k - 1],
          f,
          NaturalMediaResponseCurves.brushContactHalfWidth(
            strokeWidth,
            edges[k - 1].pressure,
          ),
          tuning,
        );
      }
      if (oi + 1 < owned.length) {
        final kn = owned[oi + 1];
        _emitBrushJoin(out, absorb, e, edges[kn], f, filtered[kn], hw, tuning);
      }

      // 毫丝：hw 足够且（隔边采样或本边压力下行——出锋毫丝）时发射
      // 2 根；激活条件只依赖本边与前一 context 边，分块一致。
      final prevPressure = k > 0 ? edges[k - 1].pressure : e.pressure;
      final falling = e.pressure < prevPressure - 0.05;
      if (hw >= tuning.brushStrandMinHalfWidth &&
          (falling || e.index % 3 == 0)) {
        for (var ch = 0; ch < 2; ch++) {
          final gseed = mix32(
            seed,
            e.index,
            0,
            NaturalMediaChannel.brushStrand,
          );
          final r1 = rand01(gseed, 0x11 + ch);
          final r2 = rand01(gseed, 0x22 + ch);
          final offsetMag = hw * (0.35 + 0.35 * r1) * (ch == 0 ? 1 : -1);
          final halfLen = 1.2 + 1.3 * r2;
          final cx = e.from.x + f.x * e.length * 0.5 - f.y * offsetMag;
          final cy = e.from.y + f.y * e.length * 0.5 + f.x * offsetMag;
          final r = ui.Rect.fromCenter(
            center: ui.Offset(cx, cy),
            width: 2 * halfLen,
            height: 2,
          );
          absorb(r);
          out.add(
            NaturalMediaPrimitive(
              kind: NaturalMediaPrimitiveKind.brushStrand,
              edgeIndex: e.index,
              ordinal: ch,
              channel: NaturalMediaChannel.brushStrand,
              paintBucket: 'brushStrand',
              bounds: r,
              center: Point(cx, cy),
              halfLength: halfLen,
              tangent: f,
              normalOffset: offsetMag,
            ),
          );
        }
      }
    }
  }

  /// 顶点 join：中转角受限 miter（笔肚，miterLimit 截断防尖刺），
  /// 锐转（> brushSharpTurnRad）圆弧 join（防偏移折叠自交）。
  /// [e]/[f] 为前一边与其滤波切线，[next]/[g] 为后一边；key 归 next。
  static void _emitBrushJoin(
    List<NaturalMediaPrimitive> out,
    void Function(ui.Rect) absorb,
    NaturalMediaEdge e,
    NaturalMediaEdge next,
    Point f,
    Point g,
    double hw,
    NaturalMediaTuning tuning,
  ) {
    final eTan = Point(_tx(e), _ty(e));
    final turn = _signedAngle(eTan, next.tangent).abs();
    if (turn > tuning.brushSharpTurnRad) {
      final signed = _signedAngle(eTan, next.tangent);
      for (var j = 1; j <= 3; j++) {
        final a = signed * j / 4;
        final ca = math.cos(a);
        final sa = math.sin(a);
        final rkx = _tx(e) * ca - _ty(e) * sa;
        final rky = _tx(e) * sa + _ty(e) * ca;
        for (var side = 0; side < 2; side++) {
          final sign = side == 0 ? 1.0 : -1.0;
          final ox = e.to.x - rky * sign * hw;
          final oy = e.to.y + rkx * sign * hw;
          final r = ui.Rect.fromCircle(center: ui.Offset(ox, oy), radius: 0);
          absorb(r);
          out.add(
            NaturalMediaPrimitive(
              kind: NaturalMediaPrimitiveKind.brushJoin,
              edgeIndex: next.index,
              ordinal: (side == 0 ? j - 1 : j + 2),
              channel: NaturalMediaChannel.brushBody,
              paintBucket: 'brushJoinArc',
              bounds: r,
              center: Point(ox, oy),
              tangent: Point(rkx, rky),
            ),
          );
        }
      }
    } else {
      final gTan = next.tangent;
      for (var side = 0; side < 2; side++) {
        final sign = side == 0 ? 1.0 : -1.0;
        final n1 = Point(-f.y * sign, f.x * sign);
        final n2 = Point(-g.y * sign, g.x * sign);
        final m = _clampedMiter(e.to, n1, n2, gTan, hw, tuning.miterLimit);
        if (m == null) continue;
        final r = ui.Rect.fromCircle(center: m, radius: 0);
        absorb(r);
        out.add(
          NaturalMediaPrimitive(
            kind: NaturalMediaPrimitiveKind.brushJoin,
            edgeIndex: next.index,
            ordinal: side,
            channel: NaturalMediaChannel.brushBody,
            paintBucket: 'brushJoinMiter',
            bounds: r,
            center: Point(m.dx, m.dy),
            tangent: gTan,
          ),
        );
      }
    }
  }

  /// 两条偏移边界线的交点（受限 miter）：偏移线 A 过 v + n1·hw、方向
  /// t；偏移线 B 过 v + n2·hw、方向 t。距顶点超 miterLimit×hw 截断。
  static ui.Offset? _clampedMiter(
    Point v,
    Point n1,
    Point n2,
    Point t,
    double hw,
    double miterLimit,
  ) {
    final wx = (n2.x - n1.x) * hw;
    final wy = (n2.y - n1.y) * hw;
    final tlen = math.sqrt(t.x * t.x + t.y * t.y);
    if (tlen < 1e-9) return null;
    final tx = t.x / tlen;
    final ty = t.y / tlen;
    final denom = tx * wx + ty * wy;
    final num = wx * wx + wy * wy;
    if (denom.abs() < 1e-9) return null;
    final a = num / denom;
    final ix = v.x + n1.x * hw + tx * a;
    final iy = v.y + n1.y * hw + ty * a;
    final dist = math.sqrt((ix - v.x) * (ix - v.x) + (iy - v.y) * (iy - v.y));
    if (!dist.isFinite) return null;
    if (dist <= miterLimit * hw) return ui.Offset(ix, iy);
    final scale = miterLimit * hw / dist;
    return ui.Offset(v.x + (ix - v.x) * scale, v.y + (iy - v.y) * scale);
  }
}
