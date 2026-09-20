import 'dart:convert';
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
import '../snapshot/deterministic_hash.dart';
import '../snapshot/source_coverage_ledger.dart';
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
    this.validationElementIds,
    this.outputElementIdsByBlock,
    this.semanticContextKey,
    this.relations = const [],
    this.readingOrder,
  });

  final String candidateId;
  final String diversityKey;
  final SmartLayoutScenePatch patch;

  /// 软指标计算事实（V3-404A LayoutMetricInput，真实放置盒）。
  final LayoutMetricInput metricInput;

  /// 反投机否决结论（V3-404A 检测器以真实 placement 事实产出）。
  final VetoVerdict veto;

  /// 本轮改写范围；其他页及原样保留元素的旧缺陷不冒充本轮失败。
  final Set<String>? validationElementIds;
  final Map<String, List<String>>? outputElementIdsByBlock;
  final String? semanticContextKey;
  final List<SemanticRelationExpectation> relations;
  final ReadingOrderExpectation? readingOrder;

  String? get expectationDigest => semanticContextKey == null
      ? null
      : fingerprint64(
          jsonEncode([
            semanticContextKey,
            outputElementIdsByBlock,
            for (final r in relations)
              [
                r.relationId,
                r.kind.name,
                r.anchorId,
                r.followerId,
                r.maxGap,
                r.memberIds.toList()..sort(),
              ],
            readingOrder?.orderedElementIds,
            readingOrder?.columnByNode,
            for (final b in readingOrder?.columns ?? const <Bounds>[])
              [b.left, b.top, b.size.width, b.size.height],
          ]),
        );
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
          _validateMaterializedContent(input, baseScene, reduced, snapshot);
          metrics = SceneMetricsContract().build(
            ReducedSceneMetricsExtractor.extract(
              reduced: reduced,
              snapshot: snapshot,
              ledger: input.patch.sourceCoverage,
              pageContentBounds: pageContentBounds,
              validationElementIds: input.validationElementIds,
              relations: input.relations,
              readingOrder: input.readingOrder,
              outputElementIdsByBlock:
                  input.outputElementIdsByBlock ?? const {},
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
          validationElementIds: input.validationElementIds,
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
          expectationDigest: candidates
              .singleWhere((c) => c.candidateId == ranked.facts.candidateId)
              .expectationDigest,
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

  /// 只读语义内容和真实输出，不把“旧笔迹已删除”当成替代文字存在的证据。
  static void _validateMaterializedContent(
    CandidateGateInput input,
    Scene base,
    ReducedScene reduced,
    DraftRenderSnapshot snapshot,
  ) {
    final mapping = input.outputElementIdsByBlock;
    if (mapping == null && input.semanticContextKey == null) return;
    if (mapping == null || input.semanticContextKey?.isNotEmpty != true) {
      throw StateError('content-expectation-missing');
    }
    final assembly = input.metricInput.assembly;
    if (!assembly.ledgerConserved ||
        mapping.length != assembly.blocks.length ||
        !mapping.keys.toSet().containsAll(assembly.blocks.map((b) => b.id))) {
      throw StateError('block-output-map-incomplete');
    }
    if (input.relations.length != assembly.relationships.length ||
        input.relations.map((r) => r.relationId).toSet().length !=
            input.relations.length) {
      throw StateError('relation-expectation-incomplete');
    }
    for (final relation in assembly.relationships) {
      final id =
          '${relation.kind.name}:${relation.fromBlockId}:${relation.toBlockId}';
      final matches = input.relations.where((r) => r.relationId == id);
      if (matches.length != 1) {
        throw StateError('relation-expectation-mismatch');
      }
      final expected = matches.single;
      final endpoints = {expected.anchorId, expected.followerId};
      if (expected.kind.name != relation.kind.name ||
          endpoints.length != 2 ||
          !endpoints.containsAll([relation.fromBlockId, relation.toBlockId]) ||
          expected.maxGap == null ||
          !expected.maxGap!.isFinite ||
          expected.maxGap! < 0) {
        throw StateError('relation-expectation-mismatch');
      }
    }
    final expectedOrder = assembly.blocks
        .where((b) => !b.isPreservedLike)
        .map((b) => b.id)
        .toList();
    if (jsonEncode(input.readingOrder?.orderedElementIds) !=
        jsonEncode(expectedOrder)) {
      throw StateError('reading-order-expectation-incomplete');
    }
    final actual = {
      for (final e in reduced.scene.activeElements) e.id.value: e,
    };
    final original = {for (final e in base.activeElements) e.id.value: e};
    final rendered = {for (final l in snapshot.layers) l.elementId: l};
    final removed = input.patch.removes.map((o) => o.elementId).toSet();
    final written = input.patch.writeSet.elementIds.toSet();
    final changedLive = {
      ...input.patch.adds.map((o) => o.elementId),
      ...input.patch.updates.map((o) => o.elementId),
    };
    if (input.validationElementIds != null &&
        !input.validationElementIds!.containsAll(changedLive)) {
      throw StateError('validation-scope-excludes-output');
    }
    final seenSources = <String>{};
    final seenOutputs = <String>{};
    final ownerByOutput = <String, String>{};
    for (final block in assembly.blocks) {
      final outputs = mapping[block.id]!;
      if (outputs.isEmpty ||
          outputs.any(
            (id) => !seenOutputs.add(id) || !actual.containsKey(id),
          )) {
        throw StateError('output-missing-or-duplicated');
      }
      for (final id in block.sourceRefs) {
        final expected = block.isPreservedLike
            ? SourceCoverageStatus.preserved
            : SourceCoverageStatus.consumed;
        if (!seenSources.add(id) ||
            input.patch.sourceCoverage.statuses[id] != expected ||
            (!removed.contains(id) && !outputs.contains(id))) {
          throw StateError('output-source-state-mismatch');
        }
        if (block.isPreservedLike && written.contains(id)) {
          throw StateError('preserved-output-modified');
        }
        if (!original.containsKey(id) ||
            (removed.contains(id) &&
                (original[id] is! FreedrawElement ||
                    block.text == null ||
                    outputs.length != 1 ||
                    original.containsKey(outputs.single)))) {
          throw StateError('source-replacement-invalid');
        }
      }
      for (final id in outputs) {
        ownerByOutput[id] = block.id;
        if (!block.sourceRefs.contains(id) &&
            !input.patch.adds.any((a) => a.elementId == id)) {
          throw StateError('output-source-mismatch');
        }
      }
      if (block.isPreservedLike) continue;
      final spec = block.text;
      if (spec != null &&
          (outputs.length != 1 ||
              actual[outputs.single] is! TextElement ||
              (actual[outputs.single] as TextElement).text != spec.text)) {
        throw StateError('output-text-mismatch');
      }
      for (final id in outputs) {
        final e = actual[id]!;
        final layer = rendered[id];
        if (layer == null ||
            e.opacity <= 0 ||
            layer.bounds.size.width <= 0 ||
            layer.bounds.size.height <= 0 ||
            layer.resourceStatus == DraftResourceStatus.missing) {
          throw StateError('output-not-visible');
        }
        final before = original[id];
        if (e is TextElement &&
            before is TextElement &&
            e.text != before.text) {
          throw StateError('native-text-changed');
        }
        if (before is ImageElement &&
            (e is! ImageElement ||
                e.fileId != before.fileId ||
                e.crop != before.crop ||
                (e.width / e.height - before.width / before.height).abs() >
                    0.02 * before.width / before.height)) {
          throw StateError('image-content-changed');
        }
      }
    }
    if (seenSources.length != input.patch.sourceCoverage.sourceCount ||
        !seenSources.containsAll(input.patch.sourceCoverage.statuses.keys) ||
        !seenOutputs.containsAll(changedLive)) {
      throw StateError('output-coverage-mismatch');
    }
    // 原生组合内部允许重叠；新输出不能覆盖别的块或原样保留的内容。
    final layers = snapshot.layers
        .where(
          (l) =>
              actual[l.elementId]?.isCanvasPage != true &&
              actual[l.elementId]?.isPdfBackground != true,
        )
        .toList();
    for (var i = 0; i < layers.length; i++) {
      for (var j = i + 1; j < layers.length; j++) {
        final a = layers[i];
        final b = layers[j];
        if (!changedLive.contains(a.elementId) &&
            !changedLive.contains(b.elementId)) {
          continue;
        }
        final owner = ownerByOutput[a.elementId];
        if (owner != null && owner == ownerByOutput[b.elementId]) continue;
        final x = a.bounds;
        final y = b.bounds;
        if (x.left < y.right - 0.5 &&
            y.left < x.right - 0.5 &&
            x.top < y.bottom - 0.5 &&
            y.top < x.bottom - 0.5) {
          throw StateError('output-overlap:${a.elementId}:${b.elementId}');
        }
      }
    }
  }
}
