library;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import '../geometry/smart_layout_scene_transformer.dart';

/// R6 语义适配器（spec §8）：识别会话产物 → [SemanticAssembly]。
///
/// - 识别账本由本适配器结算（[settle]）：recognized 笔迹按结构单元
///   consume；uncertain/锁定/未入流原生源按 §6.4 保留原因 preserve；
/// - 账本单向投影（§6.4）：assembly 的 consumed/preserved 与
///   sourceId→unitId 归属全部由结算后的识别账本导出，本类不重新决定
///   识别准入；
/// - 角色映射显式写死（§8.1 表）：listItem→list、other→unknown，
///   禁止同名映射兜底；
/// - 字号（§8.2/#14）：title 取 tokens.titleFloorSize，其余文本取
///   tokens.bodySize，记入块 extras；源笔迹行高提示不参与选档；
/// - 宽度测量全部留在块组装阶段（LayoutBlockAssembler 的
///   TextMeasureAdapter 路径），本适配器不做栏宽测量——[measure]
///   仅为接线签名占位，不在此调用。
class RecognitionSemanticAdapter {
  const RecognitionSemanticAdapter();

  /// 结算识别账本并返回携带已结算账本的会话结果副本（幂等：已终态
  /// 条目不再改写；同源重复认领仍 fail closed）。
  RecognitionSessionResult settle(RecognitionSessionResult result) {
    final structure = _structureOf(result);
    var ledger = result.ledger;
    ledger = ledger.registerUnits([
      for (final unit in structure.units) unit.unitId,
    ]);

    // 1. ink 单元：recognized→consume（锁定笔迹毒化整单元→保留）；
    //    uncertain→保留（§6.4 准入条件 6）。
    final lockedSourceIds = _lockedSourceIds(result);
    final replacementFacts = ReplacementGuard.factsOf(result);
    for (final unit in structure.units) {
      if (unit.kind != RecognitionUnitKind.ink) continue;
      final regionId = _regionIdOfInkUnit(unit.unitId);
      if (regionId == null) {
        throw StateError('ink 单元 id 无 ink: 前缀: ${unit.unitId}');
      }
      final record = _recordOf(result, regionId);
      final outcome = result.regionOutcomes[regionId];
      if (outcome == null) {
        throw StateError('ink 单元引用了无识别结果的区域: $regionId');
      }
      final poisoned = record.targetSourceIds.any(lockedSourceIds.contains);
      final facts = replacementFacts[unit.unitId]!;
      final admission = ConversionAdmission.check(
        statusConfirmedRecognized:
            outcome.status == RecognitionRegionStatus.recognized,
        text: facts.text,
        unitSourceIds: record.targetSourceIds.toSet(),
        regionTargetSourceIds: facts.regionTargetSourceIds,
        sourceGuards: facts.sourceGuards,
        conflictsResolved: facts.conflictsResolved,
        versionValid: facts.versionValid,
      );
      if (admission != null) {
        final reason = poisoned
            ? SourcePreserveReason.locked
            : SourcePreserveReason.uncertain;
        for (final sourceId in record.targetSourceIds) {
          ledger = _preserveIfPending(ledger, sourceId, reason);
        }
        continue;
      }
      for (final sourceId in record.targetSourceIds) {
        ledger = _consumeIfPending(ledger, sourceId, unit.unitId);
      }
    }

    // 2. 原生单元：typed/figure 入流（结构角色 other 的 typed 不入流）
    //   →consume；锁定→保留；形状/未入流→保留。
    final elementById = _nonBackgroundElementById(result);
    final flowRoles = const {'title', 'body', 'caption', 'listItem'};
    final eligibleNative = {
      for (final unit in structure.units)
        if ((unit.kind == RecognitionUnitKind.figure ||
                (unit.kind == RecognitionUnitKind.typed &&
                    flowRoles.contains(structure.roles[unit.unitId]))) &&
            !structure.conflictedUnitIds.contains(unit.unitId))
          _sourceIdOfNativeUnit(unit.unitId),
    };
    final blockedNative = <String>{};
    for (final id in eligibleNative) {
      final closure = SmartLayoutSceneTransformer.closureOf(result.scene, {
        ElementId(id),
      });
      if (closure.any(
        (ref) =>
            !eligibleNative.contains(ref.value) ||
            (elementById[ref.value]?.locked ?? true) ||
            result.pageScope?.protectedSourceIds.contains(ref.value) == true ||
            (result.pageScope?.effectivePageIdOf(elementById[ref.value]!) ??
                    elementById[ref.value]?.pageId) !=
                (result.pageScope?.effectivePageIdOf(elementById[id]!) ??
                    elementById[id]?.pageId),
      )) {
        blockedNative.addAll(closure.map((ref) => ref.value));
      }
    }
    for (final unit in structure.units) {
      if (unit.kind != RecognitionUnitKind.typed &&
          unit.kind != RecognitionUnitKind.figure) {
        continue;
      }
      final sourceId = _sourceIdOfNativeUnit(unit.unitId);
      final element = elementById[sourceId];
      if (element == null) {
        throw StateError('原生单元引用了不存在的场景元素: ${unit.unitId}');
      }
      if (element.locked ||
          result.pageScope?.protectedSourceIds.contains(sourceId) == true) {
        ledger = _preserveIfPending(
          ledger,
          sourceId,
          SourcePreserveReason.locked,
        );
        continue;
      }
      if (structure.conflictedUnitIds.contains(unit.unitId) ||
          blockedNative.contains(sourceId)) {
        ledger = _preserveIfPending(
          ledger,
          sourceId,
          SourcePreserveReason.uncertain,
        );
        continue;
      }
      if (unit.kind == RecognitionUnitKind.figure) {
        ledger = _consumeIfPending(ledger, sourceId, unit.unitId);
        continue;
      }
      final role = structure.roles[unit.unitId];
      if (role != null && !flowRoles.contains(role)) {
        // 结构判定 other：不进排版流，保留原样。
        ledger = _preserveIfPending(
          ledger,
          sourceId,
          SourcePreserveReason.contextOnly,
        );
        continue;
      }
      ledger = _consumeIfPending(ledger, sourceId, unit.unitId);
    }

    // 3. 兜底清扫：仍未结算的源（区域派生保留单元、未成块空文区域、
    //    无结构单元覆盖的原生物）按事实推导保留原因。
    for (final sourceId in ledger.sourceIds) {
      if (ledger.entryOf(sourceId).status != SourceLedgerStatus.pending) {
        continue;
      }
      ledger = _preserveIfPending(
        ledger,
        sourceId,
        _sweepReason(result, elementById, sourceId),
      );
    }
    ledger.assertAllSettled();
    return result.copyWith(ledger: ledger);
  }

