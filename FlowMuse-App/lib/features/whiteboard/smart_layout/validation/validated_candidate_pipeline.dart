import 'dart:ui' show Offset, Size;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../metrics/anti_gaming_veto.dart';
import '../metrics/layout_metric_calculator.dart';
import '../metrics/layout_metric_contract.dart';
import '../metrics/layout_profile.dart';
import '../metrics/scene_metrics_contract.dart';
import '../patch/smart_layout_scene_patch.dart';
import '../reducer/smart_layout_scene_reducer.dart';
import '../rendering/draft_scene_renderer.dart';
import 'hard_constraint_validator.dart';
import 'layout_scorer.dart';
import 'reduced_scene_metrics_extractor.dart';
import 'validated_candidate.dart';

/// 一条候选的完整门禁输入：patch + 多样性键 + 软指标事实 + 否决结论
///（均由候选链从真实产物构造；本层不读 placement 自报）。
class CandidateGateInput {
  const CandidateGateInput({
    required this.candidateId,
    required this.diversityKey,
    required this.patch,
    required this.metricInput,
    required this.veto,
  });

  final String candidateId;
  final String diversityKey;
  final SmartLayoutScenePatch patch;

  /// 软指标计算事实（V3-404A LayoutMetricInput，真实放置盒）。
  final LayoutMetricInput metricInput;

  /// 反投机否决结论（V3-404A 检测器以真实 placement 事实产出）。
  final VetoVerdict veto;
}

/// 本轮完整门禁结果：Top3（不足 3 不补）+ 全部淘汰记录；只有全链
/// 通过的候选成为 [ValidatedCandidate]（封装层再复核）。
class GateRoundResult {
  const GateRoundResult({required this.top, required this.rejections});

  /// 已封装的验证候选（与 Top3 排名同序；渲染快照归候选所有，
  /// 候选废弃时 dispose）。
  final List<ValidatedCandidate> top;
  final List<CandidateRejection> rejections;

  bool get hasCandidates => top.isNotEmpty;

  InfeasibleExplanation? get infeasibleExplanation =>
      hasCandidates ? null : InfeasibleExplanation(rejections: rejections);
}

