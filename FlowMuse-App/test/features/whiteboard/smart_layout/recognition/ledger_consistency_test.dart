import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';

import 'structure_test_helpers.dart';

/// §6.4-1 三方一致断言（候选生成入口第 0 步后的 fail closed 检查）：
/// 正例 + 三反例（源集合同但状态相反 / consume 归属 unitId 错配 /
/// 完整快照未剥离背景）。
void main() {
  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  SemanticAssembly assembleOf(RecognitionSessionResult result) =>
      adapter.assemble(result, measure: TextMeasureAdapter(), tokens: tokens);

  Set<String> nonBackgroundIdsOf(RecognitionSessionResult result) => {
    for (final element in result.scene.activeElements)
      if (!(element.isCanvasPage || element.isPdfBackground)) element.id.value,
  };

  test('正例：适配产物与结算识别账本三方一致', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
      RegionSpec(regionId: 'r:miss', top: 50, left: 0),
    ]);
    final settled = adapter.settle(result);
    final assembly = assembleOf(settled);
    expect(
      () => RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: nonBackgroundIdsOf(settled),
        recognition: settled.ledger,
        assembly: assembly,
      ),
      returnsNormally,
    );
  });

  test('反例 1：源集相同但终态相反（识别 consume / 文档 preserve）', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final settled = adapter.settle(result);
    final assembly = assembleOf(settled);
    // 伪造状态相反的独立账本：同源集合，全部 preserve。
    final flipped = SourceLedger.register(settled.ledger.sourceIds);
    var flippedLedger = flipped;
    for (final sourceId in settled.ledger.sourceIds) {
      flippedLedger = flippedLedger.preserve(
        sourceId,
        SourcePreserveReason.userKept,
      );
    }
    expect(
      () => RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: nonBackgroundIdsOf(settled),
        recognition: flippedLedger,
        assembly: assembly,
      ),
      throwsStateError,
      reason: '集合相等不充分——逐源终态必须一致',
    );
  });

  test('反例 2：consume 归属 unitId 错配', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final settled = adapter.settle(result);
    final assembly = assembleOf(settled);
    // 伪造归属错配的独立账本：同一源被另一 unit 消费。
    final mismatched = SourceLedger.register(const [
      's-a',
    ]).registerUnits(const ['ink:r:other']).consume('s-a', 'ink:r:other');
    expect(mismatched.projection.consumedBy['s-a'], 'ink:r:other');
    expect(
      () => RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: nonBackgroundIdsOf(settled),
        recognition: mismatched,
        assembly: assembly,
      ),
      throwsStateError,
      reason: '归属 unitId 必须与块 sourceRefs 一致',
    );
  });

  test('反例 3：完整快照未剥离背景（页面框计入源集合）', () async {
    final scene = Scene().addElement(
      TextElement(
        id: const ElementId('page-frame'),
        x: 0,
        y: -100,
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
    );
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ], scene: scene);
    final settled = adapter.settle(result);
    final assembly = assembleOf(settled);
    final withBackground = {...nonBackgroundIdsOf(settled), 'page-frame'};
    expect(
      () => RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: withBackground,
        recognition: settled.ledger,
        assembly: assembly,
      ),
      throwsStateError,
      reason: '识别账本源集合必须等于完整捕获源集合−背景剥离集',
    );
  });

  test('未结算账本进入断言即拒绝', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final assembly = assembleOf(result);
    expect(
      () => RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: nonBackgroundIdsOf(result),
        recognition: result.ledger,
        assembly: assembly,
      ),
      throwsStateError,
      reason: 'pipeline 出口的 pending（待语义适配结算）不得进入候选链',
    );
  });
}
