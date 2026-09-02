import '../metrics/layout_metric_contract.dart';
import '../metrics/anti_gaming_veto.dart';
import '../metrics/layout_profile.dart';

/// 候选评分输入（硬门禁已过、指标向量已建）。
class ScoreCandidateFacts {
  const ScoreCandidateFacts({
    required this.candidateId,
    required this.diversityKey,
    required this.vector,
    required this.veto,
  });

  final String candidateId;
  final String diversityKey;
  final LayoutMetricVector vector;

  /// 反投机否决结论（V3-404A 检测器以真实 placement 事实产出；
  /// 本层不重算、不读 placement）。
  final VetoVerdict veto;
}

/// 淘汰记录（稳定原因码：硬违规类别 / 反投机否决类别 / 指标缺失）。
class CandidateRejection {
  const CandidateRejection({
    required this.candidateId,
    required this.reasonCodes,
    required this.detail,
  });

  final String candidateId;
  final List<String> reasonCodes;
  final String detail;

  @override
  String toString() => '$candidateId: ${reasonCodes.join(',')}';
}

/// 无解解释：全部候选淘汰时的稳定汇总（不伪装成功）。
class InfeasibleExplanation {
  const InfeasibleExplanation({required this.rejections});

  final List<CandidateRejection> rejections;

  /// 稳定摘要码（按原因聚合并排序，供 UI 映射文案）。
  List<String> get aggregatedReasons {
    final counts = <String, int>{};
    for (final rejection in rejections) {
      for (final code in rejection.reasonCodes) {
        counts[code] = (counts[code] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );
    return [for (final e in entries) '${e.key}×${e.value}'];
  }
}

/// 排名条目（score 可还原分解经 [ProfileScore.entries]）。
class RankedCandidate {
  const RankedCandidate({
    required this.facts,
    required this.score,
    required this.rank,
  });

  final ScoreCandidateFacts facts;
  final ProfileScore score;
  final int rank;
}

/// Top3 结果：不足 3 不补（明确携带实际数量）；全部淘汰时为
/// [infeasible]。
class Top3Result {
  const Top3Result.top3({required this.ranked, required this.rejections})
    : infeasible = null;

  Top3Result.allRejected({required this.rejections})
    : ranked = const [],
      infeasible = InfeasibleExplanation(rejections: rejections);

  final List<RankedCandidate> ranked;
  final List<CandidateRejection> rejections;
  final InfeasibleExplanation? infeasible;

  bool get hasCandidates => ranked.isNotEmpty;
}

/// LayoutScorer（V3-504B）：profile 排序 + 反投机否决 + 多样性 Top3。
///
/// - 排序：[LayoutProfileScorer]（V3-404A，权重冻结、score 可还原）；
///   被反投机否决的候选进入淘汰记录，不进排名；
/// - 多样性：Top3 按 diversityKey 互异选取（分高优先）；同一结构只剩
///   最高分代表；**不足 3 不补**——凑数被禁止；
/// - 确定性：并列按 candidateId 字典序破平。
abstract final class LayoutScorer {
  static const int topCount = 3;

  static Top3Result rank({
    required List<ScoreCandidateFacts> candidates,
    required LayoutProfile profile,
  }) {
    final scorer = const LayoutProfileScorer();
    final rejections = <CandidateRejection>[];
    final scored = <(ScoreCandidateFacts, ProfileScore)>[];
    for (final facts in candidates) {
      final outcome = scorer.rank(profile, facts.vector, facts.veto);
      switch (outcome) {
        case ProfileScore():
          scored.add((facts, outcome));
        case ProfileGamingRejected(:final kinds, :final reasons):
          rejections.add(
            CandidateRejection(
              candidateId: facts.candidateId,
              reasonCodes: [for (final k in kinds) k.name],
              detail: reasons.join(';'),
            ),
          );
      }
    }
    if (scored.isEmpty) {
      return Top3Result.allRejected(rejections: rejections);
    }

    // 分降序 → id 字典序破平（确定性）。
    scored.sort((a, b) {
      final byScore = b.$2.score.compareTo(a.$2.score);
      if (byScore != 0) return byScore;
      return a.$1.candidateId.compareTo(b.$1.candidateId);
    });

    final ranked = <RankedCandidate>[];
    final seenKeys = <String>{};
    for (final (facts, score) in scored) {
      if (ranked.length >= topCount) break;
      if (!seenKeys.add(facts.diversityKey)) continue;
      ranked.add(
        RankedCandidate(facts: facts, score: score, rank: ranked.length + 1),
      );
    }
    return Top3Result.top3(ranked: ranked, rejections: rejections);
  }
}
