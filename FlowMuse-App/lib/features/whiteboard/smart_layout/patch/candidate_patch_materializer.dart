import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../geometry/affine_layout_transform.dart';
import '../geometry/smart_layout_scene_transformer.dart';
import '../geometry/smart_layout_transform_contract.dart';
import '../placement/flow_placer.dart';
import '../snapshot/deterministic_hash.dart';
import '../snapshot/scene_revision.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'smart_layout_scene_patch.dart';
import 'smart_layout_scene_patch_builder.dart';

/// 物化失败稳定原因（原子：任何失败都不产生 patch，base 零触碰）。
enum PatchMaterializationFailureKind {
  /// assembly 块 sourceRefs 守恒破坏（重复/与文档账目不符）。
  ledgerNotConserved,

  /// assembly 源集与传入账本源集不一致。
  ledgerSourceMismatch,

  /// 消费块缺少放置结果（placement 未覆盖该 blockId）。
  missingPlacement,

  /// 不支持的块类别（table 等 v1 未定义物化语义的类型）。
  unsupportedBlockKind,

  /// typed 块 sourceRefs 数量 ≠ 1 或源不是活动 TextElement。
  typedSourceInvalid,

  /// figure 块 sourceRefs 数量 ≠ 1 或源不是活动 ImageElement。
  figureSourceInvalid,

  /// sourceRef 在 base Scene 中不存在（或已软删）。
  sourceUnresolved,

  /// V3-303A 变换契约拒绝（锁定/背景/未知类型等，detail 携带原因）。
  transformRejected,

  /// 物化产出未通过 patch 不变量终审（内部契约破坏，整体失败）。
  patchInvariantRejected,
}

sealed class PatchMaterializationOutcome {
  const PatchMaterializationOutcome();
}

class PatchMaterializationSuccess extends PatchMaterializationOutcome {
  const PatchMaterializationSuccess({
    required this.patch,
    required this.consumedSourceIds,
    required this.preservedSourceIds,
    required this.addedElementIds,
    required this.transformedSourceIds,
  });

  final SmartLayoutScenePatch patch;
  final List<String> consumedSourceIds;
  final List<String> preservedSourceIds;

  /// 本 patch 新增的确定性元素 id（sl3- 前缀）。
  final List<String> addedElementIds;

  /// 经 V3-303A 变换改写的消费源 id（含闭包成员时以最终状态进入
  /// patch.updates，成员明细见 transformer 输出）。
  final List<String> transformedSourceIds;
}

class PatchMaterializationFailure extends PatchMaterializationOutcome {
  const PatchMaterializationFailure({
    required this.kind,
    required this.blockId,
    this.detail = '',
  });

  final PatchMaterializationFailureKind kind;

  /// 首个失败块（确定性：按 assembly 块序扫描）。
  final String blockId;
  final String detail;

  @override
  String toString() =>
      '${kind.name}($blockId${detail.isEmpty ? '' : ': $detail'})';
}

/// candidate → patch 一次物化器（V3-500B）：把完整的
///（assembly, placement）结果一次性物化为覆盖元素/关系/selection 的
/// [SmartLayoutScenePatch]——构建后不再推导坐标或关系：
/// - 坐标：放置盒（绝对页面坐标）即最终元素盒；typed/figure 源经
///   V3-303A 原子 Scene 变换（闭包成员、绑定箭头、容器文本统一重算）
///   一次性移到放置盒，fontSize 显式对齐 placed.appliedFontSize；
/// - 关系：新增文本不入组/不入 frame/无容器；既有关系经变换闭包保持；
/// - ledger：consumed/preserved 完全取自 assembly 文档账目（守恒复核
///   在 assembly 侧已做，此处复验集合一致后标记终结）；
/// - 不支持类型（table）与任何契约拒绝都是整体失败——零部分结果。
///
/// 确定性：新增元素 id、versionNonce、updated 全部显式推导（无随机、
/// 无时钟），同一输入双跑产出深度等价 patch。
abstract final class SmartLayoutCandidateMaterializer {
  static const String addedIdPrefix = 'sl3-';