  /// 结构结果 → 语义文档装配（spec §8.1/§8.2）。
  SemanticAssembly assemble(
    RecognitionSessionResult result, {
    required TextMeasureAdapter measure,
    required SmartLayoutDesignTokens tokens,
  }) {
    final settled = settle(result);
    final structure = _structureOf(result);
    final elementById = _nonBackgroundElementById(result);

    // 阅读序：修复列表子树连续性（§8.1——同一子树成员在 orderedBlockIds
    // 中连续；本地行带序可能拆散嵌套子树）。
    final order = _contiguousReadingOrder(structure);
    final orderIndexOf = <String, int>{
      for (var i = 0; i < order.length; i++) order[i]: i,
    };

    // listGroup/caption 元数据索引。
    final groupByMember = <String, RecognitionListGroup>{};
    for (final group in structure.listGroups) {
      for (final member in group.members) {
        groupByMember[member] = group;
      }
    }
    final captionTargetOf = <String, String>{
      for (final caption in structure.captions)
        caption.captionUnitId: caption.targetUnitId,
    };
    final figureTargetOf = <String, String>{
      for (final link in structure.figureTextLinks)
        if (link.confidence >= 0.8 &&
            structure.units.any(
              (u) =>
                  u.unitId == link.figureUnitId &&
                  u.kind == RecognitionUnitKind.figure &&
                  settled.ledger
                          .entryOf(_sourceIdOfNativeUnit(u.unitId))
                          .status ==
                      SourceLedgerStatus.consumed,
            ))
          link.textUnitId: link.figureUnitId,
    };
    final unitIds = {for (final unit in structure.units) unit.unitId};
    for (final entry in captionTargetOf.entries) {
      if (!unitIds.contains(entry.key) || !unitIds.contains(entry.value)) {
        throw StateError('图注关系目标不存在: ${entry.key} -> ${entry.value}');
      }
    }

    final lockedSourceIds = _lockedSourceIds(result);
    final blocks = <SemanticBlock>[];
    for (final unit in structure.units) {
      if (unit.kind == RecognitionUnitKind.typed ||
          unit.kind == RecognitionUnitKind.figure) {
        final sourceId = _sourceIdOfNativeUnit(unit.unitId);
        final element = elementById[sourceId];
        if (element == null) {
          throw StateError('原生单元引用了不存在的场景元素: ${unit.unitId}');
        }
        if (element.locked) {
          // 锁定物：无语义块（快照装配层的 protected 障碍块接管）。
          continue;
        }
      }
      blocks.add(
        _blockOf(
          settled,
          structure,
          unit,
          groupByMember: groupByMember,
          captionTargetOf: captionTargetOf,
          figureTargetOf: figureTargetOf,
          orderIndexOf: orderIndexOf,
          elementById: elementById,
          lockedSourceIds: lockedSourceIds,
          tokens: tokens,
        ),
      );
    }
    final blockIds = {for (final block in blocks) block.id};

    // 账本单向投影（§6.4）：consumed/preserved 全部由结算后的识别账本导出。
    final projection = settled.ledger.projection;
    if (!projection.fullySettled) {
      throw StateError('识别账本未结算，禁止投影');
    }
    if (projection.sourceIds.length != elementById.length ||
        !projection.sourceIds.containsAll(elementById.keys.toSet())) {
      throw StateError('识别账本源集合与完整捕获源集合−背景不一致');
    }
    final consumedSorted = projection.consumedBy.keys.toList()..sort();
    final preservedSorted = projection.preservedReasons.keys.toList()..sort();
    var coverage = SourceCoverageLedger.pending(projection.sourceIds);
    coverage = coverage.markConsumed(consumedSorted);
    coverage = coverage.markPreserved(preservedSorted);
    if (!coverage.isFinalized) {
      throw StateError('投影账本未闭合：剩余 ${coverage.pendingCount} 个 pending');
    }

    final document = SemanticDocument(
      formatVersion: SemanticDocumentFormat.currentVersion,
      pageId: settled.pageId,
      epoch: settled.sceneRevision.epoch,
      revision: settled.sceneRevision.revision,
      fingerprint: settled.sceneRevision.fingerprint,
      blocks: List.unmodifiable(blocks..sort((a, b) => a.id.compareTo(b.id))),
      readingOrder: SemanticReadingOrder(
        orderedBlockIds: List.unmodifiable([
          // 阅读序只引用实际产出的块（锁定原生单元无语义块，不在序中）。
          for (final id in order)
            if (blockIds.contains(id)) id,
        ]),
      ),
      conflicts: const [],
      consumedSourceIds: List.unmodifiable(consumedSorted),
      preservedSourceIds: List.unmodifiable(preservedSorted),
    );
    if (!document.ledgerConserved) {
      throw StateError('文档 ledger 不守恒');
    }
    return SemanticAssembly(document: document, ledger: coverage);
  }

