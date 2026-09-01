import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../patch/smart_layout_scene_patch.dart';

/// 归约失败稳定码。
enum SceneReduceFailureKind {
  /// remove 目标在 base 中不存在（base 已变化——重放冲突）。
  removeTargetMissing,

  /// update 目标在 base 中不存在。
  updateTargetMissing,

  /// add 的 id 与 base 现存元素冲突。
  addTargetConflicts,
}

sealed class SmartLayoutSceneReduceOutcome {
  const SmartLayoutSceneReduceOutcome();
}

/// 归约失败：整体失败、零部分结果（输入 Scene 不可变，天然无副作用）。
class SceneReduceFailure extends SmartLayoutSceneReduceOutcome {
  const SceneReduceFailure({required this.kind, required this.subjectId});

  final SceneReduceFailureKind kind;
  final String subjectId;

  @override
  String toString() => 'SceneReduceFailure(${kind.name}, $subjectId)';
}

/// 归约成功：携带确定性 Draft Scene 与可经既有
/// `gateway.commitValidated`（pushHistory + applyResult）落地的
/// [commitResult]——preview 与最终提交共用同一归约结果。
class ReducedScene extends SmartLayoutSceneReduceOutcome {
  const ReducedScene({
    required this.scene,
    required this.patch,
    required this.softDeletedIds,
    required this.updatedIds,
    required this.addedIds,
  });

  /// 确定性归约产物：patch 的 version/versionNonce 契约在此生效
  ///（upsert 语义，无编辑器随机 bump）。
  final Scene scene;

  final SmartLayoutScenePatch patch;
  final List<String> softDeletedIds;
  final List<String> updatedIds;
  final List<String> addedIds;

  /// 应用后的选择意图（patch.selectionIntent；null 表示不触碰选择）。
  Set<ElementId>? get selectionIds => patch.selectionIntent == null
      ? null
      : {for (final id in patch.selectionIntent!) ElementId(id)};

  /// 桥接既有 History 的唯一提交负载：单一 [CompoundResult]，一次
  /// applyResult 即一次 undo 事务（无重复 push）。
  ///
  /// 版本语义：add 元素原样落地（version=1、patch nonce）；update 元素
  /// 以 baseVersion 传入，编辑器 `updateElement` 的统一 bump 使最终
  /// version = baseVersion+1（与 patch 契约一致）；remove 走
  /// `RemoveElementResult`（软删，编辑器域 bump）。versionNonce 与
  /// updated 时间戳在提交域由编辑器生成——preview=commit 的等价口径
  /// 为元素负载排除 (versionNonce, updated) 的深度等价 + version 数字
  /// 一致（见 reducer 测试）。
  ToolResult get commitResult => CompoundResult([
    // 文件与文档先行（元素引用的资产先就位）。
    for (final op in patch.fileAdds)
      AddFileResult(fileId: op.fileId, file: op.file),
    if (patch.documentOp != null)
      SetSmartLayoutResult(patch.documentOp!.document),
    // 固定操作序：remove → update → add。
    for (final op in patch.removes)
      RemoveElementResult(ElementId(op.elementId)),
    for (final op in patch.updates)
      UpdateElementResult(op.element.copyWith(version: op.baseVersion)),
    for (final op in patch.adds) AddElementResult(op.element),
    if (patch.selectionIntent != null)
      SetSelectionResult({
        for (final id in patch.selectionIntent!) ElementId(id),
      }),
  ]);

  @override
  String toString() =>
      'ReducedScene(-${softDeletedIds.length} ~${updatedIds.length} '
      '+${addedIds.length})';
}

/// 纯 SceneReducer（V3-501A）：以固定操作序把不可变
/// [SmartLayoutScenePatch] 折叠到 base Scene——
/// remove（软删，patch 版本契约）→ update（原样替换）→ add（追加置顶）
/// → file → document；selection 意图暴露给 bridge，不进 Scene。
///
/// - 输入不可变：base/patch 全程只读，产物是全新 Scene；
/// - 失败原子：任何目标失配在产出前整体失败，无部分结果；
/// - Draft 可重放：同一 patch 可应用到写集完好的新 base（远端无关
///   变更后），冲突由目标失配显式失败；
/// - 不新增 History 框架：提交只产出 [ReducedScene.commitResult]，
///   经既有 gateway/applyResult 落地。
abstract final class SmartLayoutSceneReducer {
  static SmartLayoutSceneReduceOutcome apply({
    required Scene base,
    required SmartLayoutScenePatch patch,
  }) {
    // ---- 预检（全有或全无；目标失配即整体失败）----
    final baseById = <String, Element>{
      for (final element in base.elements) element.id.value: element,
    };
    for (final op in patch.removes) {
      final target = baseById[op.elementId];
      if (target == null || target.isDeleted) {
        return SceneReduceFailure(
          kind: SceneReduceFailureKind.removeTargetMissing,
          subjectId: op.elementId,
        );
      }
    }
    for (final op in patch.updates) {
      final target = baseById[op.elementId];
      if (target == null || target.isDeleted) {
        return SceneReduceFailure(
          kind: SceneReduceFailureKind.updateTargetMissing,
          subjectId: op.elementId,
        );
      }
    }
    for (final op in patch.adds) {
      if (baseById.containsKey(op.elementId)) {
        return SceneReduceFailure(
          kind: SceneReduceFailureKind.addTargetConflicts,
          subjectId: op.elementId,
        );
      }
    }

    // ---- 固定序折叠 ----
    var scene = base;
    // remove：软删，版本/nonce 按 patch 契约（upsert 不额外 bump）。
    scene = scene.upsertRemoteElements([
      for (final op in patch.removes)
        baseById[op.elementId]!.copyWith(
          isDeleted: true,
          version: op.newVersion,
          versionNonce: op.versionNonce,
        ),
    ]);
    // update：完整新负载原样替换。
    scene = scene.upsertRemoteElements([
      for (final op in patch.updates) op.element,
    ]);
    // add：追加置顶（patch 规范序）。
    for (final op in patch.adds) {
      scene = scene.addElement(op.element);
    }
    // file。
    for (final op in patch.fileAdds) {
      scene = scene.addFile(op.fileId, op.file);
    }
    // document。
    if (patch.documentOp != null) {
      scene = scene.withSmartLayout(patch.documentOp!.document);
    }

    return ReducedScene(
      scene: scene,
      patch: patch,
      softDeletedIds: [for (final op in patch.removes) op.elementId],
      updatedIds: [for (final op in patch.updates) op.elementId],
      addedIds: [for (final op in patch.adds) op.elementId],
    );
  }
}
