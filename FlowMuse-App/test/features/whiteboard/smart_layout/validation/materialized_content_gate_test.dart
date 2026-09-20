import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/reduced_scene_metrics_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/validated_candidate_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TextElement text(String id, String value, double x, double y) => TextElement(
    id: ElementId(id),
    x: x,
    y: y,
    width: 180,
    height: 30,
    text: value,
    fontSize: 20,
    fontFamily: 'Excalifont',
    lineHeight: 1.25,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );
  LayoutBlock block(String id, String source, String? value) => LayoutBlock(
    id: id,
    kind: value == null ? LayoutBlockKind.preserved : LayoutBlockKind.paragraph,
    sourceRefs: [source],
    orderIndex: 0,
    keepTogether: false,
    text: value == null
        ? null
        : TextBlockSpec(
            text: value,
            fontFamily: 'Excalifont',
            fontSize: 20,
            lineHeight: 1.25,
          ),
  );
  final assembly = LayoutBlockAssembly(
    blocks: [
      block('title', 't1', '标题'),
      block('body', 'ink', '完整正文'),
      block('fixed', 'fixed', null),
    ],
    relationships: const [
      BlockRelationship(
        kind: BlockRelationKind.keepWith,
        fromBlockId: 'title',
        toBlockId: 'body',
      ),
    ],
    atomicGroups: const [
      ['title', 'body'],
    ],
    documentConsumedSourceIds: const ['t1', 'ink'],
    documentPreservedSourceIds: const ['fixed'],
  );
  final base = [
    text('t1', '标题', 400, 50),
    FreedrawElement(
      id: const ElementId('ink'),
      x: 450,
      y: 300,
      width: 160,
      height: 60,
      points: const [Point(0, 0), Point(160, 60)],
      seed: 7,
      versionNonce: 11,
      updated: 1000,
    ),
    RectangleElement(
      id: const ElementId('fixed'),
      x: 500,
      y: 450,
      width: 80,
      height: 60,
      seed: 7,
      versionNonce: 11,
      updated: 1000,
    ),
  ].fold<Scene>(Scene(), (scene, element) => scene.addElement(element));
  final page = Bounds.fromLTWH(0, 0, 800, 600);

  Future<GateRoundResult> run(String mutation) {
    final y = mutation == 'far'
        ? 300.0
        : mutation == 'overlap'
        ? 40.0
        : 90.0;
    final x = mutation == 'fixed-overlap' ? 500.0 : 60.0;
    final bodyY = mutation == 'fixed-overlap' ? 450.0 : y;
    final builder =
        SmartLayoutScenePatchBuilder(
            baseScene: base,
            baseRevision: SceneRevision(
              epoch: 0,
              revision: 1,
              fingerprint: SceneFingerprint.of(base),
            ),
            sourceCoverage: SourceCoverageLedger.pending(const [
              't1',
              'ink',
              'fixed',
            ]).markConsumed(const ['t1', 'ink']).markPreserved(const ['fixed']),
          )
          ..updateElement(
            text('t1', '标题', 60, 40).copyWith(version: 2),
            baseVersion: 1,
          )
          ..removeElement('ink', baseVersion: 1, versionNonce: 12);
    if (mutation != 'delete-only') {
      builder.addElement(
        text('replacement', mutation == 'wrong-text' ? '少字' : '完整正文', x, bodyY),
      );
    }
    return ValidatedCandidatePipeline.run(
      baseScene: base,
      pageContentBounds: page,
      profile: LayoutProfile.readability,
      candidates: [
        CandidateGateInput(
          candidateId: mutation,
          diversityKey: 'single',
          patch: builder.build(),
          semanticContextKey: 'semantic:1|scope:1|policy:1',
          validationElementIds: const {'t1', 'replacement'},
          outputElementIdsByBlock: {
            'title': ['t1'],
            if (mutation != 'missing-map') 'body': ['replacement'],
            'fixed': ['fixed'],
          },
          relations: [
            if (mutation != 'empty-relations')
              SemanticRelationExpectation(
                relationId: 'keepWith:title:body',
                kind: SemanticRelationExpectationKind.keepWith,
                anchorId: 'title',
                followerId: mutation == 'wrong-endpoint' ? 'fixed' : 'body',
                maxGap: 48,
              ),
          ],
          readingOrder: mutation == 'empty-order'
              ? null
              : ReadingOrderExpectation(
                  orderedElementIds: const ['title', 'body'],
                  columnByNode: {
                    'title': 0,
                    'body': mutation == 'wrong-column' ? 1 : 0,
                  },
                  columns: [Bounds.fromLTWH(40, 30, 720, 550)],
                ),
          metricInput: LayoutMetricInput(
            assembly: assembly,
            placed: [
              for (final id in ['title', 'body'])
                PlacedBlock(
                  blockId: id,
                  // 故意始终自报好位置；最终 gate 必须依据真实输出拒绝坏位置。
                  rect: LayoutRect(
                    left: 60,
                    top: id == 'title' ? 40 : 90,
                    width: 180,
                    height: 30,
                  ),
                  columnIndex: 0,
                  lineCount: 1,
                  appliedFontSize: 20,
                  shrunk: false,
                ),
            ],
            columnRects: [
              LayoutRect(left: 40, top: 30, width: 720, height: 550),
            ],
            preservedRects: const {},
            originalBounds: const {},
            contentHeight: 550,
            hardValidated: true,
          ),
          veto: const VetoVerdict(kinds: [], reasons: []),
        ),
      ],
    );
  }

  test('真实替代文字、输出映射、关系与阅读序闭环通过', () async {
    final result = await run('valid');
    expect(
      result.top,
      hasLength(1),
      reason: result.rejections.map((r) => r.detail).join(','),
    );
    expect(result.top.single.expectationDigest, isNotEmpty);
    expect(result.top.single.metrics.relationCompliance, 1);
    result.top.single.dispose();
  });

  for (final mutation in [
    'delete-only',
    'missing-map',
    'wrong-text',
    'far',
    'overlap',
    'fixed-overlap',
    'empty-relations',
    'wrong-endpoint',
    'empty-order',
    'wrong-column',
  ]) {
    test('最终输出负例 $mutation 不因自报好位置而通过', () async {
      final result = await run(mutation);
      addTearDown(() {
        for (final c in result.top) {
          c.dispose();
        }
      });
      expect(result.top, isEmpty);
      expect(result.rejections, hasLength(1));
    });
  }

  test('集合同但消费/保留状态相反不守恒', () {
    expect(assembly.ledgerConserved, isTrue);
    expect(
      LayoutBlockAssembly(
        blocks: assembly.blocks,
        relationships: assembly.relationships,
        atomicGroups: assembly.atomicGroups,
        documentConsumedSourceIds: const ['fixed', 'ink'],
        documentPreservedSourceIds: const ['t1'],
      ).ledgerConserved,
      isFalse,
    );
  });
}
