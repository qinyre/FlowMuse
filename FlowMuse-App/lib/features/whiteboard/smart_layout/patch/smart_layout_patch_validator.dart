import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../snapshot/source_coverage_ledger.dart';
import 'patch_invariant.dart';
import 'smart_layout_scene_patch.dart';

/// ledger 守恒违反类型。
enum PatchLedgerViolationKind {
  /// 账本未终结（仍有 pending 源）。
  ledgerNotFinalized,

  /// update/remove 触碰了账本之外的元素（账本必须覆盖本页全部源；
  /// 新增元素除外）。
  touchedOutsideLedger,

  /// 触碰的源在账本中是 preserved（原样保留的源不允许被 patch 修改）。
  touchedPreservedSource,
}

class PatchLedgerViolation {
  const PatchLedgerViolation({
    required this.kind,
    required this.subjectId,
    required this.detail,
  });

  final PatchLedgerViolationKind kind;

  /// 涉及的源 id；不适用时为 '-'。
  final String subjectId;

  final String detail;

  @override
  String toString() => '${kind.name}[$subjectId] $detail';
}

/// 已构建 patch 的独立复核入口（V3-502 commit 临界区与测试复用；
/// 不依赖 builder 内部状态）：
/// - [validate]：以 base Scene 重跑全部 [PatchInvariant]——校验的不是
///   "当时怎么构建的"，而是"此刻这对 (patch, base) 是否仍然合法"；
/// - [checkLedgerConservation]：唯一账本与 patch 副作用一致——账本已
///   终结，且被 update/remove 触碰的源必须 consumed（preserved 源
///   零触碰）；新增元素不是源，不参与账本校验。
abstract final class SmartLayoutScenePatchValidator {
  /// 重跑全部构建期不变量；空列表 = 通过。
  static List<PatchInvariantViolation> validate({
    required SmartLayoutScenePatch patch,
    required Scene baseScene,
  }) => PatchInvariant.check(
    baseScene: baseScene,
    baseRevision: patch.baseRevision,
    sourceCoverage: patch.sourceCoverage,
    removes: patch.removes,
    updates: patch.updates,
    adds: patch.adds,
    fileAdds: patch.fileAdds,
    documentOp: patch.documentOp,
    selectionIntent: patch.selectionIntent,
  );

  /// 账本守恒校验；空列表 = 通过。违反项按（类型序, subjectId, detail）
  /// 确定性排序。
  static List<PatchLedgerViolation> checkLedgerConservation({
    required SmartLayoutScenePatch patch,
  }) {
    final violations = <PatchLedgerViolation>[];
    final ledger = patch.sourceCoverage;

    if (!ledger.isFinalized) {
      violations.add(
        PatchLedgerViolation(
          kind: PatchLedgerViolationKind.ledgerNotFinalized,
          subjectId: '-',
          detail: '账本仍有 ${ledger.pendingCount} 个 pending 源',
        ),
      );
    }

    void checkTouched(String id, String opKind) {
      final status = ledger.statusOf(id);
      if (status == SourceCoverageStatus.pending) return; // 已由未终结上报
      if (status == SourceCoverageStatus.preserved) {
        violations.add(
          PatchLedgerViolation(
            kind: PatchLedgerViolationKind.touchedPreservedSource,
            subjectId: id,
            detail: '$opKind 触碰了 preserved 源',
          ),
        );
      }
    }

    for (final op in patch.updates) {
      if (!ledger.statuses.containsKey(op.elementId)) {
        violations.add(
          PatchLedgerViolation(
            kind: PatchLedgerViolationKind.touchedOutsideLedger,
            subjectId: op.elementId,
            detail: 'update 触碰账本外元素',
          ),
        );
        continue;
      }
      checkTouched(op.elementId, 'update');
    }
    for (final op in patch.removes) {
      if (!ledger.statuses.containsKey(op.elementId)) {
        violations.add(
          PatchLedgerViolation(
            kind: PatchLedgerViolationKind.touchedOutsideLedger,
            subjectId: op.elementId,
            detail: 'remove 触碰账本外元素',
          ),
        );
        continue;
      }
      checkTouched(op.elementId, 'remove');
    }

    violations.sort(
      (a, b) => a.kind.index.compareTo(b.kind.index) != 0
          ? a.kind.index.compareTo(b.kind.index)
          : a.subjectId.compareTo(b.subjectId) != 0
          ? a.subjectId.compareTo(b.subjectId)
          : a.detail.compareTo(b.detail),
    );
    return violations;
  }
}
