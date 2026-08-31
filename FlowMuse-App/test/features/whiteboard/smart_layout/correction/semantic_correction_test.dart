import 'package:flow_muse/features/whiteboard/smart_layout/correction/semantic_correction.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SemanticDocument buildDocument() => SemanticDocument(
    formatVersion: 1,
    pageId: 'page-1',
    epoch: 0,
    revision: 4,
    fingerprint: '0123456789abcdef',
    blocks: [
      const SemanticBlock(
        id: 'g1',
        role: SemanticRole.title,
        sourceIds: ['text-1'],
        orderIndex: 0,
        confidence: 0.9,
        text: '标题',
      ),
      const SemanticBlock(
        id: 'g2',
        role: SemanticRole.figure,
        sourceIds: ['shape-1'],
        orderIndex: 1,
        confidence: 0.8,
      ),
      const SemanticBlock(
        id: 'g3',
        role: SemanticRole.unknown,
        sourceIds: ['ink-1', 'ink-2'],
        orderIndex: 2,
        confidence: 0.3,
      ),
    ],
    readingOrder: const SemanticReadingOrder(
      orderedBlockIds: ['g1', 'g2', 'g3'],
    ),
    conflicts: const [],
    consumedSourceIds: const ['shape-1', 'text-1'],
    preservedSourceIds: const ['ink-1', 'ink-2'],
  );

  group('SetSemanticRolePatch', () {
    test('apply/inverse 完整往返，revision 单调', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final result = applier.apply(
        doc,
        SetSemanticRolePatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'g2',
          fromRole: SemanticRole.figure,
          toRole: SemanticRole.caption,
        ),
      );
      expect(result.accepted, isTrue, reason: result.rejection ?? '');
      final next = result.document!;
      expect(
        next.blocks.firstWhere((b) => b.id == 'g2').role,
        SemanticRole.caption,
      );
      expect(next.revision, 5);

      final restored = applier.apply(next, result.inverse!);
      expect(restored.accepted, isTrue, reason: restored.rejection ?? '');
      final back = restored.document!;
      expect(
        back.blocks.firstWhere((b) => b.id == 'g2').role,
        SemanticRole.figure,
      );
      expect(back.revision, 6, reason: 'revision 单调递增，不回滚计数');
      // 其余字段与原文档一致（除 revision）。
      expect(back.pageId, doc.pageId);
      expect(back.consumedSourceIds, doc.consumedSourceIds);
    });

    test('role-mismatch 与 unknown-block 拒绝且零副作用', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final stale = applier.apply(
        doc,
        SetSemanticRolePatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'g2',
          fromRole: SemanticRole.body, // 实际是 figure
          toRole: SemanticRole.caption,
        ),
      );
      expect(stale.accepted, isFalse);
      expect(stale.rejection, 'role-mismatch(g2:figure)');
      expect(stale.document, isNull);

      final ghost = applier.apply(
        doc,
        SetSemanticRolePatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'ghost',
          fromRole: SemanticRole.body,
          toRole: SemanticRole.caption,
        ),
      );
      expect(ghost.rejection, 'unknown-block(ghost)');
    });
  });

  test('过期 revision：零副作用（stale-revision 拒绝）', () {
    final doc = buildDocument();
    final staleRef = SemanticRevisionRef(
      epoch: doc.epoch,
      revision: doc.revision - 1,
      fingerprint: doc.fingerprint,
    );
    const applier = SemanticPatchApplier();
    final result = applier.apply(
      doc,
      SetSemanticRolePatch(
        baseRevision: staleRef,
        blockId: 'g1',
        fromRole: SemanticRole.title,
        toRole: SemanticRole.body,
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.rejection, contains('stale-revision'));
    expect(doc.revision, 4, reason: '原文档不受任何影响');
  });

  group('ReorderSemanticPatch', () {
    test('合法重排 apply/inverse；非排列与 order-mismatch 拒绝', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final result = applier.apply(
        doc,
        ReorderSemanticPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          oldOrder: ['g1', 'g2', 'g3'],
          newOrder: ['g2', 'g1', 'g3'],
        ),
      );
      expect(result.accepted, isTrue, reason: result.rejection ?? '');
      expect(result.document!.readingOrder.orderedBlockIds, ['g2', 'g1', 'g3']);
      final restored = applier.apply(result.document!, result.inverse!);
      expect(restored.document!.readingOrder.orderedBlockIds, [
        'g1',
        'g2',
        'g3',
      ]);

      final notPermutation = applier.apply(
        doc,
        ReorderSemanticPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          oldOrder: ['g1', 'g2', 'g3'],
          newOrder: ['g1', 'g2'],
        ),
      );
      expect(notPermutation.rejection, 'not-a-permutation');

      final mismatch = applier.apply(
        doc,
        ReorderSemanticPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          oldOrder: ['g3', 'g2', 'g1'],
          newOrder: ['g3', 'g1', 'g2'],
        ),
      );
      expect(mismatch.rejection, 'order-mismatch');
    });
  });

  group('SetSemanticRelationsPatch', () {
    test('目标存在放行；悬空目标拒绝', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final ok = applier.apply(
        doc,
        SetSemanticRelationsPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'g3',
          oldRelations: const [],
          newRelations: const [(type: 'captionOf', targetBlockId: 'g2')],
        ),
      );
      expect(ok.accepted, isTrue, reason: ok.rejection ?? '');
      final inverseBack = applier.apply(ok.document!, ok.inverse!);
      expect(inverseBack.accepted, isTrue);

      final dangling = applier.apply(
        doc,
        SetSemanticRelationsPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'g3',
          oldRelations: const [],
          newRelations: const [(type: 'captionOf', targetBlockId: 'ghost')],
        ),
      );
      expect(dangling.rejection, 'dangling-relation(ghost)');
    });
  });

  group('PreserveSemanticSourcesPatch', () {
    test('consumed→preserved：ledger 守恒保持；逆 patch 可还原', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final result = applier.apply(
        doc,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['shape-1'],
          toPreserved: true,
        ),
      );
      expect(result.accepted, isTrue, reason: result.rejection ?? '');
      final next = result.document!;
      expect(next.consumedSourceIds, ['text-1']);
      expect(next.preservedSourceIds, ['ink-1', 'ink-2', 'shape-1']);
      expect(next.ledgerConserved, isTrue);

      final restored = applier.apply(next, result.inverse!);
      expect(restored.accepted, isTrue, reason: restored.rejection ?? '');
      expect(restored.document!.consumedSourceIds, ['shape-1', 'text-1']);
    });

    test('已是 preserved 的 source 拒绝（not-consumed）', () {
      final doc = buildDocument();
      const applier = SemanticPatchApplier();
      final result = applier.apply(
        doc,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['ink-1'],
          toPreserved: true,
        ),
      );
      expect(result.rejection, 'not-consumed(ink-1)');
    });
  });

  group('coalesce 与 SemanticRerunScope', () {
    test('连续同块修正只保留最后一次；不同块互不吞并', () {
      final doc = buildDocument();
      final ref = SemanticRevisionRef.of(doc);
      final coalesced = SemanticRerunScope.coalesce([
        SetSemanticRolePatch(
          baseRevision: ref,
          blockId: 'g1',
          fromRole: SemanticRole.title,
          toRole: SemanticRole.body,
        ),
        SetSemanticRolePatch(
          baseRevision: ref,
          blockId: 'g1',
          fromRole: SemanticRole.body,
          toRole: SemanticRole.list,
        ),
        SetSemanticRolePatch(
          baseRevision: ref,
          blockId: 'g2',
          fromRole: SemanticRole.figure,
          toRole: SemanticRole.caption,
        ),
      ]);
      expect(coalesced.length, 2, reason: 'g1 的两连修合并为最后一次');
      final first = coalesced[0] as SetSemanticRolePatch;
      expect(first.blockId, 'g1');
      expect(first.toRole, SemanticRole.list, reason: '只提交最后一次 operation 的语义');
      expect((coalesced[1] as SetSemanticRolePatch).blockId, 'g2');
    });

    test('scope 稳定 source keys：排序、含 preserve 展开、与全量 diff 等价', () {
      final doc = buildDocument();
      final ref = SemanticRevisionRef.of(doc);
      final patches = [
        SetSemanticRolePatch(
          baseRevision: ref,
          blockId: 'g3',
          fromRole: SemanticRole.unknown,
          toRole: SemanticRole.formula,
        ),
        PreserveSemanticSourcesPatch(
          baseRevision: ref,
          sourceIds: const ['text-1'],
          toPreserved: true,
        ),
      ];
      final scope = SemanticRerunScope.resolve(patches, doc);
      expect(scope.blockIds, {'g3'});
      expect(scope.stableSourceKeys, [
        'ink-1',
        'ink-2',
        'text-1',
      ], reason: '块 sources + preserve 展开，排序稳定');

      // 局部与全量等价：把 patches 全部应用后，内容发生变化的块集合
      // 与 scope.blockIds 完全一致。
      var current = doc;
      const applier = SemanticPatchApplier();
      for (final patch in SemanticRerunScope.coalesce(patches)) {
        // 连续修正逐个落地：基线随文档演进重建（结构校验仍严格）。
        final rebased = _rebase(patch, current);
        final outcome = applier.apply(current, rebased);
        expect(outcome.accepted, isTrue, reason: outcome.rejection ?? '');
        current = outcome.document!;
      }
      final changedBlocks = <String>{};
      for (final before in doc.blocks) {
        final after = current.blocks.firstWhere((b) => b.id == before.id);
        if (after != before) {
          changedBlocks.add(before.id);
        }
      }
      if (current.readingOrder != doc.readingOrder) {
        changedBlocks.addAll(current.readingOrder.orderedBlockIds);
      }
      // preserve 引起 ledger 变化 → 其所属块 g1 计入。
      changedBlocks.add('g1');
      expect(
        changedBlocks,
        scope.blockIds.union({'g1'}),
        reason: '局部 scope 与全量 diff 的受影响块一致',
      );
      expect(
        scope.stableSourceKeys,
        SemanticRerunScope.resolve(patches, doc).stableSourceKeys,
        reason: '稳定 key 重复计算一致',
      );
    });
  });
}

SemanticCorrectionPatch _rebase(
  SemanticCorrectionPatch patch,
  SemanticDocument document,
) {
  final base = SemanticRevisionRef.of(document);
  return switch (patch) {
    SetSemanticRolePatch() => SetSemanticRolePatch(
      baseRevision: base,
      blockId: patch.blockId,
      fromRole: patch.fromRole,
      toRole: patch.toRole,
    ),
    ReorderSemanticPatch() => ReorderSemanticPatch(
      baseRevision: base,
      oldOrder: patch.oldOrder,
      newOrder: patch.newOrder,
    ),
    SetSemanticRelationsPatch() => SetSemanticRelationsPatch(
      baseRevision: base,
      blockId: patch.blockId,
      oldRelations: patch.oldRelations,
      newRelations: patch.newRelations,
    ),
    PreserveSemanticSourcesPatch() => PreserveSemanticSourcesPatch(
      baseRevision: base,
      sourceIds: patch.sourceIds,
      toPreserved: patch.toPreserved,
    ),
  };
}