/// 验证候选流水线（V3-504B）：对每条候选跑 reducer→renderer→
/// metrics 提取→硬门禁→（通过者）软指标→profile 评分→多样性 Top3，
/// 全链通过者经 [ValidatedCandidate.assemble] 唯一入口封装。
///
/// fail closed：硬门禁失败、指标被拒（NaN/缺指标在计算器/向量构造
/// 层拒绝）、provenance 断链都进入淘汰记录；无候选存活时产出无解
/// 解释（不伪装成功）。被 Top3 淘汰的存活候选立即释放渲染资源。
abstract final class ValidatedCandidatePipeline {
  static Future<GateRoundResult> run({
    required Scene baseScene,
    required Bounds pageContentBounds,
    required List<CandidateGateInput> candidates,
    required LayoutProfile profile,
    Map<String, Size> imageIntrinsicSizes = const {},
  }) async {
    final rejections = <CandidateRejection>[];
    final renderer = DraftSceneRenderer();
    final survived =
        <
          (
            ScoreCandidateFacts,
            SmartLayoutScenePatch,
            ReducedScene,
            DraftRenderSnapshot,
            SceneMetricsSnapshot,
          )
        >[];
    try {
      for (final input in candidates) {
        final outcome = SmartLayoutSceneReducer.apply(
          base: baseScene,
          patch: input.patch,
        );
        // ---- reducer（失败原子）----
        if (outcome is SceneReduceFailure) {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: ['reduce:${outcome.kind.name}'],
              detail: outcome.subjectId,
            ),
          );
          continue;
        }
        final reduced = outcome as ReducedScene;

        // ---- renderer（真实绘制）----
        DraftRenderSnapshot snapshot;
        try {
          snapshot = await renderer.render(
            scene: reduced.scene,
            viewport: ViewportState(
              offset: Offset(
                pageContentBounds.origin.x,
                pageContentBounds.origin.y,
              ),
              zoom: 1,
            ),
            pixelSize: Size(
              pageContentBounds.size.width,
              pageContentBounds.size.height,
            ),
          );
        } on DraftRenderCancelled {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: const ['render:cancelled'],
              detail: '',
            ),
          );
          continue;
        }

        // ---- metrics 提取 + 硬门禁 ----
        SceneMetricsSnapshot metrics;
        try {
          metrics = SceneMetricsContract().build(
            ReducedSceneMetricsExtractor.extract(
              reduced: reduced,
              snapshot: snapshot,
              ledger: input.patch.sourceCoverage,
              pageContentBounds: pageContentBounds,
            ),
          );
        } on StateError catch (error) {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: const ['metrics:rejected'],
              detail: error.message,
            ),
          );
          snapshot.dispose();
          continue;
        }
        final hardReport = HardConstraintValidator.validate(
          baseScene: baseScene,
          reduced: reduced,
          snapshot: snapshot,
          metrics: metrics,
          ledger: input.patch.sourceCoverage,
          pageContentBounds: pageContentBounds,
          imageIntrinsicSizes: imageIntrinsicSizes,
        );
        if (!hardReport.passed) {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: [
                for (final v in hardReport.violations) 'hard:${v.kind.name}',
              ],
              detail: hardReport.violations.first.subjectIds.join(','),
            ),
          );
          snapshot.dispose();
          continue;
        }

        // ---- 软指标（NaN/缺指标在计算器/向量构造层 fail closed）----
        final vectorOutcome = const LayoutMetricCalculator().calculate(
          input.metricInput,
        );
        if (vectorOutcome is MetricsHardRejected) {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: const ['metrics:hard-rejected'],
              detail: 'violations=${vectorOutcome.hardViolationCount}',
            ),
          );
          snapshot.dispose();
          continue;
        }
        final vector = vectorOutcome as LayoutMetricVector;
        if (input.veto.vetoed) {
          rejections.add(
            CandidateRejection(
              candidateId: input.candidateId,
              reasonCodes: [for (final k in input.veto.kinds) k.name],
              detail: input.veto.reasons.join(';'),
            ),
          );
          snapshot.dispose();
          continue;
        }
        survived.add((
          ScoreCandidateFacts(
            candidateId: input.candidateId,
            diversityKey: input.diversityKey,
            vector: vector,
            veto: input.veto,
          ),
          input.patch,
          reduced,
          snapshot,
          metrics,
        ));
      }
    } finally {
      renderer.dispose();
    }

    if (survived.isEmpty) {
      return GateRoundResult(top: const [], rejections: rejections);
    }

    final top3 = LayoutScorer.rank(
      candidates: [for (final s in survived) s.$1],
      profile: profile,
    );
    final partsById = {
      for (final entry in survived) entry.$1.candidateId: entry,
    };
    final top = <ValidatedCandidate>[];
    for (final ranked in top3.ranked) {
      final parts = partsById[ranked.facts.candidateId]!;
      // 唯一封装入口：本轮硬门禁已过 + 指标齐全 + provenance 一致
      //（assemble 再复核，失败即抛——不允许半成品）。
      top.add(
        ValidatedCandidate.assemble(
          candidateId: ranked.facts.candidateId,
          diversityKey: ranked.facts.diversityKey,
          patch: parts.$2,
          reduced: parts.$3,
          snapshot: parts.$4,
          metrics: parts.$5,
          vector: ranked.facts.vector,
          score: ranked.score,
          hardReport: const HardConstraintReport(violations: []),
        ),
      );
    }
    // 未入选 Top3 的存活候选：释放渲染资源（不足 3 不补，凑数禁止）。
    final selectedIds = top.map((c) => c.candidateId).toSet();
    for (final entry in partsById.entries) {
      if (!selectedIds.contains(entry.key)) {
        entry.value.$4.dispose();
      }
    }
    return GateRoundResult(
      top: List.unmodifiable(top),
      rejections: [...rejections, ...top3.rejections],
    );
  }
}
