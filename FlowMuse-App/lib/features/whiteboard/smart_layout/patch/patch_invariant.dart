import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../snapshot/scene_fingerprint.dart';
import '../snapshot/scene_revision.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'smart_layout_scene_patch.dart';

/// 不变量违反类型。检查项固定、可枚举；顺序即报告序。
enum PatchInvariantViolationKind {
  /// 同一元素 id 出现在多个（或同型重复的）操作里。
  duplicateElementOp,

  /// add 的 id 在 base Scene 中已存在。
  addConflictsWithBase,

  /// add 的元素携带软删标记。
  addElementSoftDeleted,

  /// add 的元素 version != 1。
  addVersionNotOne,

  /// update 的 id 在 base Scene 中不存在。
  updateDangling,

  /// remove 的 id 在 base Scene 中不存在。
  removeDangling,

  /// update/remove 目标在 base 中已被软删（不属于活动内容）。
  opTargetsSoftDeleted,

  /// 操作声明的 baseVersion 与 base 元素实际 version 不符。
  baseVersionMismatch,

  /// update 元素 version != baseVersion + 1。
  updateVersionDelta,

  /// remove 的 newVersion != baseVersion + 1。
  removeVersionDelta,

  /// frameId/containerId/boundElements 引用无法在 base∪adds∖removes 中解析。
  relationDangling,

  /// remove 导致 base 中未被本 patch 处理的元素关系悬空（如删除容器但
  /// 绑定文本未被移除/改写）。
  reverseRelationDangling,

  /// 选择意图引用了应用后不存在的元素。
  selectionDangling,

  /// fileAdd 的 fileId 在 base 文件仓中已存在。
  fileAddConflictsWithBase,

  /// 同一 fileId 的 fileAdd 重复。
  duplicateFileAdd,

  /// baseRevision.fingerprint 与 base Scene 实际指纹不符（过期/错配）。
  baseRevisionFingerprintMismatch,

  /// 账本仍有 pending 源（patch 是终态事务对象，必须已终结）。
  ledgerNotFinalized,

  /// 零副作用 patch（写集为空）。
  emptyWriteSet,
}

class PatchInvariantViolation {
  const PatchInvariantViolation({
    required this.kind,
    required this.subjectId,
    required this.detail,
  });

  final PatchInvariantViolationKind kind;

  /// 涉及的元素/文件 id；不适用时为 '-'。
  final String subjectId;

  final String detail;

  @override
  String toString() => '${kind.name}[$subjectId] $detail';
}

