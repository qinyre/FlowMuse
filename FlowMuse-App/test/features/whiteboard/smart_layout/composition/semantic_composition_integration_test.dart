import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/commit/validated_candidate_commit_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/semantic_composer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/composition_scene_metrics.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/candidate_patch_materializer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/scene_patch_debug_codec.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/reduced_scene_metrics_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';
import 'fixtures/semantic_composition/pages.dart';

// 离线布局回归：角色/图文配对是真值输入，合成插画不是线上模型识别证据。
const _export = bool.fromEnvironment('EXPORT_LAYOUT_EVIDENCE');
const _cjkPath = String.fromEnvironment('LAYOUT_EVIDENCE_CJK_FONT');
const _font = _export && _cjkPath != '' ? 'LayoutEvidenceCJK' : 'Excalifont';
const _page = LayoutRect(left: 0, top: 0, width: 1024, height: 1300);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader(
      'Excalifont',
    )..addFont(rootBundle.load('assets/fonts/markdraw/Excalifont-Regular.ttf'));
    // 只用于人工导图；CI 仍使用平台测试字体，不把字体环境差异冒充实机。
    if (_export && _cjkPath.isNotEmpty) {
      final cjk = FontLoader(_font)
        ..addFont(
          File(_cjkPath).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await cjk.load();
    }
    await fonts.load();
  });

  for (final page in effectPages) {
    test('效果集 ${page.holdout ? '留出' : '开发'} ${page.name}', () async {
      final f = await _effectFixture(page);
      final layouts = await SemanticComposer.generate(
        scene: f.scene,
        assembly: f.assembly,
        pageFrame: f.frame,
        measure: TextMeasureAdapter(),
      );
      final repeat = await SemanticComposer.generate(
        scene: f.scene,
        assembly: f.assembly,
        pageFrame: f.frame,
        measure: TextMeasureAdapter(),
      );
      expect(layouts.map((l) => l.signature), repeat.map((l) => l.signature));
      for (var i = 0; i < layouts.length; i++) {
        expect(
          ScenePatchDebugCodec.encode(_input(f, layouts[i]).patch),
          ScenePatchDebugCodec.encode(_input(f, repeat[i]).patch),
        );
      }
      final round = await _gate(f, layouts);
      expect(
        round.top,
        isNotEmpty,
        reason: '${page.name}: ${round.rejections}',
      );
      for (final c in round.top) {
        final output = c.reduced.scene.activeElements;
        expect(
          output.whereType<ImageElement>().map((e) => e.id.value).toSet(),
          f.scene.activeElements
              .whereType<ImageElement>()
              .map((e) => e.id.value)
              .toSet(),
        );
        for (final b in f.assembly.blocks) {
          if (b.text != null &&
              c.patch.sourceCoverage.statusOf(b.sourceRefs.first) ==
                  SourceCoverageStatus.consumed) {
            expect(
              output.whereType<TextElement>().where(
                (e) => e.text == b.text!.text,
              ),
              hasLength(1),
              reason: b.id,
            );
          }
          if (b.isPreservedLike) {
            for (final id in b.sourceRefs) {
              expect(
                output.singleWhere((e) => e.id.value == id),
                same(
                  f.scene.activeElements.singleWhere((e) => e.id.value == id),
                ),
              );
            }
          }
        }
      }
      if (page.alreadyGood) expect(round.recommendation!.recommended, isFalse);
      debugPrint(
        'EFFECT ${page.name} top=${round.top.first.diversityKey} '
        'recommend=${round.recommendation!.recommended} delta=${round.recommendation!.improvement} '
        'scores=${round.top.map((c) => '${c.diversityKey}:${c.score.score.toStringAsFixed(4)}').join(',')}',
      );
      if (_export) {
        final renderer = DraftSceneRenderer();
        final original = await renderer.render(
          scene: f.scene,
          viewport: const ViewportState(),
          pixelSize: ui.Size(f.frame.width, f.frame.height),
        );
        await _png('${page.name}-before', original);
        await _png(
          '${page.name}-after',
          round.recommendation!.recommended
              ? round.top.first.snapshot
              : original,
        );
        // 即使保留原稿，也留一份最高分备选，不能以隐藏坏例代替评估。
        await _png('${page.name}-alternative', round.top.first.snapshot);
        original.dispose();
        renderer.dispose();
      }
      for (final c in round.top) {
        c.dispose();
      }
    });
  }

  if (const bool.fromEnvironment('RUN_LAYOUT_BENCHMARK')) {
    test('同机同字体本地候选十次基准（不含网络/样例构建）', () async {
      final f = await _fixture();
      final times = <int>[];
      for (var i = 0; i < 11; i++) {
        final watch = Stopwatch()..start();
        final layouts = await SemanticComposer.generate(
          scene: f.scene,
          assembly: f.assembly,
          pageFrame: _page,
          measure: TextMeasureAdapter(),
        );
        final round = await _gate(f, layouts);
        watch.stop();
        expect(round.top, isNotEmpty);
        for (final c in round.top) {
          c.dispose();
        }
        if (i > 0) times.add(watch.elapsedMicroseconds);
      }
      final sorted = [...times]..sort();
      debugPrint(
        'COMPOSITION_BENCH us=$times median_us=${(sorted[4] + sorted[5]) / 2} max_us=${sorted.last} font=$_font',
      );
    });
  }

  test('双图双说明：三种真实布局、确定性、最终门禁、应用及撤销', () async {
    final source = await _fixture();
    final controller = MarkdrawController()..loadScene(source.scene);
    addTearDown(controller.dispose);
    final f = _Fixture(controller.currentScene, source.assembly);
    final measure = TextMeasureAdapter();
    final first = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: measure,
    );
    final second = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: measure,
    );
    expect(
      first.map((l) => l.family),
      containsAll(['single', 'mediaSide', 'peerGrid']),
    );
    expect(first.length, lessThanOrEqualTo(6));
    expect(first.map((l) => l.signature).toSet(), hasLength(first.length));
    expect(first.map((l) => l.signature), second.map((l) => l.signature));
    for (var i = 0; i < first.length; i++) {
      expect(
        ScenePatchDebugCodec.encode(_input(f, first[i]).patch),
        ScenePatchDebugCodec.encode(_input(f, second[i]).patch),
      );
      final layout = first[i];
      expect(layout.groups, hasLength(3), reason: '标题不能将第一整组吞进巨型原子组');
      expect(
        layout.assembly.blocks
            .singleWhere((b) => b.id == 'b-title')
            .text!
            .fontSize,
        36,
      );
      expect(
        layout.assembly.blocks
            .singleWhere((b) => b.id == 'b-body-a')
            .text!
            .fontSize,
        24,
      );
      expect(
        layout.placed.singleWhere((p) => p.blockId == 'b-image-a').rect.width,
        greaterThan(100),
        reason: '高分辨率小显示图允许合理放大',
      );
    }
    final round = await _gate(f, first);
    expect(
      round.top,
      hasLength(3),
      reason: round.rejections
          .map((r) => '${r.candidateId}: ${r.reasonCodes} ${r.detail}')
          .join('\n'),
    );
    addTearDown(() {
      for (final c in round.top) {
        c.dispose();
      }
    });
    if (_export) {
      final renderer = DraftSceneRenderer();
      final original = await renderer.render(
        scene: f.scene,
        viewport: const ViewportState(),
        pixelSize: const ui.Size(1024, 1300),
      );
      await _png('01-original', original);
      original.dispose();
      renderer.dispose();
      for (final c in round.top) {
        await _png('01-${c.diversityKey}', c.snapshot);
      }
    }
    final gateway = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);
    final before = _visualPayload(controller.currentScene);
    final candidate = round.top.first;
    expect(
      ValidatedCandidateCommitGateway(
        editor: gateway,
        revisions: tracker,
      ).commit(candidate),
      isA<HistoryCommitted>(),
    );
    expect(
      _visualPayload(controller.currentScene),
      _visualPayload(candidate.reduced.scene),
    );
    controller.undo();
    expect(_visualPayload(controller.currentScene), before);
    controller.redo();
    expect(
      _visualPayload(controller.currentScene),
      _visualPayload(candidate.reduced.scene),
    );
  });

  test('不同长度前置说明：同级图片顶对齐且真实门禁通过', () async {
    final f = await _fixture(textFirst: true);
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    final grid = layouts.singleWhere((l) => l.family == 'peerGrid');
    expect(
      grid.placed.singleWhere((p) => p.blockId == 'b-image-a').rect.top,
      grid.placed.singleWhere((p) => p.blockId == 'b-image-b').rect.top,
    );
    final round = await _gate(f, [grid]);
    expect(
      round.top,
      hasLength(1),
      reason: '${round.rejections.map((r) => r.reasonCodes)}',
    );
    for (final c in round.top) {
      c.dispose();
    }
  });

  test('实际评分：原稿可胜出、缺测不推荐、同输入分母不随候选改变', () async {
    final f = await _fixture();
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    final round = await _gate(f, layouts);
    expect(round.recommendation!.recommended, isTrue);
    expect(round.recommendation!.improvement, greaterThanOrEqualTo(.05));
    final best = round.top.first;
    final ctx = CompositionMetricContext(
      source: f.assembly,
      page: Bounds.fromLTWH(0, 0, 1024, 1300),
      analyzed: true,
      pageIntent: 'comparison',
    );
    final originalBounds = ctx.boxes(best.snapshot, const {});
    final unchanged = ctx.calculate(
      scene: best.reduced.scene,
      snapshot: best.snapshot,
      originalBounds: originalBounds,
    );
    expect(
      CompositionRecommendation.compare(unchanged, unchanged).recommended,
      isFalse,
    );
    expect(
      CompositionRecommendation.compare(unchanged, unchanged).improvement,
      0,
    );
    final unknown =
        CompositionMetricContext(
          source: f.assembly,
          page: ctx.page,
          analyzed: false,
        ).calculate(
          scene: best.reduced.scene,
          snapshot: best.snapshot,
          originalBounds: originalBounds,
        );
    expect(
      unknown.stateOf(LayoutMetricId.figureTextAffinity),
      LayoutMetricState.unavailable,
    );
    expect(unknown[LayoutMetricId.figureTextAffinity], 0);
    expect(
      CompositionRecommendation.compare(unknown, unchanged).improvement,
      isNull,
    );
    final fake = _input(f, layouts.first);
    final altered = CandidateGateInput(
      candidateId: fake.candidateId,
      diversityKey: fake.diversityKey,
      patch: fake.patch,
      metricInput: LayoutMetricInput(
        assembly: fake.metricInput.assembly,
        placed: const [],
        columnRects: const [],
        preservedRects: const {},
        originalBounds: const {},
        contentHeight: 1,
        hardValidated: true,
      ),
      veto: fake.veto,
      validationElementIds: fake.validationElementIds,
      outputElementIdsByBlock: fake.outputElementIdsByBlock,
      semanticContextKey: fake.semanticContextKey,
      relations: fake.relations,
      readingOrder: fake.readingOrder,
      compositionGroups: fake.compositionGroups,
    );
    final tampered = await ValidatedCandidatePipeline.run(
      baseScene: f.scene,
      pageContentBounds: ctx.page,
      candidates: [altered],
      profile: LayoutProfile.composition,
      compositionMetrics: ctx,
    );
    expect(tampered.top, hasLength(1));
    final matching = round.top.singleWhere(
      (c) => c.candidateId == fake.candidateId,
    );
    expect(
      tampered.top.single.score.score,
      matching.score.score,
      reason: '空的计划位置、内容高度和原位声明不能改变实际评分',
    );
    for (final c in [...round.top, ...tampered.top]) {
      c.dispose();
    }
  });

  test('手写转写与图组共用真实物化，不丢正文、crop、强调色', () async {
    final f = await _fixture(ocr: true, cropped: true);
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    final round = await _gate(f, layouts);
    expect(
      round.top,
      isNotEmpty,
      reason: round.rejections.map((r) => r.detail).join(','),
    );
    for (final c in round.top) {
      expect(c.patch.removes.map((r) => r.elementId), ['body-a']);
      expect(c.patch.adds.single.element, isA<TextElement>());
      final text = c.patch.adds.single.element as TextElement;
      expect(text.text, '这是躺着的\n小猫，它喜欢晒太阳。');
      expect(text.lineHeight, 1.35);
      final before = f.scene.activeElements.whereType<ImageElement>().first;
      final after = c.reduced.scene.activeElements
          .whereType<ImageElement>()
          .first;
      expect(after.fileId, before.fileId);
      expect(after.crop, before.crop);
      expect(
        after.width / after.height,
        closeTo(before.width / before.height, .000001),
      );
      expect(
        c.reduced.scene.activeElements
            .singleWhere((e) => e.id.value == 'body-b')
            .strokeColor,
        '#d97706',
      );
      c.dispose();
    }
  });

  test('小像素图不放大；没有真实像素信息不猜分辨率', () async {
    final f = await _fixture(lowResolution: true);
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    expect(layouts, isNotEmpty);
    for (final l in layouts) {
      expect(
        l.placed.singleWhere((p) => p.blockId == 'b-image-a').rect.width,
        lessThanOrEqualTo(32),
      );
      expect(
        l.groups.any((g) => g.kind == CompositionGroupKind.mediaSide),
        isFalse,
      );
    }
  });

  test('文字先于图片的语义阅读序仍可左右排，不强改图在前', () async {
    final f = await _fixture(textFirst: true);
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    final side = layouts.singleWhere((l) => l.family == 'mediaSide');
    expect(side.groups[1].tracks, [
      ['b-body-a'],
      ['b-image-a'],
    ]);
    final round = await _gate(f, [side]);
    expect(
      round.top,
      hasLength(1),
      reason: round.rejections
          .map((r) => '${r.reasonCodes}:${r.detail}')
          .join(','),
    );
    for (final c in round.top) {
      c.dispose();
    }
  });

  test('坏图片资产只降级关系组件；全部不可排时不制造空 patch 候选', () async {
    final f = await _fixture();
    var scene = f.scene.addFile(
      'a',
      ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList([1, 2, 3])),
    );
    final layouts = await SemanticComposer.generate(
      scene: scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    expect(layouts, isNotEmpty);
    for (final l in layouts) {
      expect(
        l.assembly.documentPreservedSourceIds,
        containsAll(['title', 'image-a', 'body-a']),
      );
      expect(
        l.placed.map((p) => p.blockId),
        containsAll(['b-image-b', 'b-body-b']),
      );
    }
    scene = scene.addFile(
      'b',
      ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList([4, 5, 6])),
    );
    expect(
      await SemanticComposer.generate(
        scene: scene,
        assembly: f.assembly,
        pageFrame: _page,
        measure: TextMeasureAdapter(),
      ),
      isEmpty,
    );
  });

  test('连续标题跨固定障碍时随首个内容组一起走，不留孤立标题', () async {
    final f = await _fixture(lowResolution: true);
    final scene = f.scene.addElement(
      TextElement(
        id: const ElementId('subheading'),
        x: 200,
        y: 100,
        width: 200,
        height: 30,
        text: '一、观察结果',
        fontFamily: _font,
        seed: 1,
        versionNonce: 1,
        updated: 1,
      ),
    );
    final assembly = LayoutBlockAssembly(
      blocks: [
        f.assembly.blocks.first,
        const LayoutBlock(
          id: 'b-subheading',
          kind: LayoutBlockKind.title,
          sourceRefs: ['subheading'],
          orderIndex: .5,
          keepTogether: false,
          textOrigin: LayoutTextOrigin.typed,
          text: TextBlockSpec(
            text: '一、观察结果',
            fontFamily: _font,
            fontSize: 20,
            lineHeight: 1.25,
          ),
        ),
        ...f.assembly.blocks.skip(1),
      ],
      relationships: [
        const BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-title',
          toBlockId: 'b-subheading',
        ),
        const BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-subheading',
          toBlockId: 'b-image-a',
        ),
        ...f.assembly.relationships.skip(1),
      ],
      atomicGroups: f.assembly.atomicGroups,
      documentConsumedSourceIds: [
        ...f.assembly.documentConsumedSourceIds,
        'subheading',
      ],
      documentPreservedSourceIds: const [],
    );
    final layouts = await SemanticComposer.generate(
      scene: scene,
      assembly: assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
      fixedObstacles: const {
        'fixed-banner': LayoutRect(left: 0, top: 200, width: 1024, height: 40),
      },
    );
    expect(layouts, isNotEmpty);
    for (final l in layouts) {
      final title = l.placed.singleWhere((p) => p.blockId == 'b-title');
      final sub = l.placed.singleWhere((p) => p.blockId == 'b-subheading');
      expect(title.rect.top, greaterThan(240));
      expect(
        sub.rect.top - title.rect.bottom,
        closeTo(l.policy.innerGap, .001),
      );
    }
  });

  test('正文过长：依附图片与标题整体保留，其他组继续排版', () async {
    final f = await _fixture(ocr: true, tooLong: true);
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    expect(layouts, isNotEmpty);
    final round = await _gate(f, layouts);
    expect(
      round.top,
      isNotEmpty,
      reason: round.rejections
          .map((r) => '${r.reasonCodes}:${r.detail}')
          .join(','),
    );
    for (final c in round.top) {
      for (final id in ['title', 'image-a', 'body-a']) {
        expect(
          c.patch.sourceCoverage.statusOf(id),
          SourceCoverageStatus.preserved,
        );
        expect(c.patch.writeSet.elementIds, isNot(contains(id)));
      }
      expect(
        c.patch.sourceCoverage.statusOf('image-b'),
        SourceCoverageStatus.consumed,
      );
      c.dispose();
    }
  });

  test('横排/并列声明在真实场景被破坏后拒绝，不把声明本身当证据', () async {
    final f = await _fixture();
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    for (final layout in layouts.where((l) => l.family != 'single')) {
      final result = await ValidatedCandidatePipeline.run(
        baseScene: f.scene,
        pageContentBounds: Bounds.fromLTWH(0, 0, 1024, 1300),
        candidates: [_input(f, layout, corrupt: true)],
        profile: LayoutProfile.readability,
      );
      expect(result.top, isEmpty, reason: layout.family);
      expect(result.rejections, isNotEmpty);
    }
  });

  test('原生闭包合成后别名、输出映射及文字样式仍可追踪', () async {
    final f = await _fixture();
    var scene = f.scene;
    for (final e in f.scene.activeElements.where(
      (e) => ['image-a', 'body-a'].contains(e.id.value),
    )) {
      scene = scene.updateElement(e.copyWith(groupIds: const ['native-group']));
    }
    final composite = SmartLayoutCandidateMaterializer.composeNativeGroups(
      scene,
      f.assembly,
    );
    expect(composite.blockAliases['b-body-a'], 'b-image-a');
    final updated = _Fixture(scene, composite);
    final layouts = await SemanticComposer.generate(
      scene: scene,
      assembly: composite,
      pageFrame: _page,
      measure: TextMeasureAdapter(),
    );
    expect(layouts, isNotEmpty);
    for (final layout in layouts) {
      final input = _input(updated, layout);
      expect(
        input.outputElementIdsByBlock!['b-body-a'],
        input.outputElementIdsByBlock!['b-image-a'],
      );
    }
    final round = await _gate(updated, layouts);
    expect(
      round.top,
      isNotEmpty,
      reason: round.rejections
          .map((r) => '${r.reasonCodes}:${r.detail}')
          .join(','),
    );
    for (final c in round.top) {
      c.dispose();
    }
  });
}

