import '../semantics/semantic_document.dart';

/// 语义纠错 patch 的 revision 前置（语义文档级）。
class SemanticRevisionRef {
  const SemanticRevisionRef({
    required this.epoch,
    required this.revision,
    required this.fingerprint,
  });

  factory SemanticRevisionRef.of(SemanticDocument document) =>
      SemanticRevisionRef(
        epoch: document.epoch,
        revision: document.revision,
        fingerprint: document.fingerprint,
      );

  final int epoch;
  final int revision;
  final String fingerprint;

  bool matches(SemanticDocument document) =>
      epoch == document.epoch &&
      revision == document.revision &&
      fingerprint == document.fingerprint;
}

/// 可逆语义纠错 patch（V3-205A）：role/order/relation/preserve 的显式
/// 修改。apply 产生新文档与逆 patch；非法/过期 patch 零副作用。
sealed class SemanticCorrectionPatch {
  const SemanticCorrectionPatch({required this.baseRevision});

  final SemanticRevisionRef baseRevision;

  String get kind;
}

/// 修改一个块的 role（fromRole 必须匹配当前值——过期检测）。
class SetSemanticRolePatch extends SemanticCorrectionPatch {
  const SetSemanticRolePatch({
    required super.baseRevision,
    required this.blockId,
    required this.fromRole,
    required this.toRole,
  });

  final String blockId;
  final SemanticRole fromRole;
  final SemanticRole toRole;

  @override
  String get kind => 'set-role';
}

/// 重排阅读序（newOrder 必须是现有块 id 的排列）。
class ReorderSemanticPatch extends SemanticCorrectionPatch {
  const ReorderSemanticPatch({
    required super.baseRevision,
    required this.oldOrder,
    required this.newOrder,
  });

  final List<String> oldOrder;
  final List<String> newOrder;

  @override
  String get kind => 'reorder';
}

/// 整体替换一个块的 relations（目标必须存在）。
class SetSemanticRelationsPatch extends SemanticCorrectionPatch {
  const SetSemanticRelationsPatch({
    required super.baseRevision,
    required this.blockId,
    required this.oldRelations,
    required this.newRelations,
  });

  final String blockId;
  final List<({String type, String targetBlockId})> oldRelations;
  final List<({String type, String targetBlockId})> newRelations;

  @override
  String get kind => 'set-relations';
}

/// 在 consumed/preserved 之间切换一组 source 的终态。
/// [toPreserved]=true 把已消费 source 改为 preserved（保护不被重排）；
/// false 为逆操作。inverse 即同 ids 翻转标志。
class PreserveSemanticSourcesPatch extends SemanticCorrectionPatch {
  const PreserveSemanticSourcesPatch({
    required super.baseRevision,
    required this.sourceIds,
    required this.toPreserved,
  });

  final List<String> sourceIds;
  final bool toPreserved;

  @override
  String get kind => toPreserved ? 'preserve-sources' : 'unpreserve-sources';
}

/// 语义 patch 校验器：返回 null 表示合法；否则确定性拒绝原因。
/// 过期 revision 与一切违例都在任何重建之前拦截（零副作用）。
class SemanticPatchValidator {
  const SemanticPatchValidator();

  String? validate(SemanticDocument document, SemanticCorrectionPatch patch) {
    if (!patch.baseRevision.matches(document)) {
      return 'stale-revision(${patch.baseRevision.revision}!=${document.revision})';
    }
    return switch (patch) {
      SetSemanticRolePatch() => _validateRole(document, patch),
      ReorderSemanticPatch() => _validateReorder(document, patch),
      SetSemanticRelationsPatch() => _validateRelations(document, patch),
      PreserveSemanticSourcesPatch() => _validatePreserve(document, patch),
    };
  }

  String? _validateRole(SemanticDocument document, SetSemanticRolePatch patch) {
    final block = _blockById(document, patch.blockId);
    if (block == null) return 'unknown-block(${patch.blockId})';
    if (block.role != patch.fromRole) {
      return 'role-mismatch(${patch.blockId}:${block.role.wireName})';
    }
    return null;
  }

  String? _validateReorder(
    SemanticDocument document,
    ReorderSemanticPatch patch,
  ) {
    final existing = document.readingOrder.orderedBlockIds.toSet();
    if (patch.newOrder.length != existing.length ||
        !existing.containsAll(patch.newOrder)) {
      return 'not-a-permutation';
    }
    if (!_sameList(patch.oldOrder, document.readingOrder.orderedBlockIds)) {
      return 'order-mismatch';
    }
    return null;
  }

