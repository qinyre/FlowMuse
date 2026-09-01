import '../gateways/smart_layout_editor_gateway.dart';
import '../patch/smart_layout_scene_patch.dart';
import '../patch/smart_layout_patch_validator.dart';
import '../reducer/smart_layout_scene_reducer.dart';
import '../snapshot/scene_revision.dart';
import '../validation/reduced_scene_metrics_extractor.dart';
import '../validation/validated_candidate.dart';

/// 唯一 commit 入口的稳定拒绝码。
enum CommitRejectionKind {
  /// 编辑器已释放。
  editorDisposed,

  /// patch 与当前 Scene 不再合法（悬空/版本错配/指纹断链）。
  patchInvalid,

  /// 写集相交：远端/本地改动触碰了 patch 写集，要求重新分析。
  writeSetConflict,

  /// 候选证据被篡改（渲染 digest 与快照不符）。
  provenanceBroken,

  /// 归约失败（理论不可达——候选已带归约产物；防御性收口）。
  reduceFailed,
}

/// 提交事务结果（sealed）：成功携带归约产物与新基线；拒绝携带稳定码
/// 与明细——拒绝时 Scene/History/广播零副作用。
sealed class HistoryCommitResult {
  const HistoryCommitResult();
}

class HistoryCommitted extends HistoryCommitResult {
  const HistoryCommitted({required this.reduced, required this.baseRevision})
    : redispatched = false;

  const HistoryCommitted.redispatched({
    required this.reduced,
    required this.baseRevision,
  }) : redispatched = true;

  /// 已落地的归约产物（与预览同一条 reducer 路径——preview=commit）。
  final ReducedScene reduced;

  /// 实际提交基线（重派时为重派后的当前 revision）。
  final SceneRevision baseRevision;

  /// 是否经一次重派（不相交写集、基于新 revision）。
  final bool redispatched;
}

class HistoryCommitRejected extends HistoryCommitResult {
  const HistoryCommitRejected({required this.kind, required this.detail});

  final CommitRejectionKind kind;
  final String detail;

  @override
  String toString() => 'HistoryCommitRejected(${kind.name}, $detail)';
}

/// compare-and-commit 事务（V3-502A）：同一临界区内复核
/// revision/fingerprint/ledger/render-metrics hash，处理写集相交与
/// 最多一次重派，提交走既有 [SmartLayoutEditorGateway.commitValidated]
///（pushHistory + applyResult——现有 History/协作通道，协议零改动）。
///
/// - 原始 [SmartLayoutScenePatch] 在类型层不可提交：唯一入口只接受
///   [ValidatedCandidate]（封装层已强制本轮完整门禁）；
/// - 冲突（写集相交/patch 失效/证据断链）零 Scene/History/广播副作用；
/// - 不相交远端变化基于新 revision 重派恰好一次（同一候选同一次
///   提交至多重派一次；再冲突即拒绝重新分析）。
class ValidatedCandidateCommitGateway {
  ValidatedCandidateCommitGateway({
    required SmartLayoutEditorGateway editor,
    required SceneRevisionTracker revisions,
  }) : _editor = editor,
       _revisions = revisions;

  final SmartLayoutEditorGateway _editor;
  final SceneRevisionTracker _revisions;

  /// 唯一提交入口（同步临界区：复核与提交之间无 await）。
  HistoryCommitResult commit(ValidatedCandidate candidate) {
    if (_editor.isDisposed) {
      return const HistoryCommitRejected(
        kind: CommitRejectionKind.editorDisposed,
        detail: 'editor disposed',
      );
    }
    // 证据完整性：渲染 digest 与候选快照重算一致（防装配后篡改）。
    if (reducedSceneDigestOf(candidate.snapshot) !=
        candidate.metrics.renderedSceneDigest) {
      return const HistoryCommitRejected(
        kind: CommitRejectionKind.provenanceBroken,
        detail: 'render digest mismatch',
      );
    }
    final current = _revisions.isDisposed ? null : _revisions.current;
    if (current == null) {
      return const HistoryCommitRejected(
        kind: CommitRejectionKind.editorDisposed,
        detail: 'revision tracker disposed',
      );
    }
    final scene = _editor.currentScene;

    if (current.fingerprint == candidate.patch.baseRevision.fingerprint) {
      // ---- 基线未变：直接提交（先全量复核 patch 合法性）----
      final violations = SmartLayoutScenePatchValidator.validate(
        patch: candidate.patch,
        baseScene: scene,
      );
      if (violations.isNotEmpty) {
        return HistoryCommitRejected(
          kind: CommitRejectionKind.patchInvalid,
          detail: violations.map((v) => v.kind.name).join(','),
        );
      }
      final ledgerViolations =
          SmartLayoutScenePatchValidator.checkLedgerConservation(
            patch: candidate.patch,
          );
      if (ledgerViolations.isNotEmpty) {
        return HistoryCommitRejected(
          kind: CommitRejectionKind.patchInvalid,
          detail:
              'ledger:${ledgerViolations.map((v) => v.kind.name).join(',')}',
        );
      }
      return _applyCommit(candidate.reduced, current, redispatched: false);
    }

    // ---- 基线已变：写集判定 + 最多一次重派 ----
    final rebased = SmartLayoutScenePatch(
      baseRevision: current,
      removes: candidate.patch.removes,
      updates: candidate.patch.updates,
      adds: candidate.patch.adds,
      fileAdds: candidate.patch.fileAdds,
      documentOp: candidate.patch.documentOp,
      selectionIntent: candidate.patch.selectionIntent,
      sourceCoverage: candidate.patch.sourceCoverage,
    );
    final violations = SmartLayoutScenePatchValidator.validate(
      patch: rebased,
      baseScene: scene,
    );
    if (violations.isNotEmpty) {
      // 重派复核失败 = 远端改动与写集相交（或等效失效）→ 重新分析。
      return HistoryCommitRejected(
        kind: CommitRejectionKind.writeSetConflict,
        detail: violations.map((v) => v.kind.name).join(','),
      );
    }
    final outcome = SmartLayoutSceneReducer.apply(base: scene, patch: rebased);
    if (outcome is SceneReduceFailure) {
      return HistoryCommitRejected(
        kind: CommitRejectionKind.reduceFailed,
        detail: '${outcome.kind.name}:${outcome.subjectId}',
      );
    }
    return _applyCommit(outcome as ReducedScene, current, redispatched: true);
  }

  /// 既有通道提交（pushHistory + applyResult）；preview=commit 由
  /// reduced.commitResult 与预览共用同一归约保证。
  HistoryCommitResult _applyCommit(
    ReducedScene reduced,
    SceneRevision baseRevision, {
    required bool redispatched,
  }) {
    _editor.commitValidated(reduced.commitResult);
    return redispatched
        ? HistoryCommitted.redispatched(
            reduced: reduced,
            baseRevision: baseRevision,
          )
        : HistoryCommitted(reduced: reduced, baseRevision: baseRevision);
  }
}