class _Fixture {
  const _Fixture(this.scene, this.assembly, [this.frame = _page]);
  final Scene scene;
  final LayoutBlockAssembly assembly;
  final LayoutRect frame;
}

Future<_Fixture> _effectFixture(EffectPage page) async {
  final frame = LayoutRect(left: 0, top: 0, width: 1024, height: page.height);
  var scene = Scene().addElement(
    RectangleElement(
      id: const ElementId('page'),
      x: 0,
      y: 0,
      width: frame.width,
      height: frame.height,
      roughness: 0,
      customData: const {
        'flowMuse': {'role': 'page', 'pageId': 'p'},
      },
    ),
  );
  final blocks = <LayoutBlock>[];
  for (var i = 0; i < page.order.length; i++) {
    final id = page.order[i], text = page.texts[id];
    final x = [600.0, 90.0, 440.0][i % 3];
    final y = i == 0 ? 36.0 : 100.0 + i * 115;
    final kind = page.titles.contains(id)
        ? LayoutBlockKind.title
        : page.lists.contains(id)
        ? LayoutBlockKind.list
        : page.captions.containsKey(id)
        ? LayoutBlockKind.caption
        : text == null
        ? LayoutBlockKind.figure
        : LayoutBlockKind.paragraph;
    final ink = page.soft.containsKey(id);
    final projection = text == null
        ? null
        : DisplayTextProjection.create(
            rawText: text,
            origin: ink ? LayoutTextOrigin.transcribed : LayoutTextOrigin.typed,
            kind: kind,
            newlineIndexes: page.soft[id] ?? const [],
            confidence: ink ? 1 : 0,
          );
    if (text == null) {
      if (!page.missing.contains(id)) {
        scene = scene.addFile(
          id,
          ImageFile(mimeType: 'image/png', bytes: await _illustration(id, 640)),
        );
      }
      scene = scene.addElement(
        ImageElement(
          id: ElementId(id),
          x: x,
          y: y,
          width: 180,
          height: page.portrait.contains(id) ? 270 : 135,
          fileId: id,
          crop: page.portrait.contains(id)
              ? const ImageCrop(x: 0, y: 0, width: .5, height: 1)
              : null,
        ),
      );
    } else if (ink) {
      scene = scene.addElement(
        FreedrawElement(
          id: ElementId(id),
          x: x,
          y: y,
          width: 240,
          height: 70,
          points: const [
            Point(0, 0),
            Point(30, 20),
            Point(80, 0),
            Point(120, 50),
            Point(200, 70),
          ],
        ),
      );
    } else {
      scene = scene.addElement(
        TextElement(
          id: ElementId(id),
          x: x,
          y: y,
          width: 340,
          height: 55,
          fontFamily: _font,
          fontSize: 20,
          text: text,
          strokeColor: '#233b30',
        ),
      );
    }
    blocks.add(
      LayoutBlock(
        id: 'b-$id',
        kind: kind,
        sourceRefs: [id],
        orderIndex: i.toDouble(),
        keepTogether: false,
        textOrigin: text == null
            ? null
            : ink
            ? LayoutTextOrigin.transcribed
            : LayoutTextOrigin.typed,
        text: projection == null
            ? null
            : TextBlockSpec(
                text: projection.displayText,
                fontFamily: _font,
                fontSize: 20,
                lineHeight: 1.25,
                projection: projection,
              ),
        figure: text == null
            ? FigureBlockSpec(
                fileId: id,
                displayAspectRatio: page.portrait.contains(id) ? 2 / 3 : 4 / 3,
                missingAsset: page.missing.contains(id),
              )
            : null,
        extras: {
          if (ink) 'transcribedText': text,
          if (page.sections[id] != null) 'sectionId': page.sections[id],
          if (page.sections[id] != null && page.titles.contains(id))
            'sectionHeading': true,
          if (page.lists.contains(id)) ...{'listGroupId': 'list', 'level': 1},
          if (page.captions[id] != null) 'captionOf': 'b-${page.captions[id]}',
        },
      ),
    );
  }
  if (page.fixed) {
    scene = scene
        .addElement(
          RectangleElement(
            id: const ElementId('fixed'),
            x: 840,
            y: 1050,
            width: 90,
            height: 60,
            locked: true,
            groupIds: const ['diagram'],
          ),
        )
        .addElement(
          ArrowElement(
            id: const ElementId('arrow'),
            x: 930,
            y: 1080,
            width: 60,
            height: 30,
            points: const [Point(0, 0), Point(60, 30)],
            groupIds: const ['diagram'],
            startBinding: const PointBinding(
              elementId: 'fixed',
              fixedPoint: Point(1, .5),
            ),
          ),
        );
    for (final id in ['fixed', 'arrow']) {
      blocks.add(
        LayoutBlock(
          id: 'b-$id',
          kind: LayoutBlockKind.preserved,
          sourceRefs: [id],
          orderIndex: blocks.length.toDouble(),
          keepTogether: true,
        ),
      );
    }
  }
  final relations = <BlockRelationship>[
    for (final g in page.groups)
      for (var i = 0; i + 1 < g.length; i++)
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-${g[i]}',
          toBlockId: 'b-${g[i + 1]}',
        ),
    for (final c in page.captions.entries)
      BlockRelationship(
        kind: BlockRelationKind.captionOf,
        fromBlockId: 'b-${c.key}',
        toBlockId: 'b-${c.value}',
      ),
    for (var i = 0; i + 1 < page.order.length; i++)
      if (page.titles.contains(page.order[i]))
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-${page.order[i]}',
          toBlockId: 'b-${page.order[i + 1]}',
        ),
  ];
  var f = _Fixture(
    scene,
    LayoutBlockAssembly(
      blocks: blocks,
      relationships: relations,
      atomicGroups: [
        for (final g in page.groups) g.map((id) => 'b-$id').toList(),
      ],
      documentConsumedSourceIds: page.order,
      documentPreservedSourceIds: page.fixed
          ? const ['fixed', 'arrow']
          : const [],
    ),
    frame,
  );
  if (page.alreadyGood) {
    final layouts = await SemanticComposer.generate(
      scene: f.scene,
      assembly: f.assembly,
      pageFrame: frame,
      measure: TextMeasureAdapter(),
    );
    final layout = layouts.firstWhere((l) => l.family == 'peerGrid');
    final reduced =
        SmartLayoutSceneReducer.apply(
              base: f.scene,
              patch: _input(f, layout).patch,
            )
            as ReducedScene;
    f = _Fixture(reduced.scene, layout.assembly, frame);
  }
  return f;
}

