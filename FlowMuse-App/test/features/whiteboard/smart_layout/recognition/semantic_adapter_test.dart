import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';

import 'structure_test_helpers.dart';

/// R6 语义适配（spec §8.1）：映射表、账本结算与投影、子树连续、
/// 保留/锁定/背景处理。
void main() {
  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  test('原生组合含锁定成员：整个闭包入保留账本', () async {
    final result = await sessionOf(
      const [],
      scene: Scene()
          .addElement(
            TextElement(
              id: const ElementId('a'),
              x: 0,
              y: 0,
              width: 100,
              height: 30,
              text: '甲',
              groupIds: const ['g'],
            ),
          )
          .addElement(
            TextElement(
              id: const ElementId('b'),
              x: 120,
              y: 0,
              width: 100,
              height: 30,
              text: '乙',
              groupIds: const ['g'],
              locked: true,
            ),
          ),
    );
    final settled = adapter.settle(result);
    expect(settled.ledger.preservedCount, 2);
    expect(settled.ledger.consumedCount, 0);
  });

  test('OCR已成功但结构冲突：账本保留、障碍块、后置守卫禁止替换', () async {
    final result = await sessionOf(
      const [RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '标题')],
      structureOverride: StructureResult(
        units: [
          RecognitionUnitInput(
            unitId: 'ink:r:a',
            kind: RecognitionUnitKind.ink,
            text: '标题',
            bounds: const RecognitionBounds(
              left: 0,
              top: 0,
              width: 200,
              height: 20,
            ),
          ),
        ],
        readingOrder: const ['ink:r:a'],
        roles: const {'ink:r:a': 'title'},
        listGroups: const [],
        captions: const [],
        warnings: const ['冲突'],
        usedModel: true,
        conflictedUnitIds: const {'ink:r:a'},
      ),
    );
    final settled = adapter.settle(result);
    expect(settled.ledger.entryOf('s-a').status, SourceLedgerStatus.preserved);
    expect(
      adapter
          .assemble(settled, measure: TextMeasureAdapter(), tokens: tokens)
          .document
          .blocks
          .single
          .role,
      SemanticRole.unknown,
    );
    expect(
      ReplacementGuard.factsOf(result)['ink:r:a']!.conflictsResolved,
      isFalse,
    );
    expect(
      ReplacementGuard.check(
        recognition: settled.ledger,
        unitFactsByUnitId: ReplacementGuard.factsOf(result),
        deletedSourceIds: ['s-a'],
        modifiedSourceIds: const [],
      ),
      isNotEmpty,
    );
  });

  SemanticAssembly assembleOf(RecognitionSessionResult result) =>
      adapter.assemble(result, measure: TextMeasureAdapter(), tokens: tokens);

  RecognitionUnitInput inkUnit(String regionId, {double top = 0}) =>
      RecognitionUnitInput(
        unitId: 'ink:$regionId',
        kind: RecognitionUnitKind.ink,
        text: 'x',
        bounds: RecognitionBounds(left: 0, top: top, width: 200, height: 20),
        lineHintHeight: 20,
      );

  group('§8.1 角色映射表（显式写死，禁止同名映射兜底）', () {
    test('title/body/caption 直映；listItem→list；other→unknown', () async {
      final structure = StructureResult(
        units: [
          inkUnit('r:a'),
          inkUnit('r:b'),
          inkUnit('r:c'),
          inkUnit('r:d'),
          inkUnit('r:e'),
        ],
        readingOrder: const [
          'ink:r:a',
          'ink:r:b',
          'ink:r:c',
          'ink:r:d',
          'ink:r:e',
        ],
        roles: const {
          'ink:r:a': 'title',
          'ink:r:b': 'body',
          'ink:r:c': 'caption',
          'ink:r:d': 'listItem',
          'ink:r:e': 'other',
        },
        listGroups: const [],
        captions: const [],
        warnings: const [],
        usedModel: false,
      );
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '标题'),
        RegionSpec(regionId: 'r:b', top: 30, left: 0, text: '正文'),
        RegionSpec(regionId: 'r:c', top: 60, left: 0, text: '图注'),
        RegionSpec(regionId: 'r:d', top: 90, left: 0, text: '1. 项'),
        RegionSpec(regionId: 'r:e', top: 120, left: 0, text: '其他'),
      ], structureOverride: structure);
      final assembly = assembleOf(result);
      final roleOf = {
        for (final block in assembly.document.blocks) block.id: block.role,
      };
      expect(roleOf['ink:r:a'], SemanticRole.title);
      expect(roleOf['ink:r:b'], SemanticRole.body);
      expect(roleOf['ink:r:c'], SemanticRole.caption);
      expect(
        roleOf['ink:r:d'],
        SemanticRole.list,
        reason: 'listItem 必须映射为 list',
      );
      expect(
        roleOf['ink:r:e'],
        SemanticRole.unknown,
        reason: 'other 保留语义不进排版流',
      );
      // 全部 recognized 笔迹消费入账。
      expect(
        assembly.document.consumedSourceIds,
        containsAll(['s-a', 's-b', 's-c', 's-d', 's-e']),
      );
      expect(assembly.ledger.isFinalized, isTrue);
    });

    test('ink 正文落 extras.transcribedText；typed 正文落块 text 字段', () async {
      final scene = Scene().addElement(
        TextElement(
          id: const ElementId('text-1'),
          x: 0,
          y: 60,
          width: 200,
          height: 40,
          text: '原生正文',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      );
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:ink', top: 0, left: 0, text: '手写正文'),
      ], scene: scene);
      final assembly = assembleOf(result);
      final inkBlock = assembly.document.blocks.firstWhere(
        (block) => block.id == 'ink:r:ink',
      );
      expect(inkBlock.text, isNull, reason: '手写正文绝不进 text 字段');
      expect(inkBlock.extras['transcribedText'], '手写正文');
      final typedBlock = assembly.document.blocks.firstWhere(
        (block) => block.id == 'native:text-1',
      );
      expect(typedBlock.text, '原生正文');
      expect(typedBlock.extras.containsKey('transcribedText'), isFalse);
      expect(
        assembly.document.consumedSourceIds,
        containsAll(['s-ink', 'text-1']),
      );
    });

    test('figure 单元→figure 角色；preserved 单元→unknown + bounds 障碍身份', () async {
      final scene = Scene()
          .addElement(
            ImageElement(
              id: const ElementId('img-1'),
              x: 300,
              y: 0,
              width: 100,
              height: 90,
              fileId: 'file-1',
              seed: 7,
              versionNonce: 11,
              updated: 1000,
            ),
          )
          .addElement(
            DiamondElement(
              id: const ElementId('dia-1'),
              x: 0,
              y: 300,
              width: 60,
              height: 60,
              seed: 7,
              versionNonce: 11,
              updated: 1000,
            ),
          );
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:txt', top: 120, left: 0, text: '说明'),
      ], scene: scene);
      final assembly = assembleOf(result);
      final figureBlock = assembly.document.blocks.firstWhere(
        (block) => block.id == 'native:img-1',
      );
      expect(figureBlock.role, SemanticRole.figure);
      expect(figureBlock.sourceIds, ['img-1']);
      final shapeBlock = assembly.document.blocks.firstWhere(
        (block) => block.id == 'native:dia-1',
      );
      expect(shapeBlock.role, SemanticRole.unknown);
      final bounds = shapeBlock.extras['bounds'] as Map<String, Object?>;
      expect(bounds['width'], 60);
      // 形状按 nonText 保留，图片按消费（变换不删除）。
      final settled = adapter.settle(result);
      expect(
        settled.ledger.projection.preservedReasons['dia-1'],
        SourcePreserveReason.nonText,
      );
      expect(settled.ledger.projection.consumedBy['img-1'], 'native:img-1');
    });
  });

  group('账本结算（§6.4）', () {
    test('uncertain 区域：保留 reason=uncertain，角色强制 unknown', () async {
      final result = await sessionOf(
        const [RegionSpec(regionId: 'r:u', top: 0, left: 0, text: '存疑内容')],
        customOutcomes: const {
          'r:u': RegionReadOutcome(
            regionId: 'r:u',
            status: RecognitionRegionStatus.uncertain,
            targetSourceIds: ['s-u'],
            text: '存疑内容',
            confidence: 0.3,
          ),
        },
      );
      final settled = adapter.settle(result);
      expect(
        settled.ledger.projection.preservedReasons['s-u'],
        SourcePreserveReason.uncertain,
      );
      final assembly = assembleOf(result);
      final block = assembly.document.blocks.firstWhere(
        (block) => block.id == 'ink:r:u',
      );
      expect(block.role, SemanticRole.unknown);
      expect(assembly.document.preservedSourceIds, ['s-u']);
    });

    test('锁定笔迹毒化整单元：整区域保留 locked，不消费', () async {
      final scene = Scene().addElement(
        FreedrawElement(
          id: const ElementId('s-lk'),
          x: 0,
          y: 0,
          width: 60,
          height: 8,
          points: const [Point(0, 4), Point(30, 4), Point(60, 4)],
          strokeColor: '#1e1e1e',
          strokeWidth: 2,
          isComplete: true,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          locked: true,
        ),
      );
      final result = await sessionOf(const [], scene: scene);
      // 直接构造：该锁定笔迹区域被识别为 recognized。
      final record = RegionRecord(
        regionId: 'r:lk',
        bounds: RecognitionBounds(left: 0, top: 0, width: 60, height: 8),
        targetSourceIds: const ['s-lk'],
        localLineHeight: 8,
      );
      final structure = StructureResult(
        units: [
          RecognitionUnitInput(
            unitId: 'ink:r:lk',
            kind: RecognitionUnitKind.ink,
            text: '锁定笔迹',
            bounds: RecognitionBounds(left: 0, top: 0, width: 60, height: 8),
            lineHintHeight: 8,
          ),
        ],
        readingOrder: const ['ink:r:lk'],
        roles: const {'ink:r:lk': 'body'},
        listGroups: const [],
        captions: const [],
        warnings: const [],
        usedModel: false,
      );
      final session = RecognitionSessionResult(
        operationId: 'op-lk',
        generation: 0,
        pageId: 'page-1',
        scene: scene,
        sceneRevision: result.sceneRevision,
        contentFingerprint: result.contentFingerprint,
        regionRecords: [record],
        regionOutcomes: const {
          'r:lk': RegionReadOutcome(
            regionId: 'r:lk',
            status: RecognitionRegionStatus.recognized,
            targetSourceIds: ['s-lk'],
            text: '锁定笔迹',
            confidence: 0.9,
          ),
        },
        ledger: SourceLedger.register(const ['s-lk']),
        assetIndex: result.assetIndex,
        structureResult: structure,
      );
      final settled = adapter.settle(session);
      expect(
        settled.ledger.projection.preservedReasons['s-lk'],
        SourcePreserveReason.locked,
      );
      final assembly = assembleOf(session);
      expect(
        assembly.document.blocks.firstWhere((b) => b.id == 'ink:r:lk').role,
        SemanticRole.unknown,
      );
    });

    test('锁定原生文本：无语义块，账本 preserve(locked)', () async {
      final scene = Scene().addElement(
        TextElement(
          id: const ElementId('text-lock'),
          x: 0,
          y: 0,
          width: 200,
          height: 40,
          text: '锁定文本',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          locked: true,
        ),
      );
      final result = await sessionOf(const [], scene: scene);
      final settled = adapter.settle(result);
      expect(
        settled.ledger.projection.preservedReasons['text-lock'],
        SourcePreserveReason.locked,
      );
      final assembly = assembleOf(result);
      expect(
        assembly.document.blocks.where((b) => b.id == 'native:text-lock'),
        isEmpty,
        reason: '锁定物由快照装配层 protected 障碍块接管，不重复建块',
      );
    });

    test('结构角色 other 的 typed：不入流，preserve(contextOnly)', () async {
      final scene = Scene().addElement(
        TextElement(
          id: const ElementId('text-other'),
          x: 0,
          y: 0,
          width: 200,
          height: 40,
          text: '旁注',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      );
      final structure = StructureResult(
        units: [
          RecognitionUnitInput(
            unitId: 'native:text-other',
            kind: RecognitionUnitKind.typed,
            text: '旁注',
            bounds: RecognitionBounds(left: 0, top: 0, width: 200, height: 40),
            lineHintHeight: 25,
          ),
        ],
        readingOrder: const ['native:text-other'],
        roles: const {'native:text-other': 'other'},
        listGroups: const [],
        captions: const [],
        warnings: const [],
        usedModel: false,
      );
      final result = await sessionOf(
        const [],
        scene: scene,
        structureOverride: structure,
      );
      final settled = adapter.settle(result);
      expect(
        settled.ledger.projection.preservedReasons['text-other'],
        SourcePreserveReason.contextOnly,
      );
      final assembly = assembleOf(result);
      expect(
        assembly.document.blocks
            .firstWhere((b) => b.id == 'native:text-other')
            .role,
        SemanticRole.unknown,
      );
    });

    test('背景元素（页面框/PDF 底图）不入源集不建块', () async {
      final scene = Scene()
          .addElement(
            TextElement(
              id: const ElementId('page-frame'),
              x: 0,
              y: 0,
              width: 2000,
              height: 40,
              text: '页面框',
              seed: 7,
              versionNonce: 11,
              updated: 1000,
              customData: const {
                'flowMuse': {'role': 'page'},
              },
            ),
          )
          .addElement(
            ImageElement(
              id: const ElementId('pdf-bg'),
              x: 0,
              y: 0,
              width: 2000,
              height: 1400,
              fileId: 'file-bg',
              seed: 7,
              versionNonce: 11,
              updated: 1000,
              customData: const {
                'flowMuse': {'pdfBackground': true},
              },
            ),
          );
      final result = await sessionOf(const [], scene: scene);
      final assembly = assembleOf(result);
      expect(
        assembly.document.blocks.where(
          (b) =>
              b.id.startsWith('native:page-frame') ||
              b.id.startsWith('native:pdf-bg'),
        ),
        isEmpty,
      );
      expect(assembly.ledger.sourceCount, 0);
      expect(assembly.document.consumedSourceIds, isEmpty);
      expect(assembly.document.preservedSourceIds, isEmpty);
    });

    test('settle 幂等：已结算会话重复结算不抛错不换账目', () async {
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
      ]);
      final first = adapter.settle(result);
      final second = adapter.settle(first);
      expect(second.ledger, first.ledger);
      expect(second.copyWith(ledger: first.ledger).ledger, first.ledger);
    });

    test('structureResult 缺失：fail closed', () async {
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
      ]);
      final broken = RecognitionSessionResult(
        operationId: result.operationId,
        generation: result.generation,
        pageId: result.pageId,
        scene: result.scene,
        sceneRevision: result.sceneRevision,
        contentFingerprint: result.contentFingerprint,
        regionRecords: result.regionRecords,
        regionOutcomes: result.regionOutcomes,
        ledger: result.ledger,
        assetIndex: result.assetIndex,
      );
      expect(() => adapter.settle(broken), throwsStateError);
      expect(
        () => assembleOf(broken),
        throwsStateError,
        reason: '无结构结果不得产出半文档',
      );
    });
  });

  group('§8.1 嵌套子树连续与图注元数据', () {
    test('列表子树成员在 orderedBlockIds 中连续（跨行带交错修复）', () async {
      // 行带交错：父项 P(y=0) / 外来文本 X(y=25) / 子项 C(y=50)——
      // 本地行带序会把 X 插进父子之间；子树连续要求 P,C 相邻。
      final structure = StructureResult(
        units: [
          inkUnit('r:p', top: 0),
          inkUnit('r:x', top: 25),
          inkUnit('r:c', top: 50),
        ],
        readingOrder: const ['ink:r:p', 'ink:r:x', 'ink:r:c'],
        roles: const {
          'ink:r:p': 'listItem',
          'ink:r:x': 'body',
          'ink:r:c': 'listItem',
        },
        listGroups: const [
          RecognitionListGroup(
            groupId: 'g-parent',
            members: ['ink:r:p'],
            level: 0,
            listType: RecognitionListType.ordered,
            startNumber: 1,
          ),
          RecognitionListGroup(
            groupId: 'g-child',
            members: ['ink:r:c'],
            level: 1,
            listType: RecognitionListType.ordered,
            startNumber: 1,
            parentUnitId: 'ink:r:p',
          ),
        ],
        captions: const [],
        warnings: const [],
        usedModel: false,
      );
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:p', top: 0, left: 0, text: '1. 父'),
        RegionSpec(regionId: 'r:x', top: 25, left: 0, text: '外来正文'),
        RegionSpec(regionId: 'r:c', top: 50, left: 40, text: '1. 子'),
      ], structureOverride: structure);
      final assembly = assembleOf(result);
      final order = assembly.document.readingOrder.orderedBlockIds;
      expect(order, const ['ink:r:p', 'ink:r:c', 'ink:r:x']);
      final child = assembly.document.blocks.firstWhere(
        (block) => block.id == 'ink:r:c',
      );
      expect(child.extras['listGroupId'], 'g-child');
      expect(child.extras['level'], 1);
      expect(child.extras['listType'], 'ordered');
      expect(child.extras['parentUnitId'], 'ink:r:p');
    });

    test('图注 extras.captionOf 记录目标；目标不存在 fail closed', () async {
      final goodStructure = StructureResult(
        units: [
          RecognitionUnitInput(
            unitId: 'native:img-1',
            kind: RecognitionUnitKind.figure,
            bounds: RecognitionBounds(left: 0, top: 0, width: 100, height: 90),
          ),
          inkUnit('r:cap'),
        ],
        readingOrder: const ['native:img-1', 'ink:r:cap'],
        roles: const {'ink:r:cap': 'caption'},
        listGroups: const [],
        captions: const [
          RecognitionCaption(
            captionUnitId: 'ink:r:cap',
            targetUnitId: 'native:img-1',
          ),
        ],
        warnings: const [],
        usedModel: false,
      );
      final scene = Scene().addElement(
        ImageElement(
          id: const ElementId('img-1'),
          x: 0,
          y: 0,
          width: 100,
          height: 90,
          fileId: 'file-1',
          seed: 7,
          versionNonce: 11,
          updated: 1000,
        ),
      );
      final result = await sessionOf(
        const [RegionSpec(regionId: 'r:cap', top: 100, left: 0, text: '图1 说明')],
        scene: scene,
        structureOverride: goodStructure,
      );
      final assembly = assembleOf(result);
      expect(
        assembly.document.blocks
            .firstWhere((b) => b.id == 'ink:r:cap')
            .extras['captionOf'],
        'native:img-1',
      );

      final dangling = StructureResult(
        units: goodStructure.units,
        readingOrder: goodStructure.readingOrder,
        roles: goodStructure.roles,
        listGroups: const [],
        captions: const [
          RecognitionCaption(
            captionUnitId: 'ink:r:cap',
            targetUnitId: 'native:missing',
          ),
        ],
        warnings: const [],
        usedModel: false,
      );
      final danglingResult = await sessionOf(
        const [RegionSpec(regionId: 'r:cap', top: 100, left: 0, text: '图1 说明')],
        scene: scene,
        structureOverride: dangling,
      );
      expect(() => assembleOf(danglingResult), throwsStateError);
    });
  });

  group('文档投影一致性', () {
    test('文档账目 = 结算识别账本投影；守恒闭合', () async {
      final scene = Scene()
          .addElement(
            TextElement(
              id: const ElementId('text-1'),
              x: 0,
              y: 0,
              width: 200,
              height: 40,
              text: '原生',
              seed: 7,
              versionNonce: 11,
              updated: 1000,
            ),
          )
          .addElement(
            DiamondElement(
              id: const ElementId('dia-1'),
              x: 0,
              y: 300,
              width: 60,
              height: 60,
              seed: 7,
              versionNonce: 11,
              updated: 1000,
            ),
          );
      final result = await sessionOf(const [
        RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '识别文本'),
        RegionSpec(regionId: 'r:miss', top: 200, left: 0),
      ], scene: scene);
      final assembly = assembleOf(result);
      final settled = adapter.settle(result);
      final projection = settled.ledger.projection;
      expect(
        assembly.document.consumedSourceIds,
        [...projection.consumedBy.keys]..sort(),
      );
      expect(
        assembly.document.preservedSourceIds,
        [...projection.preservedReasons.keys]..sort(),
      );
      expect(assembly.document.ledgerConserved, isTrue);
      expect(assembly.ledger.isFinalized, isTrue);
      // 漏答区域保留原因透传（管线侧 missingResponse）。
      expect(
        assembly.document.preservedSourceIds,
        containsAll(['s-miss', 'dia-1']),
      );
    });
  });
}
