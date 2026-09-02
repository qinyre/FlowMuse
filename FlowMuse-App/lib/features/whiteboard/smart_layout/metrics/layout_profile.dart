import 'layout_metric_contract.dart';
import 'anti_gaming_veto.dart';

/// 三个用户目标的排序 profile（V3-404A 冻结 v1）：
/// 增强可读性 / 尽量保留原结构 / 突出图文展示。
///
/// 共用契约：同一生成器、同一硬约束、同一指标向量——profile 只冻结
/// 排序权重，不引入额外指标或通道；权重和恒为 1。
enum LayoutProfileId {
  readability,
  structurePreservation,
  figureEmphasis,
}

/// 冻结权重表（只读；测试钉住权重和 = 1）。
class LayoutProfile {
  const LayoutProfile._({
    required this.id,
    required this.weights,
    required this.rationale,
  });

  final LayoutProfileId id;
  final Map<LayoutMetricId, double> weights;

  /// 设计意图一句话（审计用，不参与计算）。
  final String rationale;

  /// 增强可读性：层级/顺序/密度为主。
  static const LayoutProfile readability = LayoutProfile._(
    id: LayoutProfileId.readability,
    weights: {
      LayoutMetricId.hierarchy: 0.20,
      LayoutMetricId.readingOrder: 0.20,
      LayoutMetricId.figureTextAffinity: 0.10,
      LayoutMetricId.alignmentRhythm: 0.15,
      LayoutMetricId.densityWhitespace: 0.20,
      LayoutMetricId.visualBalance: 0.10,
      LayoutMetricId.modificationCost: 0.05,
    },
    rationale: '可读性优先：层级、阅读序与密度留白主导排序',
  );

  /// 尽量保留原结构：改动成本主导。
  static const LayoutProfile structurePreservation = LayoutProfile._(
    id: LayoutProfileId.structurePreservation,
    weights: {
      LayoutMetricId.hierarchy: 0.10,
      LayoutMetricId.readingOrder: 0.15,
      LayoutMetricId.figureTextAffinity: 0.15,
      LayoutMetricId.alignmentRhythm: 0.10,
      LayoutMetricId.densityWhitespace: 0.10,
      LayoutMetricId.visualBalance: 0.05,
      LayoutMetricId.modificationCost: 0.35,
    },
    rationale: '原结构优先：改动成本主导，顺序与图文亲和次之',
  );

  /// 突出图文展示：图文亲和与视觉平衡主导。
  static const LayoutProfile figureEmphasis = LayoutProfile._(
    id: LayoutProfileId.figureEmphasis,
    weights: {
      LayoutMetricId.hierarchy: 0.10,
      LayoutMetricId.readingOrder: 0.10,
      LayoutMetricId.figureTextAffinity: 0.30,
      LayoutMetricId.alignmentRhythm: 0.10,
      LayoutMetricId.densityWhitespace: 0.10,
      LayoutMetricId.visualBalance: 0.20,
      LayoutMetricId.modificationCost: 0.10,
    },
    rationale: '图文展示优先：图文亲和与视觉平衡主导排序',
  );

  static const List<LayoutProfile> all = [
    readability,
    structurePreservation,
    figureEmphasis,
  ];
}

/// 单指标贡献（可解释分解的最小单元：value × weight = contribution）。
class MetricContribution {
  const MetricContribution({
    required this.id,
    required this.value,
    required this.weight,
  });

  final LayoutMetricId id;
  final double value;
  final double weight;

  double get contribution => value * weight;
}

/// profile 排序结果：score 恒等于 Σ entries.contribution（可还原；
/// 测试以 1e-12 容差钉住）。
class ProfileScore {
  const ProfileScore({
    required this.profileId,
    required this.score,
    required this.entries,
    required this.factsFingerprint,
  });

  final LayoutProfileId profileId;
  final double score;
  final List<MetricContribution> entries;
  final String factsFingerprint;
}

/// 否决：命中反投机否决线的候选不参与排序（无论软分多高）。
class ProfileGamingRejected {
  const ProfileGamingRejected({required this.kinds, required this.reasons});

  final List<AntiGamingVetoKind> kinds;
  final List<String> reasons;
}

/// profile 排序器（V3-404A）：输入硬通过后的指标向量 + 否决结论，
/// 输出可还原分解。三 profile 共用同一向量——只是权重不同。
class LayoutProfileScorer {
  const LayoutProfileScorer();

  Object rank(
    LayoutProfile profile,
    LayoutMetricVector vector,
    VetoVerdict veto,
  ) {
    if (veto.vetoed) {
      return ProfileGamingRejected(kinds: veto.kinds, reasons: veto.reasons);
    }
    var score = 0.0;
    final entries = <MetricContribution>[];
    for (final def in LayoutMetricContract.definitions) {
      final weight = profile.weights[def.id]!;
      final value = vector.values[def.id]!;
      final entry = MetricContribution(id: def.id, value: value, weight: weight);
      score += entry.contribution;
      entries.add(entry);
    }
    return ProfileScore(
      profileId: profile.id,
      score: score,
      entries: List.unmodifiable(entries),
      factsFingerprint: vector.factsFingerprint,
    );
  }
}
