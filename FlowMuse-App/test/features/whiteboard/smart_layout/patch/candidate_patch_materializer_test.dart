import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/candidate_patch_materializer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/scene_patch_debug_codec.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_patch_equality.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_patch_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextElement typedText(String id, {double x = 100, double fontSize = 28}) =>
      TextElement(
        id: ElementId(id),
        x: x,
        y: 50,
        width: 200,
        height: 40,
        text: 'typed 标题',
        fontSize: fontSize,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: 1,
      );

  FreedrawElement ink(String id, {double x = 300}) => FreedrawElement(
    id: ElementId(id),
    x: x,
    y: 300,
    width: 160,
    height: 60,
    points: const [Point(0, 0), Point(160, 60)],
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: 1,
  );

  ImageElement figure(String id, String fileId) => ImageElement(
    id: ElementId(id),
    x: 500,
    y: 100,
    width: 120,
    height: 90,
    fileId: fileId,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: 1,
  );

  RectangleElement locked(String id) => RectangleElement(
    id: ElementId(id),
    x: 700,
    y: 700,
    width: 80,
    height: 80,
    locked: true,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: 1,
  );

  TextElement lockedText(String id) => TextElement(
    id: ElementId(id),
    x: 100,
    y: 900,
    width: 200,
    height: 40,
    text: '锁定的文本',
    locked: true,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: 1,
  );

  Scene baseScene() => Scene()
      .addElement(typedText('t-typed'))
      .addElement(ink('i1'))
      .addElement(ink('i2', x: 320))
      .addElement(figure('img-e', 'file-1'))
      .addElement(locked('lock-e'))
      .addElement(lockedText('t-locked'));

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 3,
    fingerprint: SceneFingerprint.of(scene),
  );

  TextBlockSpec spec(String text, {double fontSize = 20}) => TextBlockSpec(
    text: text,
    fontFamily: 'Excalifont',
    fontSize: fontSize,
    lineHeight: 1.25,
  );

  LayoutBlock block(
    String id,
    LayoutBlockKind kind,
    List<String> refs, {
    TextBlockSpec? textSpec,
    FigureBlockSpec? figureSpec,
    LayoutTextOrigin? origin,
  }) => LayoutBlock(
    id: id,
    kind: kind,
    sourceRefs: refs,
    orderIndex: 0,
    keepTogether: false,
    textOrigin: origin,
    text: textSpec,
    figure: figureSpec,
  );

  LayoutBlockAssembly assembly({
    required List<LayoutBlock> blocks,
    required List<String> consumed,
    required List<String> preserved,
  }) => LayoutBlockAssembly(
    blocks: blocks,
    relationships: const [],
    atomicGroups: const [],
    documentConsumedSourceIds: consumed,
    documentPreservedSourceIds: preserved,
  );

  PlacedBlock placed(String blockId, LayoutRect rect, {double fontSize = 20}) =>
      PlacedBlock(
        blockId: blockId,
        rect: rect,
        columnIndex: 0,
        lineCount: 2,
        appliedFontSize: fontSize,
        shrunk: false,
      );

  // 完整五源场景：typed 文本 + 两笔转写笔迹 + 图片 + 锁定障碍。
  LayoutBlockAssembly fullAssembly() => assembly(
    blocks: [
      block(
        'b-title',
        LayoutBlockKind.title,
        ['t-typed'],
        textSpec: spec('typed 标题', fontSize: 28),
        origin: LayoutTextOrigin.typed,
      ),
      block(
        'b-ink',
        LayoutBlockKind.paragraph,
        ['i1', 'i2'],
        textSpec: spec('转写的段落'),
        origin: LayoutTextOrigin.transcribed,
      ),
      block(
        'b-fig',
        LayoutBlockKind.figure,
        ['img-e'],
        figureSpec: FigureBlockSpec(
          fileId: 'file-1',
          displayAspectRatio: 4 / 3,
        ),
      ),
      block('b-lock', LayoutBlockKind.protected, ['lock-e']),
    ],
    consumed: ['t-typed', 'i1', 'i2', 'img-e'],
    preserved: ['lock-e'],
  );

  FlowPlacementSuccess fullPlacement() => FlowPlacementSuccess(
    placed: [
      placed(
        'b-title',
        LayoutRect(left: 40, top: 40, width: 360, height: 36),
        fontSize: 28,
      ),
      placed('b-ink', LayoutRect(left: 40, top: 84, width: 360, height: 88)),
      placed('b-fig', LayoutRect(left: 40, top: 176, width: 160, height: 120)),
    ],
    usedHeights: [296],
  );

  SourceCoverageLedger pendingLedger() =>
      SourceCoverageLedger.pending(['t-typed', 'i1', 'i2', 'img-e', 'lock-e']);

  test('完整 candidate 一次物化：元素/关系/selection 全链与 ledger 守恒', () {
    final scene = baseScene();
    final outcome = SmartLayoutCandidateMaterializer.materialize(
      baseScene: scene,
      baseRevision: revisionOf(scene),
      sourceCoverage: pendingLedger(),
      assembly: fullAssembly(),
      placement: fullPlacement(),
      timestampMs: 123456,
      pageId: 'page-1',
    );
    expect(outcome, isA<PatchMaterializationSuccess>());
    final success = outcome as PatchMaterializationSuccess;
    final patch = success.patch;

    // typed 文本 + 图片：经 303A 变换改写到放置盒，version+1 与确定性 nonce。
    expect(patch.updates.map((o) => o.elementId), ['img-e', 't-typed']);
    final typedUpdate =
        patch.updates.firstWhere((o) => o.elementId == 't-typed').element
            as TextElement;
    expect(typedUpdate.x, 40);
    expect(typedUpdate.y, 40);
    expect(typedUpdate.width, 360);
    expect(typedUpdate.height, 36);
    expect(typedUpdate.fontSize, 28, reason: '字号显式对齐放置档');
    expect(typedUpdate.version, 2);
    final imgUpdate = patch.updates
        .firstWhere((o) => o.elementId == 'img-e')
        .element;
    expect(imgUpdate.width, 160);
    expect(imgUpdate.height, 120);

    // 转写笔迹：整组移除 + 单个确定性新增文本。
    expect(patch.removes.map((o) => o.elementId), ['i1', 'i2']);
    expect(patch.adds.map((o) => o.elementId), ['sl3-b-ink']);
    final added = patch.adds.single.element as TextElement;
    expect(added.x, 40);
    expect(added.y, 84);
    expect(added.fontSize, 20);
    expect(added.autoResize, isFalse);
    expect(added.version, 1);
    expect(added.customData?['flowMuse'], {
      'pageId': 'page-1',
    }, reason: '新元素页面归属与快照同口径');

    // selection intent = 物化主体（变换源 + 新增）。
    expect(patch.selectionIntent, ['img-e', 'sl3-b-ink', 't-typed']);

    // ledger 守恒：4 consumed / 1 preserved，零 pending。
    expect(patch.sourceCoverage.isFinalized, isTrue);
    expect(patch.sourceCoverage.consumedCount, 4);
    expect(patch.sourceCoverage.preservedCount, 1);
    expect(
      patch.sourceCoverage.statusOf('lock-e'),
      SourceCoverageStatus.preserved,
    );

    // 独立复核全绿。
    expect(
      SmartLayoutScenePatchValidator.validate(patch: patch, baseScene: scene),
      isEmpty,
    );
    expect(
      SmartLayoutScenePatchValidator.checkLedgerConservation(patch: patch),
      isEmpty,
    );
  });

  test('物化确定性：同输入双跑深度等价、codec 逐字节一致', () {
    SmartLayoutScenePatch run() {
      final scene = baseScene();
      final outcome = SmartLayoutCandidateMaterializer.materialize(
        baseScene: scene,
        baseRevision: revisionOf(scene),
        sourceCoverage: pendingLedger(),
        assembly: fullAssembly(),
        placement: fullPlacement(),
        timestampMs: 123456,
        pageId: 'page-1',
      );
      return (outcome as PatchMaterializationSuccess).patch;
    }

    final a = run();
    final b = run();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, b), isTrue);
    expect(ScenePatchDebugCodec.encode(a), ScenePatchDebugCodec.encode(b));
  });

  test('原子失败：不支持类型/悬空/缺放置/账目不符均零 patch', () {
    final scene = baseScene();
    // 各失败子用例的 assembly 源集与传入账本一致（守恒前置不短路
    // 目标检查点）。
    PatchMaterializationOutcome run({
      required LayoutBlockAssembly assembly,
      required Iterable<String> ledgerSources,
      FlowPlacementSuccess? placement,
    }) => SmartLayoutCandidateMaterializer.materialize(
      baseScene: scene,
      baseRevision: revisionOf(scene),
      sourceCoverage: SourceCoverageLedger.pending(ledgerSources),
      assembly: assembly,
      placement: placement ?? fullPlacement(),
      timestampMs: 123456,
    );

    // table 不支持类型。
    final table = run(
      ledgerSources: ['t-typed', 'lock-e'],
      assembly: assembly(
        blocks: [
          block('b-table', LayoutBlockKind.table, ['t-typed']),
          block('b-lock', LayoutBlockKind.protected, ['lock-e']),
        ],
        consumed: ['t-typed'],
        preserved: ['lock-e'],
      ),
    );
    expect(
      (table as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.unsupportedBlockKind,
    );

    // typed 源数 != 1。
    final twoTyped = run(
      ledgerSources: ['t-typed', 'i1', 'lock-e'],
      assembly: assembly(
        blocks: [
          block(
            'b-t',
            LayoutBlockKind.title,
            ['t-typed', 'i1'],
            textSpec: spec('x'),
            origin: LayoutTextOrigin.typed,
          ),
          block('b-lock', LayoutBlockKind.protected, ['lock-e']),
        ],
        consumed: ['t-typed', 'i1'],
        preserved: ['lock-e'],
      ),
    );
    expect(
      (twoTyped as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.typedSourceInvalid,
    );

    // 源未解析：transcribed 引用 base 不存在的元素。
    final ghostRef = run(
      ledgerSources: ['ghost', 'lock-e'],
      assembly: assembly(
        blocks: [
          block(
            'b-t',
            LayoutBlockKind.paragraph,
            ['ghost'],
            textSpec: spec('x'),
            origin: LayoutTextOrigin.transcribed,
          ),
          block('b-lock', LayoutBlockKind.protected, ['lock-e']),
        ],
        consumed: ['ghost'],
        preserved: ['lock-e'],
      ),
    );
    expect(
      (ghostRef as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.sourceUnresolved,
    );
    expect(ghostRef.blockId, 'b-t');

    // 消费块缺放置结果。
    final missingPlacement = run(
      ledgerSources: ['t-typed', 'i1', 'i2', 'img-e', 'lock-e'],
      assembly: fullAssembly(),
      placement: FlowPlacementSuccess(
        placed: [
          placed(
            'b-title',
            LayoutRect(left: 40, top: 40, width: 360, height: 36),
            fontSize: 28,
          ),
        ],
        usedHeights: [36],
      ),
    );
    expect(
      (missingPlacement as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.missingPlacement,
    );

    // assembly 账目与账本源集不一致（assembly 内部守恒，但账本多出
    // 一个源）。
    final mismatch = run(
      ledgerSources: ['t-typed', 'i1', 'lock-e'],
      assembly: assembly(
        blocks: [
          block(
            'b-t',
            LayoutBlockKind.paragraph,
            ['i1'],
            textSpec: spec('x'),
            origin: LayoutTextOrigin.transcribed,
          ),
          block('b-lock', LayoutBlockKind.protected, ['lock-e']),
        ],
        consumed: ['i1'],
        preserved: ['lock-e'],
      ),
    );
    expect(
      (mismatch as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.ledgerSourceMismatch,
    );

    // 锁定 TextElement 作为 typed 源：契约拒绝，整体失败。
    final lockedSource = run(
      ledgerSources: ['t-locked'],
      assembly: assembly(
        blocks: [
          block(
            'b-t',
            LayoutBlockKind.title,
            ['t-locked'],
            textSpec: spec('x'),
            origin: LayoutTextOrigin.typed,
          ),
        ],
        consumed: ['t-locked'],
        preserved: [],
      ),
      placement: FlowPlacementSuccess(
        placed: [
          placed('b-t', LayoutRect(left: 40, top: 40, width: 360, height: 36)),
        ],
        usedHeights: [36],
      ),
    );
    expect(
      (lockedSource as PatchMaterializationFailure).kind,
      PatchMaterializationFailureKind.transformRejected,
    );
  });

  test('figure 资产缺失：不删块不造数据，零元素触碰（账目按 assembly）', () {
    final scene = baseScene();
    final outcome = SmartLayoutCandidateMaterializer.materialize(
      baseScene: scene,
      baseRevision: revisionOf(scene),
      sourceCoverage: SourceCoverageLedger.pending(['t-typed', 'img-e']),
      assembly: assembly(
        blocks: [
          block(
            'b-title',
            LayoutBlockKind.title,
            ['t-typed'],
            textSpec: spec('typed 标题', fontSize: 28),
            origin: LayoutTextOrigin.typed,
          ),
          block(
            'b-fig',
            LayoutBlockKind.figure,
            ['img-e'],
            figureSpec: FigureBlockSpec(
              fileId: 'file-missing',
              displayAspectRatio: 1,
              missingAsset: true,
            ),
          ),
        ],
        // figure 块按 kind 记账为 consumed（assembly 守恒口径），
        // missingAsset 只决定物化零触碰。
        consumed: ['t-typed', 'img-e'],
        preserved: [],
      ),
      placement: FlowPlacementSuccess(
        placed: [
          placed(
            'b-title',
            LayoutRect(left: 40, top: 40, width: 360, height: 36),
            fontSize: 28,
          ),
        ],
        usedHeights: [36],
      ),
      timestampMs: 123456,
    );
    expect(outcome, isA<PatchMaterializationSuccess>());
    final patch = (outcome as PatchMaterializationSuccess).patch;
    expect(patch.updates.map((o) => o.elementId), [
      't-typed',
    ], reason: '只有 typed 文本被改写；缺失资产图零触碰');
    expect(patch.removes, isEmpty);
    expect(patch.adds, isEmpty);
    expect(
      patch.sourceCoverage.statusOf('img-e'),
      SourceCoverageStatus.consumed,
      reason: '账目按 assembly kind 口径：figure 块是 consumed',
    );
    expect(
      SmartLayoutScenePatchValidator.checkLedgerConservation(patch: patch),
      isEmpty,
      reason: '未触碰的 consumed 源不违反守恒（零副作用合法）',
    );
  });
}