  // ---- settle 辅助 ----

  static StructureResult _structureOf(RecognitionSessionResult result) {
    final structure = result.structureResult;
    if (structure is! StructureResult) {
      throw StateError('结构结果缺失或类型不符，无法装配语义文档');
    }
    return structure;
  }

  static Map<String, Element> _nonBackgroundElementById(
    RecognitionSessionResult result,
  ) => {
    for (final element in result.scene.activeElements)
      if (!(element.isCanvasPage || element.isPdfBackground))
        element.id.value: element,
  };

  static Set<String> _lockedSourceIds(RecognitionSessionResult result) => {
    ...?result.pageScope?.protectedSourceIds,
    for (final element in result.scene.activeElements)
      if (element.locked) element.id.value,
  };

  /// regionId 反查（区域派生保留单元 native:<最小源> 的归属区域）。
  static Map<String, RegionRecord> _recordByMinSource(
    RecognitionSessionResult result,
  ) => {
    for (final record in result.regionRecords)
      _minOf(record.targetSourceIds): record,
  };

  static RegionRecord _recordOf(
    RecognitionSessionResult result,
    String regionId,
  ) {
    for (final record in result.regionRecords) {
      if (record.regionId == regionId) return record;
    }
    throw StateError('ink 单元引用了不存在的区域记录: $regionId');
  }

