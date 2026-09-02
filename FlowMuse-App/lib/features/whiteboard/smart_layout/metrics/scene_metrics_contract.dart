import '../snapshot/deterministic_hash.dart';
import 'semantic_coverage_metric.dart';

/// 渲染后真实 Scene 指标的抽取记录（V3-405A 契约）。
///
/// **只能由 Renderer 在真实 Draft Scene 上产出**（Phase 5 V3-504 接线）：
/// 证据链三件套 [sceneRevision]/[rendererFingerprint]/[renderedSceneDigest]
/// 缺一不可——合成 placement 无法合法构造本类型（无工厂、无捷径；
/// 源码门禁测试钉死本文件不得引用 placement 类型）。
class SceneMetricsExtraction {
  SceneMetricsExtraction({
    required this.sceneRevision,
    required this.rendererFingerprint,
    required this.renderedSceneDigest,
    required this.ledgerSourceIds,
    required this.renderedConsumedSourceIds,
    required this.renderedPreservedSourceIds,
    required this.relationResults,
    required this.orderPairsTotal,
    required this.orderPairsCorrect,
    required this.visualBoundsViolations,
  }) {
    if (sceneRevision < 0) {
      throw StateError('sceneRevision must be non-negative');
    }
    if (rendererFingerprint.isEmpty || renderedSceneDigest.isEmpty) {
      throw StateError(
        'renderer provenance missing: fingerprint and digest are required',
      );
    }
    if (orderPairsTotal < 0 || orderPairsCorrect < 0) {
      throw StateError('order pair counts must be non-negative');
    }
    if (orderPairsCorrect > orderPairsTotal) {
      throw StateError('orderPairsCorrect > orderPairsTotal');
    }
    if (visualBoundsViolations < 0) {
      throw StateError('visualBoundsViolations must be non-negative');
    }
  }

  /// 基线 Scene revision（渲染来源锚点）。
  final int sceneRevision;

  /// Renderer 指纹（渲染管线版本/配置的 canonical hash）。
  final String rendererFingerprint;

  /// 渲染产物 digest（Draft Scene canonical 序列化 hash 或 PNG hash）。
  final String renderedSceneDigest;

  /// 快照源 ledger（权威全集）。
  final List<String> ledgerSourceIds;
  final List<String> renderedConsumedSourceIds;
  final List<String> renderedPreservedSourceIds;

  /// 关系满足表（关系 id → 是否满足；未知关系不进入本表）。
  final List<(String relationId, bool satisfied)> relationResults;

  final int orderPairsTotal;
  final int orderPairsCorrect;
  final int visualBoundsViolations;
}

/// 最终指标快照（全部字段冻结 + 事实指纹；缺字段 fail closed 由
/// [SceneMetricsExtraction] 构造校验承担）。
class SceneMetricsSnapshot {
  const SceneMetricsSnapshot({
    required this.coverage,
    required this.relationCompliance,
    required this.orderPairAccuracy,
    required this.visualBoundsViolations,
    required this.sceneRevision,
    required this.rendererFingerprint,
    required this.renderedSceneDigest,
    required this.factsFingerprint,
  });

  final SemanticCoverageMetric coverage;

  /// 关系满足率（无关系时中性 1.0）。
  final double relationCompliance;

  /// 阅读序相邻对正确率（无对时中性 1.0）。
  final double orderPairAccuracy;

  /// visual bounds 违规计数（含越界/裁切/重叠的统一硬违规计数，
  /// 判定语义归 V3-504 硬门禁；本契约只承载计数）。
  final int visualBoundsViolations;

  final int sceneRevision;
  final String rendererFingerprint;
  final String renderedSceneDigest;
  final String factsFingerprint;
}

/// 真实 Scene metrics 契约（V3-405A）：coverage / relation / order /
/// visual-bounds 四类指标的**唯一**计算与校验入口。
///
/// 合成 placement 不能冒充最终 metrics：本契约不提供任何从
/// placement 层结果构造指标的 API（源码门禁测试钉死零引用），
/// 唯一入口要求 Renderer 证据链齐全，缺失即抛（fail closed）。
class SceneMetricsContract {
  const SceneMetricsContract();

  SceneMetricsSnapshot build(SceneMetricsExtraction extraction) {
    final coverage = SemanticCoverageMetric.of(
      ledgerSourceIds: extraction.ledgerSourceIds,
      renderedConsumedSourceIds: extraction.renderedConsumedSourceIds,
      renderedPreservedSourceIds: extraction.renderedPreservedSourceIds,
    );
    final relations = extraction.relationResults;
    final relationCompliance = relations.isEmpty
        ? 1.0
        : relations.where((r) => r.$2).length / relations.length;
    final orderPairAccuracy = extraction.orderPairsTotal == 0
        ? 1.0
        : extraction.orderPairsCorrect / extraction.orderPairsTotal;

    String n(double v) =>
        v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    final canonical = [
      'rev=${extraction.sceneRevision}',
      'fp=${extraction.rendererFingerprint}',
      'dg=${extraction.renderedSceneDigest}',
      'cov=${n(coverage.consumedFraction)},${n(coverage.preservedFraction)},'
          '${n(coverage.uncoveredFraction)}',
      'rel=${n(relationCompliance)}',
      'ord=${n(orderPairAccuracy)}',
      'vb=${extraction.visualBoundsViolations}',
      ...([
        for (final r in relations)
          '${r.$1}:${r.$2 ? 1 : 0}',
      ]),
    ].join('|');
    return SceneMetricsSnapshot(
      coverage: coverage,
      relationCompliance: relationCompliance,
      orderPairAccuracy: orderPairAccuracy,
      visualBoundsViolations: extraction.visualBoundsViolations,
      sceneRevision: extraction.sceneRevision,
      rendererFingerprint: extraction.rendererFingerprint,
      renderedSceneDigest: extraction.renderedSceneDigest,
      factsFingerprint: fingerprint64('scene-metrics|$canonical'),
    );
  }
}