Future<_Fixture> _fixture({
  bool ocr = false,
  bool cropped = false,
  bool lowResolution = false,
  bool tooLong = false,
  bool textFirst = false,
}) async {
  var scene = Scene().addElement(
    RectangleElement(
      id: const ElementId('page'),
      x: 0,
      y: 0,
      width: 1024,
      height: 1300,
      backgroundColor: '#fffdf5',
      fillStyle: FillStyle.solid,
      roughness: 0,
      customData: const {
        'flowMuse': {'role': 'page', 'pageId': 'p'},
      },
      seed: 1,
      versionNonce: 1,
      updated: 1,
    ),
  );
  final bodyA = tooLong
      ? List.filled(160, '这段内容需要完整保留，不能为了排版而截掉。').join()
      : '这是躺着的\n小猫，它喜欢晒太阳。';
  final texts = {
    'title': '观察笔记 / Animal notes',
    'body-a': bodyA,
    'body-b': '小狗在草地玩耍。\n注意它的耳朵和尾巴。',
  };
  for (final entry in texts.entries) {
    final x = entry.key == 'title'
        ? 200.0
        : entry.key == 'body-a'
        ? 600.0
        : 400.0;
    final y = entry.key == 'title'
        ? 30.0
        : entry.key == 'body-a'
        ? 300.0
        : 750.0;
    scene = scene.addElement(
      ocr && entry.key == 'body-a'
          ? FreedrawElement(
              id: ElementId(entry.key),
              x: x,
              y: y,
              width: 240,
              height: 50,
              points: const [Point(0, 0), Point(240, 50)],
              seed: 3,
              versionNonce: 1,
              updated: 1,
            )
          : TextElement(
              id: ElementId(entry.key),
              x: x,
              y: y,
              width: 380,
              height: 56,
              text: entry.value,
              fontSize: 20,
              fontFamily: _font,
              strokeColor: entry.key == 'body-b' ? '#d97706' : '#1b2925',
              seed: 3,
              versionNonce: 1,
              updated: 1,
            ),
    );
  }
  for (final name in ['a', 'b']) {
    scene = scene
        .addFile(
          name,
          ImageFile(
            mimeType: 'image/png',
            bytes: await _illustration(name, lowResolution ? 32 : 640),
          ),
        )
        .addElement(
          ImageElement(
            id: ElementId('image-$name'),
            x: name == 'a' ? 100 : 700,
            y: name == 'a' ? 170 : 500,
            width: 100,
            height: cropped && name == 'a' ? 150 : 75,
            fileId: name,
            crop: cropped && name == 'a'
                ? const ImageCrop(x: 0, y: 0, width: .5, height: 1)
                : null,
            seed: 3,
            versionNonce: 1,
            updated: 1,
          ),
        );
  }
  final ids = textFirst
      ? ['title', 'body-a', 'image-a', 'body-b', 'image-b']
      : ['title', 'image-a', 'body-a', 'image-b', 'body-b'];
  return _Fixture(
    scene,
    LayoutBlockAssembly(
      blocks: [
        for (var i = 0; i < ids.length; i++)
          LayoutBlock(
            id: 'b-${ids[i]}',
            kind: ids[i] == 'title'
                ? LayoutBlockKind.title
                : ids[i].startsWith('image')
                ? LayoutBlockKind.figure
                : LayoutBlockKind.paragraph,
            sourceRefs: [ids[i]],
            orderIndex: i.toDouble(),
            keepTogether: false,
            textOrigin: ids[i].startsWith('image')
                ? null
                : ocr && ids[i] == 'body-a'
                ? LayoutTextOrigin.transcribed
                : LayoutTextOrigin.typed,
            text: texts[ids[i]] == null
                ? null
                : TextBlockSpec(
                    text: texts[ids[i]]!,
                    fontFamily: _font,
                    fontSize: 20,
                    lineHeight: 1.25,
                  ),
            figure: ids[i].startsWith('image')
                ? FigureBlockSpec(
                    fileId: ids[i].split('-').last,
                    displayAspectRatio: 4 / 3,
                    displayWidth: 100,
                  )
                : null,
            extras: {if (ocr && ids[i] == 'body-a') 'transcribedText': bodyA},
          ),
      ],
      relationships: const [
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-title',
          toBlockId: 'b-image-a',
        ),
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-body-a',
          toBlockId: 'b-image-a',
        ),
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 'b-body-b',
          toBlockId: 'b-image-b',
        ),
      ],
      atomicGroups: const [
        ['b-title', 'b-image-a', 'b-body-a'],
        ['b-image-b', 'b-body-b'],
      ],
      documentConsumedSourceIds: ids,
      documentPreservedSourceIds: const [],
    ),
  );
}

