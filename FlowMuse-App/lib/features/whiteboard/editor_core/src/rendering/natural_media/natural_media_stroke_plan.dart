import 'dart:ui' as ui;

import '../../core/math/math.dart';
import 'deterministic_stroke_seed.dart';

// ---------------------------------------------------------------------------
// 自然介质采样计划（计划 §3.3）：不可变输出。
//
// Canvas / 本地湿墨 / 远端湿墨 / SVG 与测试共同消费：渲染器只允许把
// plan 里的 sample/primitive 绘制出来，不允许重新推导几何或另设常数。
// ---------------------------------------------------------------------------

/// 一条原始边（points[i] → points[i+1]）的稳定视图。
class NaturalMediaEdge {
  const NaturalMediaEdge({
    required this.index,
    required this.from,
    required this.to,
    required this.length,
    required this.arcStart,
    required this.pressure,
  });

  /// 原始边索引（i，1-based 语义：连接 points[i-1]→points[i] 的第 i 条
  /// 边记为 i，与 primitive key 的 edgeStartIndex 同源）。
  final int index;
  final Point from;
  final Point to;
  final double length;

  /// 该边起点在整笔折线中的累计弧长。
  final double arcStart;

  /// 边平均压力（端点插值的基准）。
  final double pressure;

  Point get tangent => length <= 0
      ? const Point(1, 0)
      : Point((to.x - from.x) / length, (to.y - from.y) / length);
}

/// 边内等距采样槽（edge-local，ordinal 从边起点计数）。
class NaturalMediaSample {
  const NaturalMediaSample({
    required this.edgeIndex,
    required this.ordinal,
    required this.s,
    required this.position,
    required this.tangent,
    required this.filteredTangent,
    required this.pressure,
    required this.curvature,
  });

  final int edgeIndex;
  final int ordinal;

  /// 边内弧长位置（0 ~ edge.length）。
  final double s;
  final Point position;

  /// 所在边原始单位切线。
  final Point tangent;

  /// §3.4 三 edge 固定窗口滤波切线（毛笔方向滞后 / 铅笔颗粒朝向）。
  final Point filteredTangent;

  Point get filteredNormal => Point(-filteredTangent.y, filteredTangent.x);

  final double pressure;

  /// 离散曲率：相邻滤波切线带符号转角 / 弧长步（rad/px）。
  final double curvature;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaturalMediaSample &&
          edgeIndex == other.edgeIndex &&
          ordinal == other.ordinal &&
          s == other.s &&
          position == other.position &&
          tangent == other.tangent &&
          filteredTangent == other.filteredTangent &&
          pressure == other.pressure &&
          curvature == other.curvature;

  @override
  // fnv 系 hashCode：natural_media 目录禁用 Object.hash（源码门禁）。
  int get hashCode => mix32(
    strokeSeedOf('$edgeIndex|$ordinal|$s|${position.x}|${position.y}'),
    (pressure * 1e6).toInt() & 0x7fffffff,
    (filteredTangent.x * 1e6).toInt() & 0x7fffffff,
    (filteredTangent.y * 1e6).toInt() & 0x7fffffff,
  );
}

/// primitive 种类。
enum NaturalMediaPrimitiveKind {
  pencilBase,
  pencilGrain,
  brushEnvelopeVertex,
  brushJoin,
  brushStrand,
  brushTeardrop,
}

/// 单个 primitive：kind/channel/key/几何参数/paint bucket（§3.3）。
///
/// key 三元组 (edgeIndex, ordinal, channel) 唯一；join 归较后 edge。
/// 几何参数按 kind 解释（颗粒 = 椭圆中心/半长/半厚/切向；包络顶点 =
/// 位置/法向半宽；毫丝 = 中心/半长/切向/法向偏移）。
class NaturalMediaPrimitive {
  const NaturalMediaPrimitive({
    required this.kind,
    required this.edgeIndex,
    required this.ordinal,
    required this.channel,
    required this.paintBucket,
    required this.bounds,
    this.center,
    this.halfLength,
    this.halfThickness,
    this.tangent,
    this.normalOffset,
  });

  final NaturalMediaPrimitiveKind kind;
  final int edgeIndex;
  final int ordinal;
  final int channel;
  final String paintBucket;
  final ui.Rect bounds;

  final Point? center;
  final double? halfLength;
  final double? halfThickness;
  final Point? tangent;

  /// 包络顶点相对中心线的法向偏移（带符号）。
  final double? normalOffset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaturalMediaPrimitive &&
          kind == other.kind &&
          edgeIndex == other.edgeIndex &&
          ordinal == other.ordinal &&
          channel == other.channel &&
          paintBucket == other.paintBucket &&
          bounds == other.bounds &&
          center == other.center &&
          halfLength == other.halfLength &&
          halfThickness == other.halfThickness &&
          tangent == other.tangent &&
          normalOffset == other.normalOffset;

  @override
  int get hashCode => mix32(
    strokeSeedOf('$kind|$edgeIndex|$ordinal|$channel|$paintBucket'),
    bounds.left.toInt(),
    bounds.top.toInt(),
    0,
  );

  @override
  String toString() =>
      'Primitive(${kind.name},e:$edgeIndex,o:$ordinal,ch:$channel)';
}

/// 结构计数与降级标记（§6.1 性能门禁的探针来源）。
class NaturalMediaPlanStats {
  const NaturalMediaPlanStats({
    required this.inputPointCount,
    required this.validPointCount,
    required this.edgeCount,
    required this.sampleCount,
    required this.primitiveCount,
    required this.particleCount,
    required this.plannedPathCount,
    required this.hitParticleCap,
    required this.hitSampleCap,
    required this.droppedNonFinite,
  });

  final int inputPointCount;
  final int validPointCount;
  final int edgeCount;
  final int sampleCount;
  final int primitiveCount;

  /// 颗粒/毫丝类 primitive 数（受 [hitParticleCap] 约束的计数）。
  final int particleCount;

  /// 渲染器的主要 drawPath 预算（铅笔 ≤4 / 毛笔 ≤2）。
  final int plannedPathCount;
  final bool hitParticleCap;
  final bool hitSampleCap;
  final int droppedNonFinite;
}

/// 不可变采样计划。
class NaturalMediaStrokePlan {
  const NaturalMediaStrokePlan({
    required this.strokeSeed,
    required this.edges,
    required this.samples,
    required this.primitives,
    required this.bounds,
    required this.stats,
  });

  final int strokeSeed;
  final List<NaturalMediaEdge> edges;
  final List<NaturalMediaSample> samples;
  final List<NaturalMediaPrimitive> primitives;
  final ui.Rect bounds;
  final NaturalMediaPlanStats stats;

  /// owned edge 范围内 primitive key 的稳定摘要（分块一致性断言用）。
  List<String> primitiveKeyDigest() => [
    for (final p in primitives)
      '${p.edgeIndex}:${p.ordinal}:${p.channel}:${p.kind.name}',
  ];
}