  static String? _regionIdOfInkUnit(String unitId) =>
      unitId.startsWith('ink:') ? unitId.substring('ink:'.length) : null;

  static String _sourceIdOfNativeUnit(String unitId) {
    if (!unitId.startsWith('native:')) {
      throw StateError('原生单元 id 无 native: 前缀: $unitId');
    }
    return unitId.substring('native:'.length);
  }

  static String _minOf(List<String> ids) {
    var min = ids.first;
    for (final id in ids.skip(1)) {
      if (id.compareTo(min) < 0) min = id;
    }
    return min;
  }

  SourcePreserveReason _sweepReason(
    RecognitionSessionResult result,
    Map<String, Element> elementById,
    String sourceId,
  ) {
    for (final record in result.regionRecords) {
      if (!record.targetSourceIds.contains(sourceId)) continue;
      final outcome = result.regionOutcomes[record.regionId];
      if (outcome == null) break;
      if (outcome.status == RecognitionRegionStatus.uncertain) {
        return SourcePreserveReason.uncertain;
      }
      // recognized 但未成 ink 单元（正文为空）：无可消费文本，按不可读保留。
      return SourcePreserveReason.unreadable;
    }
    final element = elementById[sourceId];
    if (element != null) {
      if (element.locked) return SourcePreserveReason.locked;
      return SourcePreserveReason.nonText;
    }
    return SourcePreserveReason.contextOnly;
  }

  static SourceLedger _consumeIfPending(
    SourceLedger ledger,
    String sourceId,
    String unitId,
  ) {
    final entry = ledger.entryOf(sourceId);
    if (entry.status == SourceLedgerStatus.pending) {
      return ledger.consume(sourceId, unitId);
    }
    if (entry.status == SourceLedgerStatus.consumed && entry.unitId == unitId) {
      return ledger;
    }
    throw StateError(
      '源 $sourceId 终态冲突: '
      '${entry.status.name}${entry.unitId != null ? '(${entry.unitId})' : ''}'
      ' ≠ consume($unitId)',
    );
  }

  static SourceLedger _preserveIfPending(
    SourceLedger ledger,
    String sourceId,
    SourcePreserveReason reason,
  ) {
    if (ledger.entryOf(sourceId).status == SourceLedgerStatus.pending) {
      return ledger.preserve(sourceId, reason);
    }
    return ledger;
  }

  // ---- assemble 辅助 ----

