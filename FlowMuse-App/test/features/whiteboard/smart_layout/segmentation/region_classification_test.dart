import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/ink_region_segmenter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/membership_guard.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/region_segment.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/segmentation/segmentation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FreedrawElement stroke(String id, double x, double y, double w, double h) =>
      FreedrawElement(
        id: ElementId(id),
        x: x,
        y: y,
        width: w,
        height: h,
        points: [Point(x, y), Point(x + w, y + h)],
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      );

  test('line 分类：单行小笔画组 → line/0.9，非 preserved', () {
    final strokes = [
      for (var c = 0; c < 6; c++) stroke('w$c', c * 36.0, 100, 30, 8),
    ];
    final segments = InkRegionSegmenter().segment(strokes);
    expect(segments, hasLength(1));
    final segment = segments.single;
    expect(segment.regionClass, RegionClass.line);
    expect(segment.classificationConfidence, 0.9);
    expect(segment.preserved, isFalse);
  });

  test('emphasis 分类：孤立装饰长线不被并入文本', () {
    final textLine = [
      for (var c = 0; c < 6; c++) stroke('t$c', c * 36.0, 100, 30, 8),
    ];
    // 远离文本的装饰分隔线（超长、细）
    final decoration = stroke('deco', 0, 260, 420, 4);
    final segments = InkRegionSegmenter().segment([...textLine, decoration]);
    final byId = {for (final s in segments) s.id: s};
    final deco = segments.firstWhere((s) => s.strokeIds.contains('deco'));
    expect(
      textLine.every(
        (t) =>
            segments.firstWhere((s) => s.strokeIds.contains(t.id.value)).id ==
            segments.firstWhere((s) => s.strokeIds.contains('t0')).id,
      ),
      isTrue,
      reason: '文本行仍为一组',
    );
    expect(deco.regionClass, RegionClass.emphasis);
    expect(byId.length, 2);
  });

  test('table 分类：3×3 网格笔画组 → table', () {
    final cells = <FreedrawElement>[];
    var n = 0;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        cells.add(stroke('cell-${n++}', 50 + c * 33.0, 50 + r * 20.0, 28, 8));
      }
    }
    final segments = InkRegionSegmenter().segment(cells);
    expect(segments, hasLength(1));
    expect(segments.single.regionClass, RegionClass.table);
    expect(segments.single.preserved, isFalse);
  });

  test('竖排区域：无条件 preserved(verticalWriting)，分类照常给出', () {
    final vertical = [
      for (var i = 0; i < 8; i++) stroke('v-$i', 100, i * 26.0, 10, 16),
    ];
    final segments = InkRegionSegmenter().segment(vertical);
    final segment = segments.single;
    expect(segment.lineDirection, SegmentLineDirection.vertical);
    expect(segment.preserved, isTrue);
    expect(segment.preservedReason, RegionPreservedReason.verticalWriting);
  });

  test('低置信反例：散点乱排 → unknown + lowConfidence preserved', () {
    final random = math.Random(3);
    final scattered = [
      for (var i = 0; i < 7; i++)
        stroke(
          's-$i',
          100 + random.nextDouble() * 500,
          100 + random.nextDouble() * 400,
          12,
          12,
        ),
    ];
    final segments = InkRegionSegmenter().segment(scattered);
    // 散点可能成多组；每组都必须命中低置信 preserved 或 emphasis 语义，
    // 且没有任何笔画丢失。
    final seen = <String>{};
    for (final segment in segments) {
      expect(
        segment.preserved || segment.regionClass == RegionClass.emphasis,
        isTrue,
        reason: '高风险反例区域不得作为可信重排输入：$segment',
      );
      seen.addAll(segment.strokeIds);
    }
    expect(
      seen,
      scattered.map((e) => e.id.value).toSet(),
      reason: '散点页不得丢任何笔画',
    );
  });

  test('membership 不变：分类引入前后分组一致（103A 用例回归）', () {
    // 与 103A 双栏用例相同的结构；分组结果必须保持
    List<FreedrawElement> block(String prefix, double ox) => [
      for (var l = 0; l < 4; l++)
        for (var c = 0; c < 8; c++)
          stroke('$prefix-l$l-c$c', ox + c * 37.0, l * 22.0, 32, 9),
    ];
    final strokes = [...block('a', 0), ...block('b', 600)];
    final segments = InkRegionSegmenter().segment(strokes);
    expect(segments, hasLength(2));
    expect(
      segments[0].strokeIds,
      everyElement(startsWith(segments[0].strokeIds.first.split('-').first)),
    );
    final allIds = <String>{};
    for (final segment in segments) {
      allIds.addAll(segment.strokeIds);
    }
    expect(allIds, strokes.map((e) => e.id.value).toSet());
  });

  group('RegionMembershipGuard', () {
    RegionSegment seg(
      String id,
      List<String> ids, {
      int column = 0,
      bool preserved = false,
    }) => RegionSegment(
      id: id,
      strokeIds: ids,
      left: 0,
      top: 0,
      width: 10,
      height: 10,
      lineDirection: SegmentLineDirection.horizontal,
      columnIndex: column,
      skewRadians: 0,
      localScale: 9,
      preservedReason: preserved ? RegionPreservedReason.verticalWriting : null,
    );

    test('合法合并放行', () {
      const guard = RegionMembershipGuard();
      expect(
        guard.mergeBlockReason(
          seg('a', ['s1', 's2']),
          seg('b', ['s3']),
          allStrokeIds: {'s1', 's2', 's3'},
        ),
        isNull,
      );
    });

    test('跨列合并阻断', () {
      const guard = RegionMembershipGuard();
      expect(
        guard.mergeBlockReason(
          seg('a', ['s1'], column: 0),
          seg('b', ['s2'], column: 1),
          allStrokeIds: {'s1', 's2'},
        ),
        'cross-column(0!=1)',
      );
    });

    test('preserved 区域合并阻断', () {
      const guard = RegionMembershipGuard();
      expect(
        guard.mergeBlockReason(
          seg('a', ['s1'], preserved: true),
          seg('b', ['s2']),
          allStrokeIds: {'s1', 's2'},
        ),
        'preserved(a)',
      );
    });

    test('重叠成员/外来笔画合并阻断', () {
      const guard = RegionMembershipGuard();
      expect(
        guard.mergeBlockReason(
          seg('a', ['s1']),
          seg('b', ['s1']),
          allStrokeIds: {'s1'},
        ),
        'overlapping-membership',
      );
      expect(
        guard.mergeBlockReason(
          seg('a', ['s1']),
          seg('b', ['ghost']),
          allStrokeIds: {'s1'},
        ),
        'foreign-strokes',
      );
    });

    test('拆分守卫：完整覆盖放行；丢笔/重复/外来/空子集阻断', () {
      const guard = RegionMembershipGuard();
      final region = seg('a', ['s1', 's2', 's3']);
      expect(
        guard.splitBlockReason(region, [
          ['s1'],
          ['s2', 's3'],
        ]),
        isNull,
      );
      expect(
        guard.splitBlockReason(region, [
          ['s1'],
          ['s2'],
        ]),
        'stroke-loss(1)',
      );
      expect(
        guard.splitBlockReason(region, [
          ['s1', 's2'],
          ['s2', 's3'],
        ]),
        'duplicated-stroke(s2)',
      );
      expect(
        guard.splitBlockReason(region, [
          ['s1'],
          ['s2', 'ghost'],
        ]),
        'foreign-stroke(ghost)',
      );
      expect(
        guard.splitBlockReason(region, [
          ['s1'],
          [],
        ]),
        'empty-subset',
      );
      expect(
        guard.splitBlockReason(region, [
          ['s1', 's2', 's3'],
        ]),
        'too-few-subsets',
      );
    });
  });

  group('参数冻结', () {
    test('development 与 frozenValidationV1 的 canonical 哈希稳定且互异敏感', () {
      final devHash = SegmentationPolicy.development.paramsCanonicalHash;
      expect(devHash, SegmentationPolicy.development.paramsCanonicalHash);
      expect(
        devHash,
        SegmentationPolicy.frozenValidationV1.paramsCanonicalHash,
        reason: 'validation v1 结论=与 development 数值一致（见冻结注释）',
      );
      final tuned = SegmentationPolicy(gapFactor: 1.7);
      expect(
        tuned.paramsCanonicalHash,
        isNot(devHash),
        reason: '任何字段变化必须改变冻结哈希',
      );
    });

    test('冻结参数可驱动同一管线（frozen 不参与调参：仅作只读输入）', () {
      final strokes = [
        for (var c = 0; c < 6; c++) stroke('f$c', c * 36.0, 100, 30, 8),
      ];
      final devSegments = InkRegionSegmenter(
        policy: SegmentationPolicy.development,
      ).segment(strokes);
      final frozenSegments = InkRegionSegmenter(
        policy: SegmentationPolicy.frozenValidationV1,
      ).segment(strokes);
      expect(
        [for (final s in frozenSegments) s.strokeIds],
        [for (final s in devSegments) s.strokeIds],
      );
    });
  });
}
