import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/src/core/elements/elements.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/core/math/math.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_plan.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/rendering/natural_media/natural_media_stroke_sampler.dart';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// T2：共享采样器验收（计划任务卡）：确定性、分块一致性、固定窗口方向、
// 线性度、退化安全、上限降采样、不可变性。
// ---------------------------------------------------------------------------

List<Point> serpentine(int pointCount) {
  final out = <Point>[];
  var row = 0;
  var goingRight = true;
  while (out.length < pointCount) {
    final y = 20.0 + row * 14.0;
    if (goingRight) {
      for (var x = 20.0; x <= 880 && out.length < pointCount; x += 8) {
        out.add(Point(x, y));
      }
    } else {
      for (var x = 880.0; x >= 20 && out.length < pointCount; x -= 8) {
        out.add(Point(x, y));
      }
    }
    row++;
    goingRight = !goingRight;
  }
  return out;
}

List<double> rampPressures(int n) => [
  for (var i = 0; i < n; i++) 0.15 + 0.7 * i / (n - 1),
];

void main() {
  NaturalMediaStrokePlan samplePencil(
    List<Point> pts,
    List<double> prs, {
    String id = 'sampler-test',
    int? ownedStart,
    int? ownedEnd,
  }) => NaturalMediaStrokeSampler.sample(
    strokeId: id,
    points: pts,
    pressures: prs,
    strokeWidth: 6,
    brushType: BrushType.pencil,
    ownedEdgeStart: ownedStart,
    ownedEdgeEndExclusive: ownedEnd,
  );

  NaturalMediaStrokePlan sampleBrush(
    List<Point> pts,
    List<double> prs, {
    String id = 'sampler-test',
    int? ownedStart,
    int? ownedEnd,
  }) => NaturalMediaStrokeSampler.sample(
    strokeId: id,
    points: pts,
    pressures: prs,
    strokeWidth: 6,
    brushType: BrushType.brushPen,
    ownedEdgeStart: ownedStart,
    ownedEdgeEndExclusive: ownedEnd,
  );

  group('确定性', () {
    test('同输入 100 次输出字段级一致（铅笔与毛笔）', () {
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        final pts = serpentine(120);
        final prs = rampPressures(120);
        NaturalMediaStrokePlan? first;
        for (var i = 0; i < 100; i++) {
          final plan = NaturalMediaStrokeSampler.sample(
            strokeId: 'det-constant-id',
            points: pts,
            pressures: prs,
            strokeWidth: 6,
            brushType: brush,
          );
          if (first == null) {
            first = plan;
          } else {
            expect(plan.strokeSeed, first.strokeSeed);
            expect(
              plan.samples,
              equals(first.samples),
              reason: '$brush samples 第 $i 次',
            );
            expect(
              plan.primitives,
              equals(first.primitives),
              reason: '$brush primitives 第 $i 次',
            );
            expect(plan.bounds, first.bounds);
            expect(plan.stats.primitiveCount, first.stats.primitiveCount);
          }
        }
      }
    });

    test('输入列表不被修改；输出列表不可变', () {
      final pts = [for (final p in serpentine(30)) Point(p.x, p.y)];
      final prs = [...rampPressures(30)];
      final plan = samplePencil(pts, prs);
      expect(pts, equals([for (final p in serpentine(30)) Point(p.x, p.y)]));
      expect(prs, equals(rampPressures(30)));
      expect(
        () => plan.primitives.add(plan.primitives.first),
        throwsUnsupportedError,
      );
      expect(
        () => plan.samples.add(plan.samples.first),
        throwsUnsupportedError,
      );
    });
  });

  group('分块一致性（63/64/65/127/128/129）', () {
    test('任意 64 点分块 owned primitive key 并集 == 整笔且无重复', () {
      for (final brush in [BrushType.pencil, BrushType.brushPen]) {
        final sampler = brush == BrushType.pencil ? samplePencil : sampleBrush;
        for (final total in [63, 64, 65, 127, 128, 129]) {
          final pts = serpentine(total);
          final prs = rampPressures(total);
          final whole = sampler(pts, prs);
          final wholeKeys = whole.primitiveKeyDigest();

          final chunkKeys = <String>[];
          var start = 1; // 原始边索引从 1 起
          while (start < total) {
            final end = math.min(start + 31, total);
            // 分块输入 = 全序列（context 由范围外的点充当），owned 限定。
            final chunk = sampler(pts, prs, ownedStart: start, ownedEnd: end);
            chunkKeys.addAll(chunk.primitiveKeyDigest());
            start = end;
          }

          final wholeSorted = [...wholeKeys]..sort();
          final chunkSorted = [...chunkKeys]..sort();
          expect(
            chunkSorted,
            equals(wholeSorted),
            reason: '$brush total=$total 分块 key 并集应与整笔一致',
          );
          expect(
            chunkSorted.toSet().length,
            chunkSorted.length,
            reason: '$brush total=$total 不应出现重复 key',
          );
        }
      }
    });

    test('边界滤波切线与包络输入逐值一致（毛笔）', () {
      final pts = serpentine(130);
      final prs = rampPressures(130);
      final whole = sampleBrush(pts, prs);
      // 64 边界分块：owned [33, 97)（前 32 条边为 context，覆盖 3-edge
      // stencil 与压力下行判定所需 context）。
      final chunk = sampleBrush(pts, prs, ownedStart: 33, ownedEnd: 97);

      final wholeByEdge = <int, List<NaturalMediaSample>>{};
      for (final s in whole.samples) {
        wholeByEdge.putIfAbsent(s.edgeIndex, () => []).add(s);
      }
      for (final s in chunk.samples) {
        final counterpart = wholeByEdge[s.edgeIndex];
        expect(counterpart, isNotNull, reason: 'edge ${s.edgeIndex}');
        // 分块与整笔在同一 edge 上的采样槽完全一致（含滤波切线/曲率）。
        expect(
          counterpart!.any(
            (w) =>
                w.ordinal == s.ordinal &&
                w.position == s.position &&
                w.filteredTangent == s.filteredTangent &&
                w.pressure == s.pressure &&
                w.curvature == s.curvature,
          ),
          isTrue,
          reason: 'edge ${s.edgeIndex} ordinal ${s.ordinal} 边界一致',
        );
      }
    });
  });

  group('线性度与上限', () {
    test('1k/16k 构建耗时比 ≤20；粒子上限生效', () {
      final results = <int, double>{};
      for (final n in [1000, 16000]) {
        final pts = serpentine(n);
        final prs = rampPressures(n);
        final sw = Stopwatch()..start();
        final plan = samplePencil(pts, prs, id: 'lin-$n');
        sw.stop();
        results[n] = sw.elapsedMicroseconds / 1000.0;
        expect(plan.stats.particleCount, lessThanOrEqualTo(4096));
        expect(plan.stats.hitParticleCap, isTrue, reason: '长笔应触发上限');
      }
      final ratio = results[16000]! / math.max(results[1000]!, 1e-9);
      expect(
        ratio,
        lessThanOrEqualTo(20),
        reason: '16k/1k = $ratio 应 ≤20（无 O(n²)）',
      );
    });

    test('上限降采样保留首尾与压力极值段', () {
      // 压力坡道：降采样后重压区仍有颗粒（N2 不得被限流抹平）。
      final pts = serpentine(2000);
      final prs = rampPressures(2000);
      final plan = samplePencil(pts, prs);
      expect(plan.stats.particleCount, lessThanOrEqualTo(4096));
      // 首/尾 edge 的颗粒存在。
      final firstEdge = plan.edges.first.index;
      final lastEdge = plan.edges.last.index;
      expect(
        plan.primitives.any((p) => p.edgeIndex == firstEdge),
        isTrue,
        reason: '首边颗粒保留',
      );
      expect(
        plan.primitives.any((p) => p.edgeIndex == lastEdge),
        isTrue,
        reason: '尾边颗粒保留',
      );
      // 重压段（后 20% 边）颗粒存在且包含 heavy 桶。
      final heavyEdges = plan.edges
          .where((e) => e.arcStart > plan.edges.last.arcStart * 0.8)
          .map((e) => e.index)
          .toSet();
      expect(
        plan.primitives.any(
          (p) => heavyEdges.contains(p.edgeIndex) && p.channel == 3,
        ),
        isTrue,
        reason: '压力极值段的重压桶颗粒保留',
      );
    });
  });

  group('退化与安全', () {
    test('单点：dot/teardrop 退化，不虚构方向，bounds 有限', () {
      final plan = sampleBrush([const Point(10, 10)], [0.5]);
      expect(plan.stats.edgeCount, 0);
      expect(plan.primitives, hasLength(1));
      expect(
        plan.primitives.single.kind,
        NaturalMediaPrimitiveKind.brushTeardrop,
      );
      expect(plan.bounds.isFinite, isTrue);
      expect(plan.bounds.width, greaterThan(0));
    });

    test('重复点/零长边：跳过不死循环，key 稳定', () {
      final pts = [
        const Point(0, 0),
        const Point(0, 0), // 零长
        const Point(10, 0),
        const Point(10, 0), // 零长
        const Point(20, 0),
      ];
      final plan = samplePencil(pts, [0.5, 0.5, 0.6, 0.6, 0.7]);
      expect(plan.stats.edgeCount, 2, reason: '两条有效边');
      // 原始边索引保持（跳过的零长边不占 key 空间也不折叠索引）。
      expect(plan.edges.map((e) => e.index), equals([2, 4]));
      final again = samplePencil(pts, [0.5, 0.5, 0.6, 0.6, 0.7]);
      expect(again.primitives, equals(plan.primitives));
    });

    test('非有限坐标/压力：丢弃计数，不死循环不越界', () {
      final pts = [
        const Point(0, 0),
        Point(double.nan, 0),
        const Point(10, 0),
        Point(10, double.infinity),
        const Point(20, 0),
      ];
      final prs = [0.5, double.nan, double.nan, 0.5, 0.7];
      final plan = samplePencil(pts, prs);
      expect(
        plan.stats.droppedNonFinite,
        greaterThanOrEqualTo(3),
        reason: '两个非有限点 + 一个非有限压力',
      );
      expect(plan.stats.validPointCount, 3);
      expect(plan.bounds.isFinite, isTrue);
    });

    test('owned 范围越界/乱序：安全钳制不抛异常', () {
      final pts = serpentine(20);
      final prs = rampPressures(20);
      // end < start / 超大范围 / 负值都不得崩。
      expect(
        () => samplePencil(pts, prs, ownedStart: 10, ownedEnd: 5),
        returnsNormally,
      );
      expect(
        () => samplePencil(pts, prs, ownedStart: -100, ownedEnd: 10000),
        returnsNormally,
      );
      final clamped = samplePencil(pts, prs, ownedStart: 5, ownedEnd: 10);
      expect(clamped.primitives, isNotEmpty);
      for (final p in clamped.primitives) {
        expect(p.edgeIndex, greaterThanOrEqualTo(5));
        expect(p.edgeIndex, lessThan(10));
      }
    });
  });

  group('结构与 bounds', () {
    test('plannedPathCount：铅笔 ≤4、毛笔 ≤2；bounds 覆盖全部 primitive', () {
      final pts = serpentine(80);
      final prs = rampPressures(80);
      final pencil = samplePencil(pts, prs);
      final brush = sampleBrush(pts, prs);
      expect(pencil.stats.plannedPathCount, lessThanOrEqualTo(4));
      expect(brush.stats.plannedPathCount, lessThanOrEqualTo(2));
      for (final plan in [pencil, brush]) {
        for (final p in plan.primitives) {
          expect(
            plan.bounds.contains(ui.Offset(p.bounds.left, p.bounds.top)),
            isTrue,
            reason: '$p 应在 plan bounds 内',
          );
        }
      }
    });
  });
}