/// ScenePatch 全部构建期不变量的单一权威（V3-500B validator 复用同一
/// 语义）。检查只依赖 base Scene 的只读投影与操作本身，不产生任何
/// 部分结果；违反项全量收集后按（类型序, subjectId, detail）排序，
/// 双跑报告逐字节一致。
abstract final class PatchInvariant {
  /// 校验一份待构建的 patch 操作集合；返回排序后的全部违反项
  /// （空列表 = 通过）。
  static List<PatchInvariantViolation> check({
    required Scene baseScene,
    required SceneRevision baseRevision,
    required SourceCoverageLedger sourceCoverage,
    required List<ScenePatchElementRemove> removes,
    required List<ScenePatchElementUpdate> updates,
    required List<ScenePatchElementAdd> adds,
    required List<ScenePatchFileAdd> fileAdds,
    required ScenePatchDocumentOp? documentOp,
    required List<String>? selectionIntent,
  }) {
    final violations = <PatchInvariantViolation>[];
    final baseById = <String, Element>{
      for (final element in baseScene.elements) element.id.value: element,
    };
    final baseFileIds = baseScene.files.keys.toSet();

    // 1. 元素操作唯一性：每个 id 至多一个操作。
    final opKindsById = <String, ScenePatchElementOpKind>{};
    void claimOp(String id, ScenePatchElementOpKind kind, String detail) {
      final existing = opKindsById[id];
      if (existing != null) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.duplicateElementOp,
            subjectId: id,
            detail: '已存在 $existing 操作，又注册 $kind（$detail）',
          ),
        );
        return;
      }
      opKindsById[id] = kind;
    }

    for (final op in removes) {
      claimOp(op.elementId, ScenePatchElementOpKind.remove, 'remove');
    }
    for (final op in updates) {
      claimOp(op.elementId, ScenePatchElementOpKind.update, 'update');
    }
    for (final op in adds) {
      claimOp(op.elementId, ScenePatchElementOpKind.add, 'add');
    }

    // 2. add：不与 base 冲突、非软删、version==1。
    for (final op in adds) {
      final element = op.element;
      if (baseById.containsKey(element.id.value)) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.addConflictsWithBase,
            subjectId: element.id.value,
            detail: 'base Scene 已存在同 id 元素',
          ),
        );
      }
      if (element.isDeleted) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.addElementSoftDeleted,
            subjectId: element.id.value,
            detail: '新增元素携带软删标记',
          ),
        );
      }
      if (element.version != 1) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.addVersionNotOne,
            subjectId: element.id.value,
            detail: '新增元素 version 必须为 1，实际 ${element.version}',
          ),
        );
      }
    }

    // 3. update：目标存在、未软删、baseVersion 匹配、version delta 正确。
    for (final op in updates) {
      final base = baseById[op.elementId];
      if (base == null) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.updateDangling,
            subjectId: op.elementId,
            detail: 'base Scene 不存在该元素',
          ),
        );
        continue;
      }
      if (base.isDeleted) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.opTargetsSoftDeleted,
            subjectId: op.elementId,
            detail: 'update 目标在 base 中已软删',
          ),
        );
      }
      if (op.baseVersion != base.version) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.baseVersionMismatch,
            subjectId: op.elementId,
            detail:
                '期望 baseVersion=${op.baseVersion}，'
                '实际 ${base.version}',
          ),
        );
      }
      if (op.element.version != op.baseVersion + 1) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.updateVersionDelta,
            subjectId: op.elementId,
            detail:
                '新 version=${op.element.version} 必须 = '
                'baseVersion+1=${op.baseVersion + 1}',
          ),
        );
      }
    }

    // 4. remove：目标存在、未软删、baseVersion 匹配、version delta 正确。
    for (final op in removes) {
      final base = baseById[op.elementId];
      if (base == null) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.removeDangling,
            subjectId: op.elementId,
            detail: 'base Scene 不存在该元素',
          ),
        );
        continue;
      }
      if (base.isDeleted) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.opTargetsSoftDeleted,
            subjectId: op.elementId,
            detail: 'remove 目标在 base 中已软删',
          ),
        );
      }
      if (op.baseVersion != base.version) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.baseVersionMismatch,
            subjectId: op.elementId,
            detail:
                '期望 baseVersion=${op.baseVersion}，'
                '实际 ${base.version}',
          ),
        );
      }
      if (op.newVersion != op.baseVersion + 1) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.removeVersionDelta,
            subjectId: op.elementId,
            detail:
                'newVersion=${op.newVersion} 必须 = '
                'baseVersion+1=${op.baseVersion + 1}',
          ),
        );
      }
    }

    // 5. 关系完整性：adds/updates 的关系引用必须在应用后仍存在
    //    （base ∪ adds ∖ removes）。
    final removedIds = {for (final op in removes) op.elementId};
    final addedIds = {for (final op in adds) op.elementId};
    bool resolvesAfterApply(String id) =>
        addedIds.contains(id) ||
        (baseById.containsKey(id) && !removedIds.contains(id));

    for (final op in adds) {
      _checkRelationRefs(op.element, resolvesAfterApply, violations);
    }
    for (final op in updates) {
      _checkRelationRefs(op.element, resolvesAfterApply, violations);
    }

    // 5b. 反向悬空：remove 之后，base 中既未移除也未改写的元素不得仍
    //     引用被删对象（改写元素的新负载已由 5 正向检查）。
    final updatedIds = {for (final op in updates) op.elementId};
    for (final removedId in removedIds) {
      for (final base in baseById.values) {
        if (base.isDeleted || removedIds.contains(base.id.value)) continue;
        if (updatedIds.contains(base.id.value)) continue;
        for (final ref in _refsOfElement(base)) {
          if (ref == removedId) {
            violations.add(
              PatchInvariantViolation(
                kind: PatchInvariantViolationKind.reverseRelationDangling,
                subjectId: base.id.value,
                detail: 'remove "$removedId" 后该未处理元素的关系悬空',
              ),
            );
          }
        }
      }
    }

    // 6. selection intent：引用必须在应用后存在。
    if (selectionIntent != null) {
      for (final id in selectionIntent) {
        if (!resolvesAfterApply(id)) {
          violations.add(
            PatchInvariantViolation(
              kind: PatchInvariantViolationKind.selectionDangling,
              subjectId: id,
              detail: '选择意图引用应用后不存在的元素',
            ),
          );
        }
      }
    }

    // 7. fileAdd：不与 base 冲突、不重复。
    final seenFileIds = <String>{};
    for (final op in fileAdds) {
      if (baseFileIds.contains(op.fileId)) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.fileAddConflictsWithBase,
            subjectId: op.fileId,
            detail: 'base 文件仓已存在同 id 文件',
          ),
        );
      }
      if (!seenFileIds.add(op.fileId)) {
        violations.add(
          PatchInvariantViolation(
            kind: PatchInvariantViolationKind.duplicateFileAdd,
            subjectId: op.fileId,
            detail: '同一 fileId 的 fileAdd 重复注册',
          ),
        );
      }
    }

    // 8. baseRevision 必须与 base Scene 实际指纹一致（过期/错配即冲突）。
    final actual = SceneFingerprint.of(baseScene);
    if (actual != baseRevision.fingerprint) {
      violations.add(
        PatchInvariantViolation(
          kind: PatchInvariantViolationKind.baseRevisionFingerprintMismatch,
          subjectId: '-',
          detail:
              'baseRevision.fingerprint=${baseRevision.fingerprint.value} '
              '!= baseScene 实际指纹 ${actual.value}',
        ),
      );
    }

    // 9. 账本必须已终结（全部 consumed/preserved）。
    if (!sourceCoverage.isFinalized) {
      violations.add(
        PatchInvariantViolation(
          kind: PatchInvariantViolationKind.ledgerNotFinalized,
          subjectId: '-',
          detail: '账本仍有 ${sourceCoverage.pendingCount} 个 pending 源',
        ),
      );
    }

    // 10. 写集非空：零副作用 patch 不是合法事务对象。
    final hasSideEffect =
        removes.isNotEmpty ||
        updates.isNotEmpty ||
        adds.isNotEmpty ||
        fileAdds.isNotEmpty ||
        documentOp != null ||
        selectionIntent != null;
    if (!hasSideEffect) {
      violations.add(
        const PatchInvariantViolation(
          kind: PatchInvariantViolationKind.emptyWriteSet,
          subjectId: '-',
          detail: 'patch 必须至少包含一个副作用',
        ),
      );
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

  static Iterable<String> _refsOfElement(Element element) =>
      SmartLayoutScenePatch.relationRefsOf(element);

  static void _checkRelationRefs(
    Element element,
    bool Function(String id) resolvesAfterApply,
    List<PatchInvariantViolation> violations,
  ) {
    void reject(String ref, String field) {
      violations.add(
        PatchInvariantViolation(
          kind: PatchInvariantViolationKind.relationDangling,
          subjectId: element.id.value,
          detail: '$field 引用 "$ref" 在应用后不存在',
        ),
      );
    }

    final frameId = element.frameId;
    if (frameId != null && !resolvesAfterApply(frameId)) {
      reject(frameId, 'frameId');
    }
    if (element is TextElement) {
      final containerId = element.containerId;
      if (containerId != null && !resolvesAfterApply(containerId)) {
        reject(containerId, 'containerId');
      }
    }
    for (final bound in element.boundElements) {
      if (!resolvesAfterApply(bound.id)) {
        reject(bound.id, 'boundElements');
      }
    }
  }
}