  SemanticBlock _blockOf(
    RecognitionSessionResult result,
    StructureResult structure,
    RecognitionUnitInput unit, {
    required Map<String, RecognitionListGroup> groupByMember,
    required Map<String, String> captionTargetOf,
    required Map<String, String> figureTargetOf,
    required Map<String, int> orderIndexOf,
    required Map<String, Element> elementById,
    required Set<String> lockedSourceIds,
    required SmartLayoutDesignTokens tokens,
  }) {
    final role = _roleOf(result, structure, unit, elementById, lockedSourceIds);
    final extras = <String, Object?>{};

    // §8.2/#14 字号：title→titleFloorSize，其余→bodySize；与外框/行高
    // 提示/截图倍率无关（宽度测量留在块组装阶段）。
    if (unit.kind == RecognitionUnitKind.ink ||
        unit.kind == RecognitionUnitKind.typed) {
      extras['fontSize'] = role == SemanticRole.title
          ? tokens.titleFloorSize
          : tokens.bodySize;
    }

    String? text;
    List<String> sourceIds;
    double confidence;
    switch (unit.kind) {
      case RecognitionUnitKind.ink:
        final regionId = _regionIdOfInkUnit(unit.unitId)!;
        final record = _recordOf(result, regionId);
        final outcome = result.regionOutcomes[regionId]!;
        final transcribed = outcome.text?.trim();
        if (transcribed != null && transcribed.isNotEmpty) {
          extras['transcribedText'] = transcribed;
        }
        sourceIds = List.unmodifiable(record.targetSourceIds);
        confidence = outcome.confidence ?? 0;
      case RecognitionUnitKind.typed:
        final element =
            elementById[_sourceIdOfNativeUnit(unit.unitId)] as TextElement?;
        if (element == null) {
          throw StateError('typed 单元源不是场景文本元素: ${unit.unitId}');
        }
        text = element.text.isEmpty ? null : element.text;
        sourceIds = [element.id.value];
        confidence = 1;
      case RecognitionUnitKind.figure:
        sourceIds = [_sourceIdOfNativeUnit(unit.unitId)];
        confidence = 1;
      case RecognitionUnitKind.preserved:
        sourceIds = _sourcesOfPreservedUnit(result, unit, elementById);
        confidence = 1;
    }

    final group = groupByMember[unit.unitId];
    if (group != null) {
      extras['listGroupId'] = group.groupId;
      extras['level'] = group.level;
      extras['listType'] = group.listType.wireName;
      if (group.startNumber != null) extras['startNumber'] = group.startNumber;
      if (group.parentUnitId != null) {
        extras['parentUnitId'] = group.parentUnitId;
      }
    }
    final captionTarget = captionTargetOf[unit.unitId];
    if (captionTarget != null) {
      extras['captionOf'] = captionTarget;
    }
    final figureTarget = figureTargetOf[unit.unitId];
    if (figureTarget != null &&
        (role == SemanticRole.body || role == SemanticRole.list)) {
      extras['relatedFigure'] = figureTarget;
    }
    if (role == SemanticRole.unknown) {
      // 保留块障碍物身份（§8.1：带原始 bounds 进入约束输入）。
      extras['bounds'] = {
        'left': unit.bounds.left,
        'top': unit.bounds.top,
        'width': unit.bounds.width,
        'height': unit.bounds.height,
      };
    }

    return SemanticBlock(
      id: unit.unitId,
      role: role,
      sourceIds: sourceIds,
      orderIndex: orderIndexOf[unit.unitId] ?? 0,
      confidence: confidence,
      text: text,
      extras: Map.unmodifiable(extras),
    );
  }

  /// §8.1 角色映射表（显式写死，禁止同名映射兜底）。
  SemanticRole _roleOf(
    RecognitionSessionResult result,
    StructureResult structure,
    RecognitionUnitInput unit,
    Map<String, Element> elementById,
    Set<String> lockedSourceIds,
  ) {
    final sources = unit.kind == RecognitionUnitKind.ink
        ? _recordOf(result, _regionIdOfInkUnit(unit.unitId)!).targetSourceIds
        : [_sourceIdOfNativeUnit(unit.unitId)];
    if (structure.conflictedUnitIds.contains(unit.unitId) ||
        sources.any(
          (id) =>
              result.ledger.entryOf(id).status == SourceLedgerStatus.preserved,
        )) {
      return SemanticRole.unknown;
    }
    switch (unit.kind) {
      case RecognitionUnitKind.figure:
        return SemanticRole.figure;
      case RecognitionUnitKind.preserved:
        return SemanticRole.unknown;
      case RecognitionUnitKind.typed:
        if (elementById[_sourceIdOfNativeUnit(unit.unitId)]?.locked ?? false) {
          return SemanticRole.unknown;
        }
        return _mapStructureRole(structure.roles[unit.unitId]);
      case RecognitionUnitKind.ink:
        final regionId = _regionIdOfInkUnit(unit.unitId)!;
        final outcome = result.regionOutcomes[regionId];
        if (outcome == null ||
            outcome.status != RecognitionRegionStatus.recognized) {
          // uncertain：按保留语义处理，不进排版流。
          return SemanticRole.unknown;
        }
        final record = _recordOf(result, regionId);
        if (record.targetSourceIds.any(lockedSourceIds.contains)) {
          // 锁定笔迹毒化整单元：保留语义。
          return SemanticRole.unknown;
        }
        return _mapStructureRole(structure.roles[unit.unitId]);
    }
  }