CandidateGateInput _input(
  _Fixture f,
  SemanticCompositionLayout layout, {
  bool corrupt = false,
}) {
  final output = SmartLayoutCandidateMaterializer.materialize(
    baseScene: f.scene,
    baseRevision: SceneRevision(
      epoch: 0,
      revision: 1,
      fingerprint: SceneFingerprint.of(f.scene),
    ),
    sourceCoverage: SourceCoverageLedger.pending([
      ...f.assembly.documentConsumedSourceIds,
      ...f.assembly.documentPreservedSourceIds,
    ]),
    assembly: layout.assembly,
    placement: FlowPlacementSuccess(
      placed: layout.placed,
      usedHeights: const [],
    ),
    timestampMs: 1,
  );
  expect(output, isA<PatchMaterializationSuccess>(), reason: '$output');
  final success = output as PatchMaterializationSuccess;
  var patch = success.patch;
  if (corrupt) {
    patch = SmartLayoutScenePatch(
      baseRevision: patch.baseRevision,
      documentOp: patch.documentOp,
      selectionIntent: patch.selectionIntent,
      sourceCoverage: patch.sourceCoverage,
      adds: patch.adds,
      removes: patch.removes,
      fileAdds: patch.fileAdds,
      updates: [
        for (final op in patch.updates)
          ScenePatchElementUpdate(
            element: op.elementId == 'body-a'
                ? op.element.copyWith(x: 850, y: 1000)
                : op.element,
            baseVersion: op.baseVersion,
          ),
      ],
    );
  }
  return CandidateGateInput(
    candidateId: layout.family,
    diversityKey: layout.family,
    patch: patch,
    metricInput: LayoutMetricInput(
      assembly: layout.assembly,
      placed: layout.placed,
      columnRects: [layout.content],
      preservedRects: layout.preservedRects,
      originalBounds: const {},
      contentHeight: layout.content.height,
      hardValidated: true,
    ),
    veto: const VetoVerdict(kinds: [], reasons: []),
    semanticContextKey: layout.policy.key,
    validationElementIds: {
      ...patch.updates.map((o) => o.elementId),
      ...patch.adds.map((o) => o.elementId),
    },
    outputElementIdsByBlock: success.outputElementIdsByBlock,
    compositionGroups: layout.groups,
    readingOrder: ReadingOrderExpectation(
      orderedElementIds: [
        for (final b in layout.assembly.blocks)
          if (!b.isPreservedLike) b.id,
      ],
    ),
    relations: [
      for (final r in layout.assembly.relationships)
        () {
          final ids = layout.assembly.blocks.map((b) => b.id).toList();
          final forward = ids.indexOf(r.fromBlockId) < ids.indexOf(r.toBlockId);
          return SemanticRelationExpectation(
            relationId: '${r.kind.name}:${r.fromBlockId}:${r.toBlockId}',
            kind: r.kind == BlockRelationKind.keepWith
                ? SemanticRelationExpectationKind.keepWith
                : SemanticRelationExpectationKind.captionOf,
            anchorId: forward ? r.fromBlockId : r.toBlockId,
            followerId: forward ? r.toBlockId : r.fromBlockId,
            maxGap: layout.policy.innerGap,
          );
        }(),
    ],
  );
}

