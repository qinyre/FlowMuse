import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// V3-402A：阅读序流式放置、真实测量换行/缩档、原子组不拆、
/// 不可满足返回稳定原因（无裁字/估算/省略）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const placer = FlowPlacer();
  const tokens = SmartLayoutDesignTokens.v1;
  final measure = TextMeasureAdapter();

  CompositionCandidate candidate(
    double width, {
    bool twoColumn = false,
  }) =>
      CompositionCandidate(
        id: twoColumn ? 'twoColumn#0' : 'single#0',
        skeleton: twoColumn ? LayoutSkeleton.twoColumn : LayoutSkeleton.single,
        params: CompositionParams(
          columnGutter: tokens.columnGutter,
          pageMargin: tokens.pageMargin,
          mainColumnWidth: twoColumn ? (width - tokens.columnGutter) / 2 : width,
        ),
        index: 0,
      );

  TextBlockSpec specOf(
    String text, {
    double fontSize = 20,
    TextDirectionSpec direction = TextDirectionSpec.ltr,
  }) =>
      TextBlockSpec(
        text: text,
        fontFamily: 'Excalifont',
        fontSize: fontSize,
        lineHeight: tokens.lineHeight,
        direction: direction,
      );

  LayoutBlock textBlock(
    String id,
    String text, {
    LayoutBlockKind kind = LayoutBlockKind.paragraph,
    TextDirectionSpec direction = TextDirectionSpec.ltr,
  }) =>
      LayoutBlock(
        id: id,
        kind: kind,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: false,
        textOrigin: LayoutTextOrigin.typed,
        text: specOf(
          text,
          fontSize: kind == LayoutBlockKind.title ? 28 : 20,
          direction: direction,
        ),
      );

  LayoutBlock figureBlock(String id, double ratio) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.figure,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: true,
        figure: FigureBlockSpec(fileId: 'f-$id', displayAspectRatio: ratio),
      );

  LayoutBlockAssembly assemblyOf(
    List<LayoutBlock> blocks, {
    List<BlockRelationship> relationships = const [],
    List<List<String>> atomicGroups = const [],
  }) =>
      LayoutBlockAssembly(
        blocks: List.unmodifiable(blocks),
        relationships: List.unmodifiable(relationships),
        atomicGroups: List.unmodifiable(atomicGroups),
        documentConsumedSourceIds: const [],
        documentPreservedSourceIds: const [],
      );

  test('阅读序单栏放置：真实测量高度、垂直推进单调、行数为真', () {
    final outcome = placer.place(
      assembly: assemblyOf([
        textBlock('t1', '标题', kind: LayoutBlockKind.title),
        textBlock('p1', '第一段正文内容'),
        textBlock('p2', '第二段正文内容'),
      ]),
      candidate: candidate(600),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 600, height: 800),
      ],
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<FlowPlacementSuccess>());
    final success = outcome as FlowPlacementSuccess;
    expect(
      success.placed.map((p) => p.blockId).toList(),
      ['t1', 'p1', 'p2'],
      reason: '阅读序',
    );
    expect(success.placed.first.rect.top, 0);
    var lastBottom = -1.0;
    for (final p in success.placed) {
      expect(p.rect.height, greaterThan(0));
      expect(p.rect.top, greaterThan(lastBottom));
      expect(p.rect.width, lessThanOrEqualTo(600));
      lastBottom = p.rect.top + p.rect.height;
    }
    expect(success.usedHeights.single, greaterThan(0));
  });

  test('CJK/长词/emoji/RTL/公式：无裁字（成功或显式失败，永不静默）', () {
    const cases = <(String, TextDirectionSpec)>[
      ('智能排版把白板上的手写笔记整理成结构化文档', TextDirectionSpec.ltr),
      (
        'supercalifragilisticexpialidocious_antidisestablishmentarianism',
        TextDirectionSpec.ltr,
      ),
      ('🎉🎊🎈 emoji 表情与中文混排 🚀', TextDirectionSpec.ltr),
      ('نص باللغة العربية من اليمين إلى اليسار', TextDirectionSpec.rtl),
      ('a²+b²=c² 公式混合 x₁ᵢ', TextDirectionSpec.ltr),
    ];
    for (final (text, dir) in cases) {
      final outcome = placer.place(
        assembly: assemblyOf([textBlock('x1', text, direction: dir)]),
        candidate: candidate(400),
        columnRects: const [
          LayoutRect(left: 0, top: 0, width: 400, height: 600),
        ],
        contentHeight: 600,
        measure: measure,
        tokens: tokens,
      );
      if (outcome is FlowPlacementSuccess) {
        final placed = outcome.placed.single;
        expect(placed.rect.width, lessThanOrEqualTo(400),
            reason: '成功时宽不越栏（$text）');
        expect(placed.lineCount, greaterThan(0));
      } else {
        expect(
          (outcome as FlowPlacementFailure).kind,
          FlowPlacementFailureKind.blockOverflowsAtMinFontSize,
          reason: '失败必须显式稳定码（$text）',
        );
      }
    }
  });

  test('keep 原子组不拆：第一栏剩余不足时整组换栏且同栏连续', () {
    final pad = textBlock('pad', List.filled(240, '占').join());
    final assembly = assemblyOf(
      [
        pad,
        textBlock('t1', '章节标题', kind: LayoutBlockKind.title),
        textBlock('p1', '首段紧跟标题，不允许与标题分栏'),
      ],
      relationships: const [
        BlockRelationship(
          kind: BlockRelationKind.keepWith,
          fromBlockId: 't1',
          toBlockId: 'p1',
        ),
      ],
      atomicGroups: const [
        ['t1', 'p1'],
      ],
    );
    final outcome = placer.place(
      assembly: assembly,
      candidate: candidate(1200, twoColumn: true),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 588, height: 300),
        LayoutRect(left: 612, top: 0, width: 588, height: 300),
      ],
      contentHeight: 300,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<FlowPlacementSuccess>());
    final success = outcome as FlowPlacementSuccess;
    final t1 = success.placed.firstWhere((p) => p.blockId == 't1');
    final p1 = success.placed.firstWhere((p) => p.blockId == 'p1');
    expect(t1.columnIndex, p1.columnIndex, reason: 'keep 组同栏');
    expect(
      p1.rect.top,
      greaterThanOrEqualTo(t1.rect.top + t1.rect.height),
      reason: '组内连续',
    );
    expect(t1.columnIndex, 1, reason: '第一栏剩余不足时整组换栏');
  });

  test('不可满足：块高超过栏高 → 显式失败（不静默拆关系/缩小越线）', () {
    final tall = LayoutBlock(
      id: 'huge',
      kind: LayoutBlockKind.formula,
      sourceRefs: const ['huge'],
      orderIndex: 0,
      keepTogether: true,
      textOrigin: LayoutTextOrigin.typed,
      text: specOf(List.filled(400, '式').join()),
    );
    final outcome = placer.place(
      assembly: assemblyOf([tall]),
      candidate: candidate(500),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 500, height: 60),
      ],
      contentHeight: 60,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<FlowPlacementFailure>());
    final failure = outcome as FlowPlacementFailure;
    expect(
      failure.kind,
      anyOf(
        FlowPlacementFailureKind.keepGroupTooTall,
        FlowPlacementFailureKind.blockOverflowsAtMinFontSize,
      ),
      reason: '不可满足必须显式失败',
    );
    expect(failure.blockId, 'huge');
  });

  test('不可满足：末栏用尽 → columnsExhausted', () {
    final outcome = placer.place(
      assembly: assemblyOf([
        for (var i = 0; i < 30; i++) textBlock('p$i', '第$i段正文'),
      ]),
      candidate: candidate(1200, twoColumn: true),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 588, height: 120),
        LayoutRect(left: 612, top: 0, width: 588, height: 120),
      ],
      contentHeight: 120,
      measure: measure,
      tokens: tokens,
    );
    expect(
      (outcome as FlowPlacementFailure).kind,
      FlowPlacementFailureKind.columnsExhausted,
    );
  });

  test('字号缩档：token 档 28→20→12（步长 snapStep），不越 minBodySize', () {
    expect(tokens.titleFloorSize - tokens.snapStep, tokens.bodySize);
    expect(tokens.bodySize - tokens.snapStep, tokens.minBodySize);
    final outcome = placer.place(
      assembly: assemblyOf([
        textBlock('title', List.filled(24, '题').join(),
            kind: LayoutBlockKind.title),
      ]),
      candidate: candidate(260),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 260, height: 62),
      ],
      contentHeight: 62,
      measure: measure,
      tokens: tokens,
    );
    if (outcome is FlowPlacementSuccess) {
      final placed = outcome.placed.single;
      expect(placed.appliedFontSize, lessThanOrEqualTo(28));
      expect(
        placed.appliedFontSize,
        greaterThanOrEqualTo(tokens.minBodySize),
        reason: '不缩小越线',
      );
    } else {
      expect(
        (outcome as FlowPlacementFailure).kind,
        FlowPlacementFailureKind.blockOverflowsAtMinFontSize,
        reason: '缩到下限仍不行才失败',
      );
    }
  });

  test('figure 等比放置：宽=栏宽、高=宽/比例', () {
    final outcome = placer.place(
      assembly: assemblyOf([figureBlock('fig1', 2.0)]),
      candidate: candidate(400),
      columnRects: const [
        LayoutRect(left: 10, top: 0, width: 400, height: 500),
      ],
      contentHeight: 500,
      measure: measure,
      tokens: tokens,
    );
    final placed = (outcome as FlowPlacementSuccess).placed.single;
    expect(placed.rect.width, 400);
    expect(placed.rect.height, closeTo(200, 1e-9));
    expect(placed.rect.left, 10);
  });

  test('preserved/protected 不参与放置', () {
    final preserved = LayoutBlock(
      id: 'keep-me',
      kind: LayoutBlockKind.preserved,
      sourceRefs: const ['keep-me'],
      orderIndex: 0,
      keepTogether: true,
    );
    final outcome = placer.place(
      assembly: assemblyOf([preserved, textBlock('p1', '正文')]),
      candidate: candidate(400),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 400, height: 300),
      ],
      contentHeight: 300,
      measure: measure,
      tokens: tokens,
    );
    expect(
      (outcome as FlowPlacementSuccess).placed.map((p) => p.blockId),
      ['p1'],
    );
  });

  test('无文本文本块显式失败（不造数据）', () {
    final empty = LayoutBlock(
      id: 'void',
      kind: LayoutBlockKind.paragraph,
      sourceRefs: const ['void'],
      orderIndex: 0,
      keepTogether: false,
    );
    final outcome = placer.place(
      assembly: assemblyOf([empty]),
      candidate: candidate(400),
      columnRects: const [
        LayoutRect(left: 0, top: 0, width: 400, height: 300),
      ],
      contentHeight: 300,
      measure: measure,
      tokens: tokens,
    );
    expect(
      (outcome as FlowPlacementFailure).kind,
      FlowPlacementFailureKind.textualBlockWithoutContent,
    );
  });
}
