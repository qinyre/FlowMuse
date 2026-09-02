import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show ImageCrop, Scene;
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// V3-400A：block 组装、ledger 守恒、文本三态、图片比例、关系原子性。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // V3-300A 同口径：关闭 GoogleFonts 运行时抓取（无网络回退度量）。
  GoogleFonts.config.allowRuntimeFetching = false;

  const assembler = LayoutBlockAssembler();
  final measure = TextMeasureAdapter();

  SnapshotBounds b(double l, double t, double w, double h) =>
      SnapshotBounds(left: l, top: t, width: w, height: h);

  SnapshotObject imageObject(
    String id, {
    String fileId = 'file-1',
    SnapshotBounds? intrinsic,
    ImageCrop? crop,
    SnapshotMobility mobility = SnapshotMobility.movable,
  }) =>
      SnapshotObject(
        sourceId: id,
        kind: 'image',
        bounds: b(0, 0, 200, 100),
        visualBounds: b(0, 0, 200, 100),
        rotation: 0,
        mobility: mobility,
        groupIds: const [],
        frameId: null,
        bindingRefs: const [],
        zIndex: 0,
        memberIds: const [],
        fileId: fileId,
        imageCrop: crop,
        imageIntrinsicSize: intrinsic,
      );

  SnapshotObject lockedObject(String id) => SnapshotObject(
        sourceId: id,
        kind: 'rectangle',
        bounds: b(500, 500, 40, 30),
        visualBounds: b(500, 500, 40, 30),
        rotation: 0,
        mobility: SnapshotMobility.protectedObstacle,
        groupIds: const [],
        frameId: null,
        bindingRefs: const [],
        zIndex: 0,
        memberIds: const [],
      );

  SemanticDocument doc({
    required List<SemanticBlock> blocks,
    required List<String> consumed,
    required List<String> preserved,
    List<String>? readingOrder,
  }) =>
      SemanticDocument(
        formatVersion: 1,
        pageId: 'p1',
        epoch: 0,
        revision: 1,
        fingerprint: 'fp',
        blocks: blocks,
        readingOrder: SemanticReadingOrder(
          orderedBlockIds: readingOrder ?? [for (final x in blocks) x.id],
        ),
        conflicts: const [],
        consumedSourceIds: consumed,
        preservedSourceIds: preserved,
      );

  SemanticBlock sb(
    String id,
    SemanticRole role,
    List<String> sources, {
    String? text,
    int orderIndex = 0,
    Map<String, Object?> extras = const {},
  }) =>
      SemanticBlock(
        id: id,
        role: role,
        sourceIds: sources,
        orderIndex: orderIndex,
        confidence: 0.9,
        text: text,
        extras: extras,
      );

  final revision = SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(Scene()),
  );

  LayoutPageSnapshot snapshot({
    List<SnapshotObject> objects = const [],
    List<SnapshotRenderAsset> assets = const [],
    List<String> allSourceIds = const [],
  }) =>
      LayoutPageSnapshot(
        pageId: 'p1',
        pageBounds: null,
        contentBounds: null,
        sceneRevision: revision,
        objects: objects,
        inkStrokes: const [],
        renderAssets: assets,
        sourceCoverage: SourceCoverageLedger.pending(
          [
            for (final o in objects) o.sourceId,
            ...allSourceIds,
          ],
        ),
      );

  test('role→kind 全映射与阅读序透传', () {
    final document = doc(
      blocks: [
        sb('b1', SemanticRole.title, ['s1'], text: '标题', orderIndex: 0),
        sb('b2', SemanticRole.body, ['s2'], text: '段落', orderIndex: 1),
        sb('b3', SemanticRole.list, ['s3'], text: '一、条目', orderIndex: 2),
        sb('b4', SemanticRole.figure, ['img-1'], orderIndex: 3),
        sb('b5', SemanticRole.caption, ['s5'], text: '图注', orderIndex: 4),
        sb('b6', SemanticRole.formula, ['s6'], text: 'a+b=c', orderIndex: 5),
        sb('b7', SemanticRole.table, ['s7'], orderIndex: 6),
        sb('b8', SemanticRole.unknown, ['s8'], orderIndex: 7),
      ],
      consumed: ['s1', 's2', 's3', 'img-1', 's5', 's6', 's7'],
      preserved: ['s8'],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(
        objects: [
          imageObject('img-1', intrinsic: b(0, 0, 400, 200)),
          SnapshotObject(
            sourceId: 's8',
            kind: 'future-widget',
            bounds: b(9, 9, 9, 9),
            visualBounds: b(9, 9, 9, 9),
            rotation: 0,
            mobility: SnapshotMobility.movable,
            groupIds: const [],
            frameId: null,
            bindingRefs: const [],
            zIndex: 0,
            memberIds: const [],
          ),
        ],
      ),
      measure: measure,
    );
    final kinds = {
      for (final block in assembly.blocks) block.id: block.kind,
    };
    expect(kinds['b1'], LayoutBlockKind.title);
    expect(kinds['b2'], LayoutBlockKind.paragraph);
    expect(kinds['b3'], LayoutBlockKind.list);
    expect(kinds['b4'], LayoutBlockKind.figure);
    expect(kinds['b5'], LayoutBlockKind.caption);
    expect(kinds['b6'], LayoutBlockKind.formula);
    expect(kinds['b7'], LayoutBlockKind.table);
    expect(kinds['b8'], LayoutBlockKind.preserved,
        reason: 'unknown 一律 preserved 语义');
    // 阅读序：blocks 按 readingOrder 排列。
    expect(
      assembly.blocks.map((x) => x.id).toList(),
      ['b1', 'b2', 'b3', 'b4', 'b5', 'b6', 'b7', 'b8'],
    );
    expect(assembly.ledgerConserved, isTrue);
  });

  test('文本三态：typed / transcribed / 无文本不造数据', () {
    final document = doc(
      blocks: [
        sb('t1', SemanticRole.body, ['s1'], text: '来自快照'),
        sb('t2', SemanticRole.body, ['s2'],
            extras: {'transcribedText': '模型转写'}),
        sb('t3', SemanticRole.body, ['s3']),
      ],
      consumed: ['s1', 's2', 's3'],
      preserved: const [],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(),
      measure: measure,
    );
    final byId = {
      for (final block in assembly.blocks) block.id: block,
    };
    expect(byId['t1']!.textOrigin, LayoutTextOrigin.typed);
    expect(byId['t1']!.text!.text, '来自快照');
    expect(byId['t2']!.textOrigin, LayoutTextOrigin.transcribed);
    expect(byId['t2']!.text!.text, '模型转写');
    expect(byId['t3']!.text, isNull, reason: '无文本不造数据');
    expect(byId['t3']!.measuredIntrinsic, isNull);
    expect(byId['t3']!.sourceRefs, ['s3'], reason: '源仍守恒不丢块');
    expect(assembly.ledgerConserved, isTrue);
  });

  test('真实测量接入：typed 块 intrinsic 来自 TextMeasureAdapter（宽>0）',
      () {
    final document = doc(
      blocks: [sb('p1', SemanticRole.body, ['s1'], text: '宽度必为真实测量')],
      consumed: ['s1'],
      preserved: const [],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(),
      measure: measure,
    );
    final intrinsic = assembly.blocks.single.measuredIntrinsic!;
    expect(intrinsic.width, greaterThan(0), reason: '真实 TextPainter 度量');
    expect(intrinsic.height, greaterThan(0));
    expect(intrinsic.lineCount, greaterThan(0));
    // 同文本同参数复测（缓存路径）一致性。
    final again = measure.measure(
      text: '宽度必为真实测量',
      fontFamily: assembly.blocks.single.text!.fontFamily,
      fontSize: assembly.blocks.single.text!.fontSize,
      lineHeight: assembly.blocks.single.text!.lineHeight,
    );
    expect(again.width, intrinsic.width);
  });

  test('图片比例：intrinsic×crop 显示比 + 资产缺失事实', () {
    final document = doc(
      blocks: [sb('f1', SemanticRole.figure, ['img-1'])],
      consumed: ['img-1'],
      preserved: const [],
    );
    // intrinsic 800×400，crop 半幅 0.5×1 → 显示比 400/400 = 1.0。
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(
        objects: [
          imageObject(
            'img-1',
            fileId: 'file-missing',
            intrinsic: b(0, 0, 800, 400),
            crop: const ImageCrop(width: 0.5, height: 1),
          ),
        ],
      ),
      measure: measure,
    );
    final figure = assembly.blocks.single;
    expect(figure.figure!.displayAspectRatio, closeTo(1.0, 1e-9));
    expect(figure.figure!.missingAsset, isTrue, reason: '资产缺失如实记录');

    // resolved 资产：missingAsset=false。
    final resolvedAssembly = assembler.assemble(
      document: doc(
        blocks: [sb('f2', SemanticRole.figure, ['img-2'])],
        consumed: ['img-2'],
        preserved: const [],
      ),
      snapshot: snapshot(
        objects: [imageObject('img-2', fileId: 'file-ok', intrinsic: b(0, 0, 800, 400))],
        assets: [
          SnapshotRenderAsset(
            fileId: 'file-ok',
            ownerSourceId: 'img-2',
            status: SnapshotRenderAssetStatus.resolved,
            mimeType: 'image/png',
            byteLength: 10,
          ),
        ],
      ),
      measure: measure,
    );
    expect(resolvedAssembly.blocks.single.figure!.missingAsset, isFalse);
    expect(
      resolvedAssembly.blocks.single.figure!.displayAspectRatio,
      closeTo(2.0, 1e-9),
    );
  });

  test('caption 绑定 figure + 标题 keepWith 后继（关系原子性）', () {
    final document = doc(
      blocks: [
        sb('title-1', SemanticRole.title, ['s1'], text: '章节', orderIndex: 0),
        sb('para-1', SemanticRole.body, ['s2'], text: '首段', orderIndex: 1),
        sb('fig-1', SemanticRole.figure, ['img-1'], orderIndex: 2),
        sb('cap-1', SemanticRole.caption, ['s3'], text: '图 1', orderIndex: 3),
      ],
      consumed: ['s1', 's2', 'img-1', 's3'],
      preserved: const [],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(
        objects: [imageObject('img-1', intrinsic: b(0, 0, 400, 200))],
      ),
      measure: measure,
    );
    expect(
      assembly.relationships,
      containsAll([
        const BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'title-1',
          toBlockId: 'para-1',
        ),
        const BlockRelationship(
          kind: BlockRelationKind.captionOf,
          fromBlockId: 'cap-1',
          toBlockId: 'fig-1',
        ),
      ]),
    );
    // 原子组：{title-1, para-1} 与 {fig-1, cap-1}（figure 自身 keepTogether
    // 与 caption 关系并成一组）。
    final groups = assembly.atomicGroups;
    expect(groups, containsAll([
      containsAll(['title-1', 'para-1']),
      containsAll(['fig-1', 'cap-1']),
    ]));
  });

  test('protected 障碍投影 + ledger preserved 态复核 fail closed', () {
    final document = doc(
      blocks: [sb('p1', SemanticRole.body, ['s1'], text: '正文')],
      consumed: ['s1'],
      preserved: ['lock-1'],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(objects: [lockedObject('lock-1')]),
      measure: measure,
    );
    final protected = assembly.blocks
        .where((x) => x.kind == LayoutBlockKind.protected)
        .toList();
    expect(protected, hasLength(1));
    expect(protected.single.id, 'protected-lock-1');
    expect(protected.single.sourceRefs, ['lock-1']);
    expect(protected.single.keepTogether, isTrue);
    expect(assembly.ledgerConserved, isTrue);

    // 锁定物被标记 consumed → fail closed。
    expect(
      () => assembler.assemble(
        document: doc(
          blocks: [sb('p1', SemanticRole.body, ['s1'], text: 'x')],
          consumed: ['s1', 'lock-1'],
          preserved: const [],
        ),
        snapshot: snapshot(objects: [lockedObject('lock-1')]),
        measure: measure,
      ),
      throwsStateError,
      reason: '锁定物不可被消费',
    );
  });

  test('ledger 守恒 fail closed：重叠/遗漏即抛', () {
    // 语义块 sourceIds 重叠（同源两个块）。
    expect(
      () => assembler.assemble(
        document: doc(
          blocks: [
            sb('a', SemanticRole.body, ['s1'], text: 'x'),
            sb('b', SemanticRole.body, ['s1'], text: 'y'),
          ],
          consumed: ['s1'],
          preserved: const [],
        ),
        snapshot: snapshot(),
        measure: measure,
      ),
      throwsStateError,
      reason: '重复 sourceRefs',
    );
    // 块没覆盖 ledger 的某源。
    expect(
      () => assembler.assemble(
        document: doc(
          blocks: [sb('a', SemanticRole.body, ['s1'], text: 'x')],
          consumed: ['s1', 's2'],
          preserved: const [],
        ),
        snapshot: snapshot(),
        measure: measure,
      ),
      throwsStateError,
      reason: 'ledger 源遗漏',
    );
  });

  test('unknown extras 原样透传不丢失', () {
    final document = doc(
      blocks: [
        sb('u1', SemanticRole.unknown, ['s1'],
            extras: {'futureField': {'nested': 1}}),
      ],
      consumed: const [],
      preserved: ['s1'],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(),
      measure: measure,
    );
    final block = assembly.blocks.single;
    expect(block.kind, LayoutBlockKind.preserved);
    expect(block.extras['futureField'], {
      'nested': 1,
    }, reason: '未知字段逐位保留');
  });

  test('formula/table 块级 keepTogether', () {
    final document = doc(
      blocks: [
        sb('fx', SemanticRole.formula, ['s1'], text: 'E=mc^2'),
        sb('tb', SemanticRole.table, ['s2']),
      ],
      consumed: ['s1', 's2'],
      preserved: const [],
    );
    final assembly = assembler.assemble(
      document: document,
      snapshot: snapshot(),
      measure: measure,
    );
    final byId = {
      for (final block in assembly.blocks) block.id: block,
    };
    expect(byId['fx']!.keepTogether, isTrue);
    expect(byId['tb']!.keepTogether, isTrue);
  });
}