Future<GateRoundResult> _gate(
  _Fixture f,
  List<SemanticCompositionLayout> layouts,
) => ValidatedCandidatePipeline.run(
  baseScene: f.scene,
  pageContentBounds: Bounds.fromLTWH(
    f.frame.left,
    f.frame.top,
    f.frame.width,
    f.frame.height,
  ),
  candidates: layouts.map((l) => _input(f, l)).toList(),
  profile: LayoutProfile.composition,
  compositionMetrics: CompositionMetricContext(
    source: f.assembly,
    page: Bounds.fromLTWH(
      f.frame.left,
      f.frame.top,
      f.frame.width,
      f.frame.height,
    ),
    analyzed: true,
    pageIntent: 'comparison',
  ),
);

Future<Uint8List> _illustration(String kind, int width) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(width / 640);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 640, 480),
    ui.Paint()
      ..color = kind == 'a'
          ? const ui.Color(0xffd7e9df)
          : const ui.Color(0xfff1e2c2),
  );
  canvas.drawOval(
    const ui.Rect.fromLTWH(80, 160, 480, 250),
    ui.Paint()
      ..color = kind == 'a'
          ? const ui.Color(0xff647f70)
          : const ui.Color(0xffa57948),
  );
  canvas.drawCircle(
    const ui.Offset(390, 200),
    100,
    ui.Paint()..color = const ui.Color(0xfff7f2e5),
  );
  for (final x in [360.0, 420.0]) {
    canvas.drawCircle(
      ui.Offset(x, 190),
      8,
      ui.Paint()..color = const ui.Color(0xff253b31),
    );
  }
  // 每个资产可视觉区分，避免测试中两图字节相同而无法发现交换。
  if (kind != 'a' && kind != 'b') {
    final code = kind.runes.fold<int>(0, (s, r) => s * 31 + r);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 640, 24),
      ui.Paint()..color = ui.Color(0xff000000 | (code & 0x7f7f7f)),
    );
    final label = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 42))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xff233b30)))
      ..addText(kind);
    final paragraph = label.build()
      ..layout(const ui.ParagraphConstraints(width: 620));
    canvas.drawParagraph(paragraph, const ui.Offset(20, 415));
    paragraph.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, (width * .75).round());
  try {
    return (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _png(String name, DraftRenderSnapshot snapshot) async {
  final dir = Directory('build/semantic-composition-evidence')
    ..createSync(recursive: true);
  // Draft 为透明前景，预览组件在纸色背景上显示；导图使用相同背景口径。
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Offset.zero & snapshot.pixelSize,
    ui.Paint()..color = const ui.Color(0xfffffdf5),
  );
  canvas.drawImage(snapshot.image, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    snapshot.pixelSize.width.round(),
    snapshot.pixelSize.height.round(),
  );
  try {
    final bytes = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    await File('${dir.path}/$name.png').writeAsBytes(bytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

// 既有协作入口会刷新提交时间和 nonce；其余字段逐字相同，含样式/坐标/关系。
String _visualPayload(Scene scene) => canonicalValue({
  'elements': [
    for (final e in scene.elements)
      ExcalidrawJsonCodec.elementToJson(e)
        ..remove('versionNonce')
        ..remove('updated'),
  ],
  'files': scene.files.keys.toList()..sort(),
});
