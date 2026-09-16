import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/correction/semantic_correction.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';

/// §9.2 语义纠错闭环（R6 修复）：
/// - SetSemanticRelationsPatch 真正写入关系（不再是空操作）；
/// - PreserveSemanticSourcesPatch 同步块角色 + previousRole 可逆；
/// - 逆操作同链（经同一 validator），不绕过替换准入。
void main() {
  SemanticDocument buildDocument() => SemanticDocument(
    formatVersion: 1,
    pageId: 'page-1',
    epoch: 0,
    revision: 4,
    fingerprint: '0123456789abcdef',
    blocks: [
      const SemanticBlock(
        id: 'cap-1',
        role: SemanticRole.caption,
        sourceIds: ['ink-cap'],
        orderIndex: 0,
        confidence: 0.8,
        extras: {'transcribedText': '图1 架构'},
      ),
      const SemanticBlock(
        id: 'fig-1',
        role: SemanticRole.figure,
        sourceIds: ['img-1'],
        orderIndex: 1,
        confidence: 1,
      ),
      const SemanticBlock(
        id: 'body-1',
        role: SemanticRole.body,
        sourceIds: ['ink-1', 'ink-2'],
        orderIndex: 2,
        confidence: 0.9,
        extras: {'transcribedText': '正文'},
      ),
    ],
    readingOrder: const SemanticReadingOrder(
      orderedBlockIds: ['cap-1', 'fig-1', 'body-1'],
    ),
    conflicts: const [],
    consumedSourceIds: const ['img-1', 'ink-1', 'ink-2', 'ink-cap'],
    preservedSourceIds: const [],
  );

  const applier = SemanticPatchApplier();

  group('SetSemanticRelationsPatch 闭环', () {
    test('图注改绑生效：关系写入块 extras 并可读回', () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        SetSemanticRelationsPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'cap-1',
          oldRelations: const [],
          newRelations: const [(type: 'captionOf', targetBlockId: 'fig-1')],
        ),
      );
      expect(outcome.accepted, isTrue, reason: outcome.rejection ?? '');
      final relations = outcome.document!.blocks
          .firstWhere((b) => b.id == 'cap-1')
          .extras['relations'] as List<Object?>;
      expect(relations, hasLength(1));
      final relation = Map<String, Object?>.from(relations.single as Map);
      expect(relation['type'], 'captionOf');
      expect(relation['targetBlockId'], 'fig-1');
      expect(outcome.document!.revision, 5);
    });

    test('悬空目标拒绝（dangling relation）', () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        SetSemanticRelationsPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'cap-1',
          oldRelations: const [],
          newRelations: const [(type: 'captionOf', targetBlockId: 'ghost')],
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejection, contains('dangling-relation'));
    });

    test('逆操作恢复旧关系（同链：经同一 validator）', () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        SetSemanticRelationsPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          blockId: 'cap-1',
          oldRelations: const [],
          newRelations: const [(type: 'captionOf', targetBlockId: 'fig-1')],
        ),
      );
      final undone = applier.apply(outcome.document!, outcome.inverse!);
      expect(undone.accepted, isTrue, reason: undone.rejection ?? '');
      final relations = undone.document!.blocks
          .firstWhere((b) => b.id == 'cap-1')
          .extras['relations'] as List<Object?>?;
      expect(relations, isEmpty);
      expect(undone.document!.revision, 6);
    });
  });

  group('PreserveSemanticSourcesPatch 闭环', () {
    test('保留后原件不动：块角色降 unknown + previousRole 留档 + 账目搬移',
        () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['ink-1', 'ink-2'],
          toPreserved: true,
        ),
      );
      expect(outcome.accepted, isTrue, reason: outcome.rejection ?? '');
      final next = outcome.document!;
      final block = next.blocks.firstWhere((b) => b.id == 'body-1');
      expect(block.role, SemanticRole.unknown, reason: '保留语义不进排版流');
      expect(block.extras['previousRole'], 'body');
      expect(block.text, isNull);
      expect(next.consumedSourceIds, ['img-1', 'ink-cap']);
      expect(next.preservedSourceIds, ['ink-1', 'ink-2']);
      expect(next.ledgerConserved, isTrue);
    });

    test('已 unknown 的块保留不覆盖 previousRole', () {
      final doc = SemanticDocument(
        formatVersion: 1,
        pageId: 'page-1',
        epoch: 0,
        revision: 4,
        fingerprint: '0123456789abcdef',
        blocks: [
          const SemanticBlock(
            id: 'u-1',
            role: SemanticRole.unknown,
            sourceIds: ['ink-u'],
            orderIndex: 0,
            confidence: 0.2,
            extras: {'previousRole': 'caption'},
          ),
        ],
        readingOrder: const SemanticReadingOrder(orderedBlockIds: ['u-1']),
        conflicts: const [],
        consumedSourceIds: const ['ink-u'],
        preservedSourceIds: const [],
      );
      final outcome = applier.apply(
        doc,
        const PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef(
            epoch: 0,
            revision: 4,
            fingerprint: '0123456789abcdef',
          ),
          sourceIds: ['ink-u'],
          toPreserved: true,
        ),
      );
      expect(outcome.accepted, isTrue, reason: outcome.rejection ?? '');
      expect(
        outcome.document!.blocks.first.extras['previousRole'],
        'caption',
        reason: '二次保留不得吞掉更早的角色留档',
      );
    });

    test('逆操作恢复角色与账目；不绕过替换准入（同 validator）', () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['ink-1', 'ink-2'],
          toPreserved: true,
        ),
      );
      final undone = applier.apply(outcome.document!, outcome.inverse!);
      expect(undone.accepted, isTrue, reason: undone.rejection ?? '');
      final back = undone.document!;
      final block = back.blocks.firstWhere((b) => b.id == 'body-1');
      expect(block.role, SemanticRole.body, reason: 'previousRole 恢复');
      expect(block.extras.containsKey('previousRole'), isFalse);
      expect(back.consumedSourceIds, containsAll(['ink-1', 'ink-2']));
      expect(back.preservedSourceIds, isEmpty);
      // 再次撤销保留（非 preserved 终态）必须被同一 validator 拒绝——
      // 逆操作链不因"是逆"而获得豁免。
      final stale = applier.apply(
        back,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(back),
          sourceIds: const ['ink-1', 'ink-2'],
          toPreserved: false,
        ),
      );
      expect(stale.accepted, isFalse);
      expect(stale.rejection, contains('not-preserved'));
    });

    test('部分块保留拒绝（整块语义，§9.2）', () {
      final doc = buildDocument();
      final outcome = applier.apply(
        doc,
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['ink-1'],
          toPreserved: true,
        ),
      );
      expect(outcome.accepted, isFalse);
      expect(outcome.rejection, contains('partial-block-preserve'));
    });
  });

  group('重算范围（§9.2 保留触块进入 rerun scope）', () {
    test('resolve 含保留触块与展开源', () {
      final doc = buildDocument();
      final scope = SemanticRerunScope.resolve([
        PreserveSemanticSourcesPatch(
          baseRevision: SemanticRevisionRef.of(doc),
          sourceIds: const ['ink-1', 'ink-2'],
          toPreserved: true,
        ),
      ], doc);
      expect(scope.blockIds, contains('body-1'));
      expect(scope.stableSourceKeys, ['ink-1', 'ink-2']);
    });
  });
}