  static SemanticRole _mapStructureRole(String? role) {
    switch (role) {
      case 'title':
        return SemanticRole.title;
      case 'body':
        return SemanticRole.body;
      case 'caption':
        return SemanticRole.caption;
      case 'listItem':
        return SemanticRole.list;
      // other / 缺席：保留语义，不进排版流。
      default:
        return SemanticRole.unknown;
    }
  }

  /// 保留单元的源集：区域派生（native:<最小源> 未命中场景元素）取该
  /// 区域 target 全集；场景原生形状取该元素自身。
  List<String> _sourcesOfPreservedUnit(
    RecognitionSessionResult result,
    RecognitionUnitInput unit,
    Map<String, Element> elementById,
  ) {
    final sourceId = _sourceIdOfNativeUnit(unit.unitId);
    // 区域派生保留单元（native:<区域最小源>）优先按区域记录解析整组
    // target 集——最小源本身也是场景元素，先查元素表会把多笔迹区域
    // 截断成单源，块装配守恒（并集 vs ledger）随之失败。场景形状类
    // 保留单元无区域记录，按单元素解析。
    final record = _recordByMinSource(result)[sourceId];
    if (record != null) {
      return List.unmodifiable(record.targetSourceIds);
    }
    if (elementById.containsKey(sourceId)) {
      return [sourceId];
    }
    throw StateError('保留单元无法解析源集: ${unit.unitId}');
  }

  /// 阅读序子树连续修复：同一列表子树（组 + 挂靠子组）的成员在
  /// orderedBlockIds 中连续，组内相对顺序保持结构阅读序。
  List<String> _contiguousReadingOrder(StructureResult structure) {
    final groupOfMember = <String, String>{};
    for (final group in structure.listGroups) {
      for (final member in group.members) {
        groupOfMember[member] = group.groupId;
      }
    }
    final groupsById = {
      for (final group in structure.listGroups) group.groupId: group,
    };

    // 根组解析：parentUnitId → 所属组 → 递归上溯（深度上限防环）。
    final rootCache = <String, String>{};
    String rootOf(String groupId) {
      var current = groupId;
      for (var depth = 0; depth < groupsById.length + 1; depth++) {
        final cached = rootCache[current];
        if (cached != null) return cached;
        final group = groupsById[current];
        final parent = group?.parentUnitId;
        final parentGroup = parent == null ? null : groupOfMember[parent];
        if (parentGroup == null || parentGroup == current) {
          rootCache[current] = current;
          return current;
        }
        current = parentGroup;
      }
      rootCache[current] = current;
      return current;
    }

    final subtreeOfRoot = <String, Set<String>>{};
    for (final group in structure.listGroups) {
      subtreeOfRoot
          .putIfAbsent(rootOf(group.groupId), () => {})
          .addAll(group.members);
    }

    final emitted = <String>{};
    final out = <String>[];
    for (final id in structure.readingOrder) {
      if (emitted.contains(id)) continue;
      final groupId = groupOfMember[id];
      if (groupId == null) {
        out.add(id);
        emitted.add(id);
        continue;
      }
      final subtree = subtreeOfRoot[rootOf(groupId)] ?? const <String>{};
      for (final candidate in structure.readingOrder) {
        if (subtree.contains(candidate) && !emitted.contains(candidate)) {
          out.add(candidate);
          emitted.add(candidate);
        }
      }
    }
    // 阅读序未覆盖的单元（异常输入）按原序追加，不静默丢弃。
    for (final unit in structure.units) {
      if (!emitted.contains(unit.unitId)) {
        out.add(unit.unitId);
        emitted.add(unit.unitId);
      }
    }
    return out;
  }
}

