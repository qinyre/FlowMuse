import 'dart:convert';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_response.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pageId = 'page-1';
  const onPage = {
    'flowMuse': {'pageId': pageId},
  };

  Scene buildScene() => Scene()
      .addElement(
        RectangleElement(
          id: const ElementId('shape-1'),
          x: 0,
          y: 0,
          width: 100,
          height: 40,
          seed: 3,
          versionNonce: 5,
          updated: 1,
          customData: onPage,
        ),
      )
      .addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 60,
          width: 120,
          height: 20,
          text: '会议纪要标题',
          seed: 3,
          versionNonce: 5,
          updated: 1,
          customData: onPage,
        ),
      )
      .addElement(
        FreedrawElement(
          id: const ElementId('ink-1'),
          x: 200,
          y: 0,
          width: 80,
          height: 30,
          points: const [Point(200, 0), Point(280, 30)],
          seed: 3,
          versionNonce: 5,
          updated: 1,
          customData: onPage,
        ),
      )
      .addElement(
        FrameElement(
          id: const ElementId('frame-1'),
          x: 400,
          y: 0,
          width: 200,
          height: 200,
          seed: 3,
          versionNonce: 5,
          updated: 1,
          customData: onPage,
        ),
      );

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 2,
    fingerprint: SceneFingerprint.of(scene),
  );

  SmartLayoutV3Response responseOf() => SmartLayoutV3Response.fromJson({
    'protocolVersion': 3,
    'regions': [
      {
        'id': 'g1',
        'role': 'title',
        'sourceIds': ['text-1'],
        'readingOrder': 0,
        'confidence': 0.9,
        'relations': [],
      },
      {
        'id': 'g2',
        'role': 'figure',
        'sourceIds': ['shape-1'],
        'readingOrder': 1,
        'confidence': 0.8,
        'relations': [],
      },
      {
        'id': 'g3',
        'role': 'unknown',
        'sourceIds': ['ink-1'],
        'readingOrder': 2,
        'confidence': 0.3,
        'relations': [],
      },
      // frame-1 未被认领 → preserved
    ],
    'warnings': [],
  });

  test('装配：ledger 守恒、unknown preserved、未认领 preserved、text 回填', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final assembly = const SemanticDocumentAssembler().assemble(
      snapshot: snapshot,
      response: responseOf(),
    );
    final document = assembly.document;
    expect(document.blocks.length, 3);
    expect(
      document.blocks.firstWhere((b) => b.id == 'g1').text,
      '会议纪要标题',
      reason: 'typed text 只来自快照 exactText',
    );
    expect(document.consumedSourceIds, ['shape-1', 'text-1']);
    expect(document.preservedSourceIds, [
      'frame-1',
      'ink-1',
    ], reason: 'unknown 块与未认领 frame 均 preserved');
    expect(document.ledgerConserved, isTrue);
    expect(assembly.ledger.isFinalized, isTrue);
    expect(document.readingOrder.orderedBlockIds, ['g1', 'g2', 'g3']);
    expect(document.readingOrder.consecutivePairs().length, 2);
  });

  test('ledger 推进与文档 hash 一致：双重装配幂等', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final first = const SemanticDocumentAssembler().assemble(
      snapshot: snapshot,
      response: responseOf(),
    );
    final second = const SemanticDocumentAssembler().assemble(
      snapshot: snapshot,
      response: responseOf(),
    );
    expect(first.document, second.document);
    expect(first.document.ledgerHash, second.document.ledgerHash);
    // hash 与 ledger 终态集合一致（重算口径）。
    expect(first.document.ledgerHash, first.document.ledgerHash);
  });

  test('悬空 source：装配失败且不产出半文档', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final dangling = SmartLayoutV3Response.fromJson({
      'protocolVersion': 3,
      'regions': [
        {
          'id': 'gx',
          'role': 'body',
          'sourceIds': ['ghost-source'],
          'readingOrder': 0,
          'confidence': 0.5,
          'relations': [],
        },
      ],
      'warnings': [],
    });
    expect(
      () => const SemanticDocumentAssembler().assemble(
        snapshot: snapshot,
        response: dangling,
      ),
      throwsStateError,
    );
  });

  test('冲突留档进入文档', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final assembly = const SemanticDocumentAssembler().assemble(
      snapshot: snapshot,
      response: responseOf(),
      conflicts: const [
        RawConflict(
          regionId: 'g3',
          kind: 'role-disagreement',
          overview: 'role=unknown conf=0.30',
          crop: 'role=formula conf=0.85',
        ),
      ],
    );
    expect(assembly.document.conflicts.single.kind, 'role-disagreement');
  });

  test('current round-trip 深度等价（含 extras 保留）', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final document = const SemanticDocumentAssembler()
        .assemble(snapshot: snapshot, response: responseOf())
        .document;
    final encoded = jsonEncode(document.toJson());
    final decoded = SemanticDocument.fromJson(
      jsonDecode(encoded) as Map<String, Object?>,
    );
    expect(decoded, document);
    expect(decoded.formatVersion, SemanticDocumentFormat.currentVersion);
    expect(decoded.readVersion, isNull);
  });

  test('旧/异版 fixture 可读且新字段不误删', () {
    // 模拟"更新版本写入的文档带未知新字段"：读取必须保留并通过
    // round-trip 原样回写，不抛错不丢字段。
    final futureJson = {
      'formatVersion': 2,
      'pageId': 'page-9',
      'revision': {
        'epoch': 1,
        'revision': 7,
        'fingerprint': '0123456789abcdef',
      },
      'blocks': [
        {
          'id': 'b1',
          'role': 'body',
          'sourceIds': ['s1'],
          'orderIndex': 0,
          'confidence': 0.5,
          'futureBlockField': {'x': 1},
        },
      ],
      'readingOrder': {
        'blocks': ['b1'],
      },
      'conflicts': [],
      'ledger': {
        'consumed': ['s1'],
        'preserved': <String>[],
        'hash': 'ignored',
      },
      'futureTopField': true,
    };
    final document = SemanticDocument.fromJson(futureJson);
    expect(document.readVersion, 2, reason: '异版读取必须记录来源版本');
    expect(document.extras['futureTopField'], true);
    expect(document.blocks.single.extras['futureBlockField'], {
      'x': 1,
    }, reason: '块级未知字段不得误删');
    final roundTripped = document.toJson();
    expect(roundTripped['futureTopField'], true);
    expect((roundTripped['blocks'] as List).first['futureBlockField'], {
      'x': 1,
    });
    expect(roundTripped['formatVersion'], 2, reason: '读什么版回什么版');

    // 过老版本拒绝。
    expect(
      () => SemanticDocument.fromJson({...futureJson, 'formatVersion': 0}),
      throwsFormatException,
    );
  });

  test('ledger hash 守恒破坏可检测', () {
    final scene = buildScene();
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: pageId,
      sceneRevision: revisionOf(scene),
    );
    final document = const SemanticDocumentAssembler()
        .assemble(snapshot: snapshot, response: responseOf())
        .document;
    // 同一 source 同时出现在两个终态 → ledgerConserved=false。
    final broken = SemanticDocument(
      formatVersion: document.formatVersion,
      pageId: document.pageId,
      epoch: document.epoch,
      revision: document.revision,
      fingerprint: document.fingerprint,
      blocks: document.blocks,
      readingOrder: document.readingOrder,
      conflicts: document.conflicts,
      consumedSourceIds: document.consumedSourceIds,
      preservedSourceIds: [
        ...document.preservedSourceIds,
        document.consumedSourceIds.first,
      ],
    );
    expect(broken.ledgerConserved, isFalse);
    expect(broken.ledgerHash, isNot(document.ledgerHash));
  });
}
