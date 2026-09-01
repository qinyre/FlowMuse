import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_structure_signature.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/scene_metrics_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/semantic_coverage_metric.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-405A：完整 placement 上的结构签名与去重 + 真实 Scene metrics
/// 契约（coverage/relation/order/visual-bounds；缺字段 fail closed，
/// 合成 placement 不能冒充）。
void main() {
  const signature = LayoutStructureSignature();
  const deduplicator = LayoutPlacementDeduplicator();

  PlacedBlock p(
    String id,
    int column,
    double top,
    double font,
  ) =>
      PlacedBlock(
        blockId: id,
        rect: LayoutRect(left: column * 612.0, top: top, width: 588, height: 100),
        columnIndex: column,
        lineCount: 2,
        appliedFontSize: font,
        shrunk: font != 20,
      );

  test('结构签名：同结构（坐标差）等价；叙事差异不等价', () {
    final base = [p('a', 0, 0, 20), p('b', 0, 124, 20), p('c', 1, 0, 20)];
    final sameStructureShifted = [
      p('a', 0, 40, 20),
      p('b', 0, 200, 20),
      p('c', 1, 88, 20),
    ];
    // 同栏同序同字号、仅坐标不同 → 等价。
    expect(
      signature.of(skeleton: LayoutSkeleton.twoColumn, placed: base),
      signature.of(
        skeleton: LayoutSkeleton.twoColumn,
        placed: sameStructureShifted,
      ),
    );

    // 块换栏（叙事指派变化）→ 不等价。
    final swapped = [p('a', 1, 0, 20), p('b', 0, 124, 20), p('c', 0, 0, 20)];
    expect(
      signature.of(skeleton: LayoutSkeleton.twoColumn, placed: base),
      isNot(
        signature.of(skeleton: LayoutSkeleton.twoColumn, placed: swapped),
      ),
    );

    // 栏内堆叠序变化 → 不等价。
    final reordered = [p('a', 0, 124, 20), p('b', 0, 0, 20), p('c', 1, 0, 20)];
    expect(
      signature.of(skeleton: LayoutSkeleton.twoColumn, placed: base),
      isNot(
        signature.of(skeleton: LayoutSkeleton.twoColumn, placed: reordered),
      ),
    );

    // 生效字号变化（缩档差异）→ 不等价。
    final shrunk = [p('a', 0, 0, 12), p('b', 0, 124, 20), p('c', 1, 0, 20)];
    expect(
      signature.of(skeleton: LayoutSkeleton.twoColumn, placed: base),
      isNot(signature.of(skeleton: LayoutSkeleton.twoColumn, placed: shrunk)),
    );

    // 骨架不同 → 不等价。
    expect(
      signature.of(skeleton: LayoutSkeleton.twoColumn, placed: base),
      isNot(signature.of(skeleton: LayoutSkeleton.single, placed: base)),
    );
  });

  test('去重：只删等价结构、保留首个、零静默；双跑确定', () {
    final entryA = PlacementEntry(
      candidateId: 'twoColumn#1',
      skeleton: LayoutSkeleton.twoColumn,
      placed: [p('a', 0, 0, 20), p('b', 0, 124, 20)],
    );
    // 与 A 等价：同栏同序同字号，坐标平移（不同候选推导出的同结构）。
    final entryA2 = PlacementEntry(
      candidateId: 'mainSide#2',
      skeleton: LayoutSkeleton.mainSide,
      placed: [p('a', 0, 60, 20), p('b', 0, 300, 20)],
    );
    // 注意：骨架不同 ⇒ 不等价（上面 entryA2 骨架是 mainSide）。
    final entryB = PlacementEntry(
      candidateId: 'single#0',
      skeleton: LayoutSkeleton.single,
      placed: [p('a', 0, 0, 20), p('b', 0, 124, 20)],
    );
    // 与 A 完全同构同骨架（坐标差）⇒ 等价，应被删。
    final entryA3 = PlacementEntry(
      candidateId: 'twoColumn#1-variant',
      skeleton: LayoutSkeleton.twoColumn,
      placed: [p('a', 0, 24, 20), p('b', 0, 480, 20)],
    );
    final result = deduplicator.dedupe([entryA, entryA2, entryB, entryA3]);
    expect(result.kept.map((e) => e.candidateId), [
      'twoColumn#1',
      'mainSide#2',
      'single#0',
    ]);
    expect(result.dropped.length, 1);
    expect(result.dropped.first.candidateId, 'twoColumn#1-variant');
    expect(
      result.dropped.first.equivalentToCandidateId,
      'twoColumn#1',
      reason: '等价于首个保留者',
    );
    // 确定性。
    final again = deduplicator.dedupe([entryA, entryA2, entryB, entryA3]);
    expect(
      again.dropped.map((d) => d.signature).toList(),
      result.dropped.map((d) => d.signature).toList(),
    );
  });

  test('语义覆盖：全覆盖 1.0；缺失列出；未知/重复 fail closed', () {
    final full = SemanticCoverageMetric.of(
      ledgerSourceIds: ['a', 'b', 'c'],
      renderedConsumedSourceIds: ['a', 'b'],
      renderedPreservedSourceIds: ['c'],
    );
    expect(full.fullyCovered, isTrue);
    expect(full.consumedFraction, 2 / 3);
    expect(full.preservedFraction, 1 / 3);
    expect(full.uncoveredFraction, 0.0);

    final partial = SemanticCoverageMetric.of(
      ledgerSourceIds: ['a', 'b', 'c'],
      renderedConsumedSourceIds: ['a'],
      renderedPreservedSourceIds: [],
    );
    expect(partial.fullyCovered, isFalse);
    expect(partial.missingSourceIds, ['b', 'c']);
    expect(partial.uncoveredFraction, 2 / 3);

    // 空 ledger 合法（空文档）：全覆盖中性。
    final empty = SemanticCoverageMetric.of(
      ledgerSourceIds: [],
      renderedConsumedSourceIds: [],
      renderedPreservedSourceIds: [],
    );
    expect(empty.fullyCovered, isTrue);

    expect(
      () => SemanticCoverageMetric.of(
        ledgerSourceIds: ['a'],
        renderedConsumedSourceIds: ['ghost'],
        renderedPreservedSourceIds: [],
      ),
      throwsStateError,
      reason: '渲染出 ledger 外的源 = fail closed',
    );
    expect(
      () => SemanticCoverageMetric.of(
        ledgerSourceIds: ['a'],
        renderedConsumedSourceIds: ['a'],
        renderedPreservedSourceIds: ['a'],
      ),
      throwsStateError,
      reason: '同一源既消费又保留 = fail closed',
    );
    expect(
      () => SemanticCoverageMetric.of(
        ledgerSourceIds: ['a', 'a'],
        renderedConsumedSourceIds: [],
        renderedPreservedSourceIds: [],
      ),
      throwsStateError,
      reason: 'ledger 重复 = fail closed',
    );
  });

  test('Scene metrics 契约：四类指标计算 + 事实指纹 + 证据链 fail closed', () {
    const contract = SceneMetricsContract();
    final extraction = SceneMetricsExtraction(
      sceneRevision: 7,
      rendererFingerprint: 'renderer-v3@abc123',
      renderedSceneDigest: 'sha256:deadbeef',
      ledgerSourceIds: ['s1', 's2', 's3', 's4'],
      renderedConsumedSourceIds: ['s1', 's2', 's3'],
      renderedPreservedSourceIds: ['s4'],
      relationResults: [('cap-of-fig', true), ('keep-with', false)],
      orderPairsTotal: 10,
      orderPairsCorrect: 9,
      visualBoundsViolations: 0,
    );
    final snapshot = contract.build(extraction);
    expect(snapshot.coverage.fullyCovered, isTrue);
    expect(snapshot.relationCompliance, 0.5);
    expect(snapshot.orderPairAccuracy, 0.9);
    expect(snapshot.visualBoundsViolations, 0);
    expect(snapshot.sceneRevision, 7);
    expect(snapshot.factsFingerprint, isNotEmpty);
    // 双跑确定。
    final again = contract.build(extraction);
    expect(again.factsFingerprint, snapshot.factsFingerprint);

    // 证据链缺失 → 构造即抛（合成 placement 冒充不了）。
    expect(
      () => SceneMetricsExtraction(
        sceneRevision: 7,
        rendererFingerprint: '',
        renderedSceneDigest: 'sha256:deadbeef',
        ledgerSourceIds: ['s1'],
        renderedConsumedSourceIds: ['s1'],
        renderedPreservedSourceIds: [],
        relationResults: [],
        orderPairsTotal: 0,
        orderPairsCorrect: 0,
        visualBoundsViolations: 0,
      ),
      throwsStateError,
      reason: '缺 renderer 指纹 = fail closed',
    );
    expect(
      () => SceneMetricsExtraction(
        sceneRevision: 7,
        rendererFingerprint: 'fp',
        renderedSceneDigest: '',
        ledgerSourceIds: ['s1'],
        renderedConsumedSourceIds: ['s1'],
        renderedPreservedSourceIds: [],
        relationResults: [],
        orderPairsTotal: 0,
        orderPairsCorrect: 0,
        visualBoundsViolations: 0,
      ),
      throwsStateError,
      reason: '缺渲染产物 digest = fail closed',
    );
    expect(
      () => SceneMetricsExtraction(
        sceneRevision: 7,
        rendererFingerprint: 'fp',
        renderedSceneDigest: 'dg',
        ledgerSourceIds: ['s1'],
        renderedConsumedSourceIds: ['s1'],
        renderedPreservedSourceIds: [],
        relationResults: [],
        orderPairsTotal: 3,
        orderPairsCorrect: 4,
        visualBoundsViolations: 0,
      ),
      throwsStateError,
      reason: 'correct > total = fail closed',
    );
    // 契约计算内的覆盖 fail closed 同样生效（build 内部复用 of）。
    expect(
      () => contract.build(SceneMetricsExtraction(
        sceneRevision: 1,
        rendererFingerprint: 'fp',
        renderedSceneDigest: 'dg',
        ledgerSourceIds: ['s1'],
        renderedConsumedSourceIds: ['unknown'],
        renderedPreservedSourceIds: [],
        relationResults: [],
        orderPairsTotal: 0,
        orderPairsCorrect: 0,
        visualBoundsViolations: 0,
      )),
      throwsStateError,
    );

    // 无关系/无序对时中性 1.0。
    final neutral = contract.build(SceneMetricsExtraction(
      sceneRevision: 0,
      rendererFingerprint: 'fp',
      renderedSceneDigest: 'dg',
      ledgerSourceIds: ['s1'],
      renderedConsumedSourceIds: ['s1'],
      renderedPreservedSourceIds: [],
      relationResults: [],
      orderPairsTotal: 0,
      orderPairsCorrect: 0,
      visualBoundsViolations: 0,
    ));
    expect(neutral.relationCompliance, 1.0);
    expect(neutral.orderPairAccuracy, 1.0);
  });

  test('源码门禁：scene metrics 契约不得引用 placement 类型（合成冒充隔离）', () {
    final source = File(
      'lib/features/whiteboard/smart_layout/metrics/scene_metrics_contract.dart',
    ).readAsStringSync();
    for (final banned in [
      'PlacedBlock',
      'BalancedPlacement',
      'FlowPlacer',
      'placement/flow_placer.dart',
      'placement/balanced_flow_placer.dart',
    ]) {
      expect(source.contains(banned), isFalse, reason: '契约不得引用 $banned');
    }
  });
}
