import '../correction/correction_patch_applier.dart' show AffectedSourceSet;
import 'validated_candidate.dart';

/// 纠错重跑计划：影响集 + 旧候选全失效（轮次语义）+ 重跑范围。
class CorrectionRerunPlan {
  const CorrectionRerunPlan({
    required this.affectedSourceIds,
    required this.invalidatedCandidateIds,
    required this.assetKeys,
    required this.cropKeys,
  });

  /// 受影响笔迹源 id（重跑 scope：planner→patch→render→gate→score
  /// 以此为键只重算受影响部分；不受影响源沿用缓存事实）。
  final Set<String> affectedSourceIds;

  /// 本轮全部旧候选 id：纠错后旧验证结果一律失效（V3-505 再入）。
  final List<String> invalidatedCandidateIds;

  /// 受影响渲染资产/crop 键（资产重解码与裁剪事实刷新范围）。
  final Set<String> assetKeys;
  final Set<String> cropKeys;
}

/// 纠错重跑结果：新验证候选（经同一完整门禁流水线产出）+ 失效清单。
class CorrectionRerunResult {
  const CorrectionRerunResult({
    required this.plan,
    required this.newCandidates,
  });

  final CorrectionRerunPlan plan;
  final List<ValidatedCandidate> newCandidates;
}

/// CorrectionRerunCoordinator（V3-504B）：纠错 → 影响集（V3-205A
/// AffectedSourceSet）→ 旧候选全失效 → 以受影响源为 scope 重跑
/// planner→patch→render→gate→score 全链。
///
/// 局部与全量等价：重跑链由调用方注入（[chain]），其实现以
/// affectedSourceIds 为键消费缓存事实与重算事实——语义层"局部重算
/// 与全量等价"已在 V3-205A 证明，本协调器保证：scope 传递确定、
/// 旧候选零幸存、双跑确定。
class CorrectionRerunCoordinator {
  CorrectionRerunCoordinator({
    required Future<List<ValidatedCandidate>> Function(
      Set<String> affectedSourceIds,
    )
    chain,
  }) : _chain = chain;

  final Future<List<ValidatedCandidate>> Function(Set<String> affectedSourceIds)
  _chain;

  /// 对一次纠错执行重跑。
  ///
  /// [previousCandidates]：本轮既有验证候选——全部失效并在结果前
  /// 释放其渲染资源（旧候选不得再被提交/预览引用）。
  Future<CorrectionRerunResult> rerun({
    required List<ValidatedCandidate> previousCandidates,
    required AffectedSourceSet affected,
  }) async {
    final plan = CorrectionRerunPlan(
      affectedSourceIds: Set.unmodifiable(affected.strokeSourceIds),
      invalidatedCandidateIds: [
        for (final candidate in previousCandidates) candidate.candidateId,
      ]..sort(),
      assetKeys: Set.unmodifiable(affected.renderAssetKeys),
      cropKeys: Set.unmodifiable(affected.cropKeys),
    );
    // 先失效旧候选（资源释放），再重跑——期间无双重有效窗口。
    for (final candidate in previousCandidates) {
      candidate.dispose();
    }
    final newCandidates = await _chain(plan.affectedSourceIds);
    return CorrectionRerunResult(plan: plan, newCandidates: newCandidates);
  }
}