  /// [timestampMs]：新增/改写元素的 updated 字段（显式传入保证双跑
  /// 确定）；[pageId]：新元素的页面归属（customData.flowMuse.pageId，
  /// 与快照提取同口径；null 表示无分页数据）。
  static PatchMaterializationOutcome materialize({
    required Scene baseScene,
    required SceneRevision baseRevision,
    required SourceCoverageLedger sourceCoverage,
    required LayoutBlockAssembly assembly,
    required FlowPlacementSuccess placement,
    required int timestampMs,
    String? pageId,
  }) {
    // ---- 0. ledger 守恒前置：assembly 账目与传入账本一致 ----
    if (!assembly.ledgerConserved) {
      return const PatchMaterializationFailure(
        kind: PatchMaterializationFailureKind.ledgerNotConserved,
        blockId: '*',
        detail: 'assembly sourceRefs 重复或与文档账目不符',
      );
    }
    final consumedSet = assembly.documentConsumedSourceIds.toSet();
    final preservedSet = assembly.documentPreservedSourceIds.toSet();
    if (!_setEquals(
      consumedSet.union(preservedSet),
      sourceCoverage.statuses.keys.toSet(),
    )) {
      return const PatchMaterializationFailure(
        kind: PatchMaterializationFailureKind.ledgerSourceMismatch,
        blockId: '*',
        detail: 'assembly 源集与账本源集不一致',
      );
    }

    final baseActiveById = <String, Element>{
      for (final element in baseScene.activeElements) element.id.value: element,
    };
    final placedByBlockId = {
      for (final placed in placement.placed) placed.blockId: placed,
    };

    // ---- 1. 块分类（按 assembly 块序，首个失败即返回）----
    final transformPlans = <_TransformPlan>[];
    final retypePlans = <_RetypePlan>[];
    for (final block in assembly.blocks) {
      final isPreservedLike =
          block.kind == LayoutBlockKind.preserved ||
          block.kind == LayoutBlockKind.protected;
      final isMissingFigure =
          block.figure != null && block.figure!.missingAsset;
      if (isPreservedLike || isMissingFigure) {
        // preserved/protected/资产缺失：原样保留，零元素操作
        //（ledger 状态一律按 assembly 文档账目）。
        if (!_allResolve(block.sourceRefs, baseActiveById)) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.sourceUnresolved,
            blockId: block.id,
            detail: '保留块 sourceRef 未解析',
          );
        }
        continue;
      }
      if (block.kind == LayoutBlockKind.table) {
        return PatchMaterializationFailure(
          kind: PatchMaterializationFailureKind.unsupportedBlockKind,
          blockId: block.id,
          detail: 'table 物化语义 v1 未定义',
        );
      }
      // 源契约先于放置查找校验（块与 base 的结构绑定是 assembly 属性）。
      if (block.figure != null) {
        if (block.sourceRefs.length != 1) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.figureSourceInvalid,
            blockId: block.id,
            detail: 'figure sourceRefs=${block.sourceRefs.length}，必须为 1',
          );
        }
        final figureSource = baseActiveById[block.sourceRefs.single];
        if (figureSource is! ImageElement) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.figureSourceInvalid,
            blockId: block.id,
            detail: 'figure 源不是活动 ImageElement',
          );
        }
        final placed = placedByBlockId[block.id];
        if (placed == null) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.missingPlacement,
            blockId: block.id,
            detail: 'placement 未覆盖该消费块',
          );
        }
        transformPlans.add(
          _TransformPlan(
            blockId: block.id,
            sourceId: figureSource.id.value,
            placed: placed,
          ),
        );
        continue;
      }
      final spec = block.text;
      if (spec == null) {
        return PatchMaterializationFailure(
          kind: PatchMaterializationFailureKind.unsupportedBlockKind,
          blockId: block.id,
          detail: '无文本规格的消费块无物化语义',
        );
      }
      if (block.textOrigin == LayoutTextOrigin.typed) {
        if (block.sourceRefs.length != 1) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.typedSourceInvalid,
            blockId: block.id,
            detail: 'typed sourceRefs=${block.sourceRefs.length}，必须为 1',
          );
        }
        final typedSource = baseActiveById[block.sourceRefs.single];
        if (typedSource is! TextElement) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.typedSourceInvalid,
            blockId: block.id,
            detail: 'typed 源不是活动 TextElement',
          );
        }
        final placed = placedByBlockId[block.id];
        if (placed == null) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.missingPlacement,
            blockId: block.id,
            detail: 'placement 未覆盖该消费块',
          );
        }
        transformPlans.add(
          _TransformPlan(
            blockId: block.id,
            sourceId: typedSource.id.value,
            placed: placed,
          ),
        );
      } else {
        // transcribed：源笔迹整组移除，新增确定性文本元素承载转写。
        for (final ref in block.sourceRefs) {
          if (!baseActiveById.containsKey(ref)) {
            return PatchMaterializationFailure(
              kind: PatchMaterializationFailureKind.sourceUnresolved,
              blockId: block.id,
              detail: 'sourceRef "$ref" 未解析',
            );
          }
        }
        final placed = placedByBlockId[block.id];
        if (placed == null) {
          return PatchMaterializationFailure(
            kind: PatchMaterializationFailureKind.missingPlacement,
            blockId: block.id,
            detail: 'placement 未覆盖该消费块',
          );
        }
        retypePlans.add(_RetypePlan(block: block, placed: placed, spec: spec));
      }
    }

    // ---- 2. 变换链：逐块经 V3-303A 原子变换（闭包/绑定统一重算）----
    var evolvingScene = baseScene;
    final baseVersionById = <String, int>{
      for (final element in baseScene.elements)
        element.id.value: element.version,
    };
    final finalStates = <String, Element>{};
    for (final plan in transformPlans) {
      Element? current;
      for (final element in evolvingScene.activeElements) {
        if (element.id.value == plan.sourceId) {
          current = element;
          break;
        }
      }
      if (current == null) {
        return PatchMaterializationFailure(
          kind: PatchMaterializationFailureKind.sourceUnresolved,
          blockId: plan.blockId,
          detail: '变换源 "${plan.sourceId}" 在演进场景中不存在',
        );
      }
      if (current.width <= 0 || current.height <= 0) {
        return PatchMaterializationFailure(
          kind: PatchMaterializationFailureKind.transformRejected,
          blockId: plan.blockId,
          detail: '源 "${plan.sourceId}" 尺寸非正，无法推导变换',
        );
      }
      final target = plan.placed.rect;
      final sx = target.width / current.width;
      final sy = target.height / current.height;
      final transform = AffineLayoutTransform(
        m00: sx,
        m01: 0,
        m10: 0,
        m11: sy,
        tx: target.left - current.x * sx,
        ty: target.top - current.y * sy,
      );
      final isMoveOnly = sx == 1 && sy == 1;
      final outcome = SmartLayoutSceneTransformer.apply(
        scene: evolvingScene,
        targetIds: {ElementId(plan.sourceId)},
        op: isMoveOnly ? LayoutTransformOp.move : LayoutTransformOp.resize,
        transform: transform,
        resizeTargetWidth: target.width,
        resizeTargetHeight: target.height,
      );
      if (outcome is SceneTransformFailure) {
        return PatchMaterializationFailure(
          kind: PatchMaterializationFailureKind.transformRejected,
          blockId: plan.blockId,
          detail: '源 "${plan.sourceId}" ${outcome.reason.name}',
        );
      }
      final success = outcome as SceneTransformSuccess;
      evolvingScene = success.scene;
      for (final element in success.updatedElements) {
        // typed 文本字号显式对齐放置档（变换器不缩放 fontSize）。
        if (element is TextElement &&
            element.fontSize != plan.placed.appliedFontSize) {
          finalStates[element.id.value] = element.copyWithText(
            fontSize: plan.placed.appliedFontSize,
          );
        } else {
          finalStates[element.id.value] = element;
        }
      }
    }

    // ---- 3. 新增元素确定性 id（sl3- 前缀；冲突即 salt 递增）----
    // 守恒前置：变换闭包不得触碰 assembly 记为 preserved 的源
    //（保留物零副作用；missingAsset 消费源虽零触碰，但按 assembly
    // 账目计入 consumed，不在此判定）。
    final assemblyPreserved = assembly.documentPreservedSourceIds.toSet();
    final touchedPreserved =
        finalStates.keys.where(assemblyPreserved.contains).toList()..sort();
    if (touchedPreserved.isNotEmpty) {
      return PatchMaterializationFailure(
        kind: PatchMaterializationFailureKind.ledgerNotConserved,
        blockId: '*',
        detail: '变换闭包触碰 preserved 源：${touchedPreserved.join(', ')}',
      );
    }
    final usedIds = baseScene.elements.map((e) => e.id.value).toSet();
    for (final plan in retypePlans) {
      var candidate = '$addedIdPrefix${_sanitizeId(plan.block.id)}';
      var salt = 2;
      while (usedIds.contains(candidate)) {
        candidate = '$addedIdPrefix${_sanitizeId(plan.block.id)}-$salt';
        salt++;
      }
      usedIds.add(candidate);
      plan.newElementId = candidate;
    }

    // ---- 4. 装配 patch（Builder + PatchInvariant 终审）----
    final finalizedLedger = sourceCoverage
        .markConsumed(consumedSet)
        .markPreserved(preservedSet);
    final builder = SmartLayoutScenePatchBuilder(
      baseScene: baseScene,
      baseRevision: baseRevision,
      sourceCoverage: finalizedLedger,
    );

    final removedIds = <String>{
      for (final plan in retypePlans) ...plan.block.sourceRefs,
    };
    for (final entry in finalStates.entries) {
      // 同一元素同时被变换跟随与移除时，移除胜出（笔迹归档语义）。
      if (removedIds.contains(entry.key)) continue;
      final baseVersion = baseVersionById[entry.key] ?? entry.value.version;
      builder.updateElement(
        entry.value.copyWith(
          version: baseVersion + 1,
          versionNonce: _nonceFor(entry.key, baseRevision),
          updated: timestampMs,
        ),
        baseVersion: baseVersion,
      );
    }
    for (final plan in retypePlans) {
      for (final ref in plan.block.sourceRefs) {
        builder.removeElement(
          ref,
          baseVersion: baseVersionById[ref] ?? 1,
          versionNonce: _nonceFor(ref, baseRevision),
        );
      }
      final text = plan.newElementId!;
      final rect = plan.placed.rect;
      builder.addElement(
        TextElement(
          id: ElementId(text),
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
          text: plan.spec.text,
          fontSize: plan.placed.appliedFontSize,
          fontFamily: plan.spec.fontFamily,
          lineHeight: plan.spec.lineHeight,
          autoResize: false,
          seed: _seedFor(text),
          versionNonce: _nonceFor(text, baseRevision),
          updated: timestampMs,
          customData: pageId == null
              ? null
              : {
                  'flowMuse': {'pageId': pageId},
                },
        ),
      );
    }
    final selection = <String>[
      ...[for (final plan in transformPlans) plan.sourceId],
      ...[
        for (final plan in retypePlans)
          if (plan.newElementId != null) plan.newElementId!,
      ],
    ]..sort();
    if (selection.isNotEmpty) {
      builder.setSelectionIntent(selection);
    }

    try {
      final patch = builder.build();
      return PatchMaterializationSuccess(
        patch: patch,
        consumedSourceIds: consumedSet.toList()..sort(),
        preservedSourceIds: preservedSet.toList()..sort(),
        addedElementIds: [
          for (final plan in retypePlans)
            if (plan.newElementId != null) plan.newElementId!,
        ],
        transformedSourceIds: [
          for (final plan in transformPlans) plan.sourceId,
        ],
      );
    } on StateError catch (error) {
      // Builder 终审失败 = 物化内部契约破坏；作为整体失败上报。
      return PatchMaterializationFailure(
        kind: PatchMaterializationFailureKind.patchInvariantRejected,
        blockId: '*',
        detail: 'patch 不变量终审失败：$error',
      );
    }
  }

  static bool _allResolve(
    List<String> refs,
    Map<String, Element> baseActiveById,
  ) => refs.every(baseActiveById.containsKey);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// 确定性 nonce：元素 id + base 指纹推导（跨端/双跑一致，31 位内）。
  static int _nonceFor(String elementId, SceneRevision baseRevision) =>
      int.parse(
        fingerprint64(
          'sl3-nonce|$elementId|${baseRevision.fingerprint.value}',
        ).substring(0, 8),
        radix: 16,
      ) &
      0x7fffffff;

  /// 确定性 seed：元素 id 推导（正 31 位内）。
  static int _seedFor(String elementId) =>
      int.parse(
        fingerprint64('sl3-seed|$elementId').substring(0, 8),
        radix: 16,
      ) &
      0x7fffffff;

  /// 块 id 只保留安全字符，保证元素 id 形态稳定。
  static String _sanitizeId(String blockId) =>
      blockId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

class _TransformPlan {
  _TransformPlan({
    required this.blockId,
    required this.sourceId,
    required this.placed,
  });

  final String blockId;
  final String sourceId;
  final PlacedBlock placed;
}

class _RetypePlan {
  _RetypePlan({required this.block, required this.placed, required this.spec});

  final LayoutBlock block;
  final PlacedBlock placed;
  final TextBlockSpec spec;
  String? newElementId;
}