  String? _validateRelations(
    SemanticDocument document,
    SetSemanticRelationsPatch patch,
  ) {
    final block = _blockById(document, patch.blockId);
    if (block == null) return 'unknown-block(${patch.blockId})';
    final ids = document.blocks.map((b) => b.id).toSet();
    for (final relation in patch.newRelations) {
      if (!ids.contains(relation.targetBlockId)) {
        return 'dangling-relation(${relation.targetBlockId})';
      }
    }
    return null;
  }

  String? _validatePreserve(
    SemanticDocument document,
    PreserveSemanticSourcesPatch patch,
  ) {
    for (final sourceId in patch.sourceIds) {
      final consumed = document.consumedSourceIds.contains(sourceId);
      final preserved = document.preservedSourceIds.contains(sourceId);
      final known =
          consumed ||
          preserved ||
          document.blocks.any((b) => b.sourceIds.contains(sourceId));
      if (!known) return 'unknown-source($sourceId)';
      if (patch.toPreserved && !consumed) return 'not-consumed($sourceId)';
      if (!patch.toPreserved && !preserved) {
        return 'not-preserved($sourceId)';
      }
    }
    return null;
  }

  static SemanticBlock? _blockById(SemanticDocument document, String blockId) {
    for (final block in document.blocks) {
      if (block.id == blockId) return block;
    }
    return null;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// apply 结果。
class SemanticPatchOutcome {
  const SemanticPatchOutcome._(this.document, this.inverse, this.rejection);

  const SemanticPatchOutcome.rejected(String reason)
    : this._(null, null, reason);

  const SemanticPatchOutcome.applied(
    SemanticDocument document,
    SemanticCorrectionPatch inverse,
  ) : this._(document, inverse, null);

  final SemanticDocument? document;
  final SemanticCorrectionPatch? inverse;
  final String? rejection;

  bool get accepted => document != null;
}

/// 语义 patch 应用器：校验→重建（revision+1）→逆 patch。
class SemanticPatchApplier {
  const SemanticPatchApplier({this.validator = const SemanticPatchValidator()});

  final SemanticPatchValidator validator;

  SemanticPatchOutcome apply(
    SemanticDocument document,
    SemanticCorrectionPatch patch,
  ) {
    final reason = validator.validate(document, patch);
    if (reason != null) {
      return SemanticPatchOutcome.rejected(reason);
    }
    final next = _rebuild(document, patch);
    return SemanticPatchOutcome.applied(next, _inverse(next, patch));
  }

  SemanticDocument _rebuild(
    SemanticDocument document,
    SemanticCorrectionPatch patch,
  ) {
    final bumped = _withRevision(document, document.revision + 1);
    return switch (patch) {
      SetSemanticRolePatch(:final blockId, :final toRole) => _copyWith(
        bumped,
        blocks: [
          for (final block in bumped.blocks)
            if (block.id == blockId)
              SemanticBlock(
                id: block.id,
                role: toRole,
                sourceIds: block.sourceIds,
                orderIndex: block.orderIndex,
                confidence: block.confidence,
                text: block.text,
                extras: block.extras,
              )
            else
              block,
        ],
      ),
      ReorderSemanticPatch(:final newOrder) => _copyWith(
        bumped,
        readingOrder: SemanticReadingOrder(orderedBlockIds: newOrder),
      ),
      SetSemanticRelationsPatch() => bumped, // 关系不影响文档核心字段（由冲突/重算消费）
      PreserveSemanticSourcesPatch(:final sourceIds, :final toPreserved) =>
        toPreserved
            ? _copyWith(
                bumped,
                consumedSourceIds: [
                  ...bumped.consumedSourceIds.where(
                    (id) => !sourceIds.contains(id),
                  ),
                ]..sort(),
                preservedSourceIds: [...bumped.preservedSourceIds, ...sourceIds]
                  ..sort(),
              )
            : _copyWith(
                bumped,
                consumedSourceIds: [...bumped.consumedSourceIds, ...sourceIds]
                  ..sort(),
                preservedSourceIds: [
                  ...bumped.preservedSourceIds.where(
                    (id) => !sourceIds.contains(id),
                  ),
                ]..sort(),
              ),
    };
  }

  SemanticCorrectionPatch _inverse(
    SemanticDocument next,
    SemanticCorrectionPatch patch,
  ) {
    final base = SemanticRevisionRef.of(next);
    return switch (patch) {
      SetSemanticRolePatch(:final blockId, :final fromRole, :final toRole) =>
        SetSemanticRolePatch(
          baseRevision: base,
          blockId: blockId,
          fromRole: toRole,
          toRole: fromRole,
        ),
      ReorderSemanticPatch(:final oldOrder, :final newOrder) =>
        ReorderSemanticPatch(
          baseRevision: base,
          oldOrder: newOrder,
          newOrder: oldOrder,
        ),
      SetSemanticRelationsPatch(
        :final blockId,
        :final oldRelations,
        :final newRelations,
      ) =>
        SetSemanticRelationsPatch(
          baseRevision: base,
          blockId: blockId,
          oldRelations: newRelations,
          newRelations: oldRelations,
        ),
      PreserveSemanticSourcesPatch(:final sourceIds, :final toPreserved) =>
        PreserveSemanticSourcesPatch(
          baseRevision: base,
          sourceIds: sourceIds,
          toPreserved: !toPreserved,
        ),
    };
  }

  static SemanticDocument _withRevision(SemanticDocument document, int value) =>
      _copyWith(document, revision: value);

  static SemanticDocument _copyWith(
    SemanticDocument document, {
    int? revision,
    List<SemanticBlock>? blocks,
    SemanticReadingOrder? readingOrder,
    List<String>? consumedSourceIds,
    List<String>? preservedSourceIds,
  }) => SemanticDocument(
    formatVersion: document.formatVersion,
    pageId: document.pageId,
    epoch: document.epoch,
    revision: revision ?? document.revision,
    fingerprint: document.fingerprint,
    blocks: blocks ?? document.blocks,
    readingOrder: readingOrder ?? document.readingOrder,
    conflicts: document.conflicts,
    consumedSourceIds: consumedSourceIds ?? document.consumedSourceIds,
    preservedSourceIds: preservedSourceIds ?? document.preservedSourceIds,
    readVersion: document.readVersion,
    extras: document.extras,
  );
}

/// 语义局部重算范围（V3-205A）：受影响块/稳定 source key 集合。
class SemanticRerunScope {
  SemanticRerunScope._(this.blockIds, this.sourceIds);

  /// 从 patch 序列计算重算范围；连续同块修正只保留最后一次（合并提交）。
  factory SemanticRerunScope.of(List<SemanticCorrectionPatch> patches) {
    final coalesced = SemanticRerunScope.coalesce(patches);
    final blocks = <String>{};
    for (final patch in coalesced) {
      blocks.addAll(_blocksOf(patch));
    }
    final sources = <String>{};
    // source 集合从块集合展开（调用方给文档上下文）。
    return SemanticRerunScope._(blocks, sources);
  }

  /// 计算完整 scope（含块→source 展开）。
  static SemanticRerunScope resolve(
    List<SemanticCorrectionPatch> patches,
    SemanticDocument document,
  ) {
    final base = SemanticRerunScope.of(patches);
    final sources = <String>{};
    for (final block in document.blocks) {
      if (base.blockIds.contains(block.id)) {
        sources.addAll(block.sourceIds);
      }
    }
    for (final patch in SemanticRerunScope.coalesce(patches)) {
      if (patch is PreserveSemanticSourcesPatch) {
        sources.addAll(patch.sourceIds);
      }
    }
    return SemanticRerunScope._(base.blockIds, sources);
  }

  /// 连续修正合并：同块连续 patch 只保留最后一次（仅提交最后一次
  /// operation 的语义）。不同块/不同种类互不吞并。
  static List<SemanticCorrectionPatch> coalesce(
    List<SemanticCorrectionPatch> patches,
  ) {
    final result = <SemanticCorrectionPatch>[];
    for (final patch in patches) {
      final key = _coalesceKey(patch);
      final previous = result.isEmpty ? null : result.last;
      if (previous != null && _coalesceKey(previous) == key) {
        result.removeLast();
      }
      result.add(patch);
    }
    return List.unmodifiable(result);
  }

  static String? _coalesceKey(SemanticCorrectionPatch patch) => switch (patch) {
    SetSemanticRolePatch(:final blockId) => 'set-role:$blockId',
    SetSemanticRelationsPatch(:final blockId) => 'set-relations:$blockId',
    ReorderSemanticPatch() => 'reorder',
    PreserveSemanticSourcesPatch() => 'preserve',
  };

  static Set<String> _blocksOf(SemanticCorrectionPatch patch) =>
      switch (patch) {
        SetSemanticRolePatch(:final blockId) => {blockId},
        SetSemanticRelationsPatch(:final blockId) => {blockId},
        ReorderSemanticPatch(:final newOrder) => newOrder.toSet(),
        PreserveSemanticSourcesPatch() => const {},
      };

  final Set<String> blockIds;

  /// 受影响稳定 source key（resolve 后有值；排序见 [stableSourceKeys]）。
  final Set<String> sourceIds;

  /// 稳定 source key：排序后的只读列表（跨端/跨次一致）。
  List<String> get stableSourceKeys =>
      List.unmodifiable(sourceIds.toList()..sort());
}
