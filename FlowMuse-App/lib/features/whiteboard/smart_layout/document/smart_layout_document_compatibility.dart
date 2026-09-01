import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';

import 'smart_layout_document_v3_mapper.dart';

/// SmartLayoutDocument 重开/undo/redo/reconcile 兼容语义（V3-601A，
/// 合并原 V3-601A~B）。
///
/// 全部复用既有机制，零新增框架：
/// - 重开：mapper 写回→读入深度一致（确定性默认保证双跑等价）；
/// - undo/redo：文档通道事务 = 真实 [SmartLayoutScenePatchBuilder]
///   documentOp + [SmartLayoutSceneReducer] 折叠；undo/redo = 历史回放
///   前一文档状态的同类事务（与 editor pushHistory 同粒度，本类不建
///   第二套 History）；
/// - reconcile：文档通道与元素通道隔离——远端元素经既有
///   [Scene.upsertRemoteElements] 合并不触碰 smartLayout；documentOp
///   是 patch 触碰文档通道的唯一入口（写集口径）。
abstract final class SmartLayoutDocumentCompatibility {
  /// 文档重开一致性：write→read→write 深度等价（经 mapper canonical
  /// 比较；确定性 generatedAt/块 id 默认是前提）。
  static bool reopenRoundTrip(SmartLayoutDocument document) {
    final first = SmartLayoutDocumentV3Mapper.readFromJson(
      SmartLayoutDocumentV3Mapper.writeJson(document),
    );
    final second = SmartLayoutDocumentV3Mapper.readFromJson(
      SmartLayoutDocumentV3Mapper.writeJson(first.document),
    );
    return SmartLayoutDocumentV3Mapper.deepEquals(
      first.document,
      second.document,
    );
  }

  /// 文档事务：replace（documentOp 唯一替换通道）经真实 builder+reducer
  /// 折叠到 Scene。undo/redo 即对前一/后一文档状态调用本方法。
  static Scene applyDocumentReplace({
    required Scene base,
    required SmartLayoutDocument document,
    required int revisionCount,
  }) =>
      _applyDocumentOp(
        base: base,
        revisionCount: revisionCount,
        build: (builder) =>
            builder.replaceSmartLayoutDocument(document),
      );

  /// 文档事务：clear（回到无文档状态，undo 回基线用）。
  static Scene applyDocumentClear({
    required Scene base,
    required int revisionCount,
  }) =>
      _applyDocumentOp(
        base: base,
        revisionCount: revisionCount,
        build: (builder) => builder.clearSmartLayoutDocument(),
      );

  /// reconcile 元素通道：远端元素合并经既有 upsert 通道，文档通道
  /// 原样保留（返回 Scene 的 smartLayout 与 local 逐字段一致）。
  static Scene mergeRemoteElements(
    Scene local,
    Iterable<Element> remoteElements,
  ) => local.upsertRemoteElements(remoteElements);

  /// patch 是否触碰文档通道：读自写集（V3-502 冲突判定的权威口径）。
  /// 元素/文件/选择操作不得隐式触碰 smartLayout——documentOp 存在且
  /// 仅其存在时为真。
  static bool patchTouchesDocumentChannel(SmartLayoutScenePatch patch) =>
      patch.writeSet.touchesDocument;

  static Scene _applyDocumentOp({
    required Scene base,
    required int revisionCount,
    required void Function(SmartLayoutScenePatchBuilder) build,
  }) {
    final builder = SmartLayoutScenePatchBuilder(
      baseScene: base,
      baseRevision: SceneRevision(
        epoch: 0,
        revision: revisionCount,
        fingerprint: SceneFingerprint.of(base),
      ),
      // 纯文档事务零源元素：空账本天然终结。
      sourceCoverage: SourceCoverageLedger.pending(const []),
    );
    build(builder);
    final patch = builder.build();
    return switch (SmartLayoutSceneReducer.apply(base: base, patch: patch)) {
      ReducedScene(:final scene) => scene,
      SceneReduceFailure() => throw StateError('文档事务折叠失败'),
    };
  }
}
