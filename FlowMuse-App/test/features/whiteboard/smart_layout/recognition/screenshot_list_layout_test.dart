import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';

import 'structure_test_helpers.dart';

/// §11 R6 截图场景：一标题一列表——适配产物经块装配后阅读序完整、
/// 标题与列表首项成原子组（放置不拆列的保护机制在 placementUnits）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  test('一标题一列表：角色/顺序/原子组（不拆列机制）', () async {
    // 截图识别结果的典型形态：大字标题 + 三个连续编号列表项。
    final result = await sessionOf(const [
      RegionSpec(
        regionId: 'r:title',
        top: 0,
        left: 0,
        text: '会议纪要',
        lineHeight: 40,
      ),
      RegionSpec(regionId: 'r:i1', top: 60, left: 0, text: '1. 第一项'),
      RegionSpec(regionId: 'r:i2', top: 90, left: 0, text: '2. 第二项'),
      RegionSpec(regionId: 'r:i3', top: 120, left: 0, text: '3. 第三项'),
    ]);
    final assembly = adapter.assemble(
      result,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    final document = assembly.document;

    // 角色：本地规则把编号连续行判为列表（R5 规则 1）。
    final roleOf = {for (final block in document.blocks) block.id: block.role};
    expect(roleOf['ink:r:i1'], SemanticRole.list);
    expect(roleOf['ink:r:i2'], SemanticRole.list);
    expect(roleOf['ink:r:i3'], SemanticRole.list);

    // 阅读序：列表子树连续（R-08 口径），不被其它单元穿插。
    final order = document.readingOrder.orderedBlockIds;
    final listPositions = [
      for (var i = 0; i < order.length; i++)
        if (order[i].startsWith('ink:r:i')) i,
    ];
    expect(listPositions, containsAllInOrder(const [1, 2, 3]));

    // 块装配：标题 keepWith 首个列表项 → 原子组不拆列。
    final snapshot = const SnapshotExtractor().extract(
      scene: result.scene,
      pageId: '',
      sceneRevision: SceneRevision(
        epoch: 0,
        revision: 5,
        fingerprint: SceneFingerprint.of(result.scene),
      ),
    );
    final blockAssembly = const LayoutBlockAssembler().assemble(
      document: document,
      snapshot: snapshot,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    expect(blockAssembly.ledgerConserved, isTrue);

    // 放置单元：标题与后继（列表首项）成组，同组不被切分点拆开。
    final units = FlowPlacer.placementUnits(blockAssembly);
    final titleUnit = units.firstWhere(
      (unit) => unit.any((b) => b.id == 'ink:r:title'),
    );
    expect(
      titleUnit.any((b) => b.id == 'ink:r:i1'),
      isTrue,
      reason: '标题 keepWith 列表首项：原子组同进同出',
    );
    // 列表三项全部进入放置流且保持阅读序。
    final placedIds = [
      for (final unit in units)
        for (final block in unit) block.id,
    ];
    final listIndices = placedIndices(placedIds, [
      'ink:r:i1',
      'ink:r:i2',
      'ink:r:i3',
    ]);
    expect(listIndices, hasLength(3));
    expect(listIndices[0] + 1, listIndices[1], reason: '列表项相邻不被穿插');
    expect(listIndices[1] + 1, listIndices[2]);
    // 字号档：标题 28、列表项 20（§8.2）。
    final titleBlock = blockAssembly.blocks.firstWhere(
      (b) => b.id == 'ink:r:title',
    );
    expect(titleBlock.text?.fontSize, tokens.titleFloorSize);
    final listBlock = blockAssembly.blocks.firstWhere(
      (b) => b.id == 'ink:r:i1',
    );
    expect(listBlock.text?.fontSize, tokens.bodySize);
    expect(listBlock.textOrigin, LayoutTextOrigin.transcribed);
  });
}

List<int> placedIndices(List<String> placedIds, List<String> wanted) {
  final positions = <int>[];
  for (final id in wanted) {
    final index = placedIds.indexOf(id);
    if (index >= 0) positions.add(index);
  }
  return positions;
}
