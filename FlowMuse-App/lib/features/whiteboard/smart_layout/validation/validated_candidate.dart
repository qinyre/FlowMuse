import '../metrics/layout_metric_contract.dart';
import '../metrics/layout_profile.dart';
import '../metrics/scene_metrics_contract.dart';
import '../patch/smart_layout_scene_patch.dart';
import '../reducer/smart_layout_scene_reducer.dart';
import '../rendering/draft_scene_renderer.dart';
import 'hard_constraint_validator.dart';

/// 本轮完整门禁产出的验证候选（V3-504B）：携带 patch、归约产物、渲染
/// 快照、真实 metrics、指标向量与 profile 得分——preview、commit 与
/// 协作投影的唯一合法来源（计划 §4.8）。
///
/// 封装不变量（唯一入口 [assemble] 强制）：
/// - 硬门禁 [HardConstraintReport.passed] 为真（失败候选在此前已分流
///   为拒绝记录，不可能进入本类型）；
/// - 指标向量齐全且有限（[LayoutMetricVector] 构造层拒 NaN/缺指标/
///   越界，assemble 复核并 fail closed）；
/// - provenance 三件套（revision/digest/fingerprint）来自同一轮真实
///   渲染（[SceneMetricsSnapshot] 构造校验 + digest 复核）。
class ValidatedCandidate {
  ValidatedCandidate._({
    required this.candidateId,
    required this.diversityKey,
    required this.patch,
    required this.reduced,
    required this.snapshot,
    required this.metrics,
    required this.vector,
    required this.score,
    required this.hardReport,
  });

  final String candidateId;

  /// 多样性键（结构代表；Top3 去重依据，调用方从候选结构推导）。
  final String diversityKey;
  final SmartLayoutScenePatch patch;
  final ReducedScene reduced;

  /// 渲染快照归候选所有：候选废弃时必须 [dispose]（图片资源）。
  final DraftRenderSnapshot snapshot;
  final SceneMetricsSnapshot metrics;
  final LayoutMetricVector vector;
  final ProfileScore score;
  final HardConstraintReport hardReport;

  /// 唯一工厂：只有本轮完整门禁全过才能构造——任何缺失/不一致
  /// 抛 [StateError]（fail closed，不返回部分结果）。
  static ValidatedCandidate assemble({
    required String candidateId,
    required String diversityKey,
    required SmartLayoutScenePatch patch,
    required ReducedScene reduced,
    required DraftRenderSnapshot snapshot,
    required SceneMetricsSnapshot metrics,
    required LayoutMetricVector vector,
    required ProfileScore score,
    required HardConstraintReport hardReport,
  }) {
    if (!hardReport.passed) {
      throw StateError(
        'ValidatedCandidate 拒绝：硬门禁未通过'
        '（${hardReport.violations.map((v) => v.kind.name).join(',')}）',
      );
    }
    for (final def in LayoutMetricContract.definitions) {
      final value = vector.values[def.id];
      if (value == null || value.isNaN || !value.isFinite) {
        throw StateError('ValidatedCandidate 拒绝：指标 ${def.id} 缺失或非有限');
      }
    }
    if (metrics.renderedSceneDigest.isEmpty ||
        metrics.rendererFingerprint.isEmpty ||
        metrics.sceneRevision != patch.baseRevision.revision) {
      throw StateError('ValidatedCandidate 拒绝：provenance 断链');
    }
    if (reduced.patch != patch) {
      throw StateError('ValidatedCandidate 拒绝：归约产物与 patch 不一致');
    }
    return ValidatedCandidate._(
      candidateId: candidateId,
      diversityKey: diversityKey,
      patch: patch,
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      vector: vector,
      score: score,
      hardReport: hardReport,
    );
  }

  /// 账本哈希（V3-502 commit 复核用）。
  String get ledgerHash => patch.sourceCoverage.hashValue;

  bool _disposed = false;

  /// 释放渲染快照资源；幂等。patch/reduced/metrics 纯数据不受影响。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    snapshot.dispose();
  }
}