/// §6.4-1 三方一致断言（候选生成入口第 0 步之后调用，fail closed）：
/// ① 完整捕获源集合−背景 = 识别账本源集合 = assembly 账本源集合；
/// ② 逐源终态（consume/preserve）一致；③ consumed 源的归属 unitId 在
/// 识别账本与 assembly 块 sourceRefs 间一致。
///
/// 断言输入是独立的只读识别账本——不得用 assembly 自身账目反推一份
/// 账本来"自证一致"。
abstract final class RecognitionLedgerAssertions {
  static void assertThreeWayConsistency({
    required Set<String> capturedNonBackgroundSourceIds,
    required SourceLedger recognition,
    required SemanticAssembly assembly,
  }) {
    final recognitionIds = recognition.sourceIds;
    if (recognitionIds.length != capturedNonBackgroundSourceIds.length ||
        !recognitionIds.containsAll(capturedNonBackgroundSourceIds)) {
      throw StateError('三方不一致：识别账本源集合≠完整捕获源集合−背景');
    }
    final projection = recognition.projection;
    if (!projection.fullySettled) {
      throw StateError('三方不一致：识别账本存在未结算源');
    }
    final document = assembly.document;
    final documentIds = {
      ...document.consumedSourceIds,
      ...document.preservedSourceIds,
    };
    if (documentIds.length != recognitionIds.length ||
        !documentIds.containsAll(recognitionIds)) {
      throw StateError('三方不一致：assembly 账本源集合≠识别账本源集合');
    }
    final consumedSet = document.consumedSourceIds.toSet();
    final preservedSet = document.preservedSourceIds.toSet();
    if (consumedSet.intersection(preservedSet).isNotEmpty) {
      throw StateError('三方不一致：文档账本源双终态');
    }
    final recognitionConsumed = projection.consumedBy.keys.toSet();
    final recognitionPreserved = projection.preservedReasons.keys.toSet();
    if (!consumedSet.containsAll(recognitionConsumed) ||
        !recognitionConsumed.containsAll(consumedSet)) {
      throw StateError('三方不一致：consume 终态集合不一致');
    }
    if (!preservedSet.containsAll(recognitionPreserved) ||
        !recognitionPreserved.containsAll(preservedSet)) {
      throw StateError('三方不一致：preserve 终态集合不一致');
    }
    final blockOfSource = <String, String>{};
    for (final block in document.blocks) {
      for (final sourceId in block.sourceIds) {
        if (blockOfSource.containsKey(sourceId)) {
          throw StateError('三方不一致：源 $sourceId 出现在多个块');
        }
        blockOfSource[sourceId] = block.id;
      }
    }
    projection.consumedBy.forEach((sourceId, unitId) {
      if (blockOfSource[sourceId] != unitId) {
        throw StateError(
          '三方不一致：源 $sourceId 归属 $unitId ≠ 块 ${blockOfSource[sourceId]}',
        );
      }
    });
  }
}

/// §6.4-2 物化后置检查的单元事实（按 unit 提供，物化侧组装）。
class ReplacementUnitFacts {
  const ReplacementUnitFacts({
    required this.unitId,
    required this.text,
    required this.regionTargetSourceIds,
    required this.sourceGuards,
    this.conflictsResolved = true,
    this.versionValid = true,
  });

  final String unitId;

  /// 该单元的转写正文（§6.4 条件 2）。
  final String text;

  /// 区域 target 全集（条件 3）。
  final Set<String> regionTargetSourceIds;

  /// unit 消费的全部源的守卫事实（条件 4+5）。
  final Map<String, SourceGuardFacts> sourceGuards;

  /// 条件 6：uncertain/复核冲突已消解。
  final bool conflictsResolved;

  /// 条件 7：四元组校验通过且结构结果与正文指纹匹配。
  final bool versionValid;
}

/// 后置检查违规（确定性描述，不含自由文本推断）。
class ReplacementViolation {
  const ReplacementViolation._(this.kind, this.sourceId);

  /// 删除了未消费/未获准替换的源。
  static const String deletedNotConsumed = 'deleted-not-consumed';

  /// 删除了识别账本保留的源。
  static const String deletedPreserved = 'deleted-preserved';

  /// 删除源的单元未通过转换准入七条件。
  static const String admissionFailed = 'admission-failed';

  /// 保留源被删除或修改。
  static const String preservedTouched = 'preserved-touched';

  final String kind;
  final String sourceId;

  @override
  String toString() => 'ReplacementViolation($kind, $sourceId)';
}

/// §6.4-2 物化后置检查：删除源 ⊆ 已批准替换集合（识别账本 consume 且
/// 七条件通过）；保留源未被删除或修改。违反即候选整体失败。
abstract final class ReplacementGuard {
  /// 同一份源事实用于识别准入和物化后置检查，不能以文档账目自证安全。
  static Map<String, ReplacementUnitFacts> factsOf(
    RecognitionSessionResult result,
  ) {
    final elements = {
      for (final e in result.scene.activeElements) e.id.value: e,
    };
    return {
      for (final record in result.regionRecords)
        'ink:${record.regionId}': ReplacementUnitFacts(
          unitId: 'ink:${record.regionId}',
          text: result.regionOutcomes[record.regionId]?.text ?? '',
          regionTargetSourceIds: record.targetSourceIds.toSet(),
          conflictsResolved:
              result.regionOutcomes[record.regionId]?.status ==
                  RecognitionRegionStatus.recognized &&
              !(result.structureResult is StructureResult &&
                  (result.structureResult as StructureResult).conflictedUnitIds
                      .contains('ink:${record.regionId}')),
          sourceGuards: {
            for (final id in record.targetSourceIds)
              id: SourceGuardFacts(
                isReplaceableInk:
                    elements[id] is FreedrawElement &&
                    brushTypeFromCustomData(
                      elements[id]!.customData,
                    ).canAutoRecognize,
                isLocked:
                    (elements[id]?.locked ?? true) ||
                    result.pageScope?.protectedSourceIds.contains(id) == true,
                hasCrossBinding:
                    (elements[id]?.boundElements.any(
                          (bound) => !record.targetSourceIds.contains(bound.id),
                        ) ??
                        true) ||
                    elements.values.any(
                      (other) =>
                          !record.targetSourceIds.contains(other.id.value) &&
                          other.boundElements.any((bound) => bound.id == id),
                    ),
              ),
          },
        ),
    };
  }

  static List<ReplacementViolation> check({
    required SourceLedger recognition,
    required Map<String, ReplacementUnitFacts> unitFactsByUnitId,
    required Iterable<String> deletedSourceIds,
    required Iterable<String> modifiedSourceIds,
  }) {
    final violations = <ReplacementViolation>[];
    final projection = recognition.projection;
    final deleted = deletedSourceIds.toSet();
    final modified = modifiedSourceIds.toSet();

    for (final sourceId in deleted) {
      final unitId = projection.consumedBy[sourceId];
      if (unitId == null) {
        violations.add(
          ReplacementViolation._(
            projection.preservedReasons.containsKey(sourceId)
                ? ReplacementViolation.deletedPreserved
                : ReplacementViolation.deletedNotConsumed,
            sourceId,
          ),
        );
        continue;
      }
      final facts = unitFactsByUnitId[unitId];
      if (facts == null) {
        violations.add(
          ReplacementViolation._(
            ReplacementViolation.admissionFailed,
            sourceId,
          ),
        );
        continue;
      }
      final failure = ConversionAdmission.check(
        statusConfirmedRecognized: true,
        text: facts.text,
        unitSourceIds: projection.consumedBy.entries
            .where((entry) => entry.value == unitId)
            .map((entry) => entry.key)
            .toSet(),
        regionTargetSourceIds: facts.regionTargetSourceIds,
        sourceGuards: facts.sourceGuards,
        conflictsResolved: facts.conflictsResolved,
        versionValid: facts.versionValid,
      );
      if (failure != null) {
        violations.add(
          ReplacementViolation._(
            ReplacementViolation.admissionFailed,
            sourceId,
          ),
        );
      }
    }
    for (final sourceId in modified) {
      if (projection.preservedReasons.containsKey(sourceId)) {
        violations.add(
          ReplacementViolation._(
            ReplacementViolation.preservedTouched,
            sourceId,
          ),
        );
      }
    }
    return violations;
  }
}
