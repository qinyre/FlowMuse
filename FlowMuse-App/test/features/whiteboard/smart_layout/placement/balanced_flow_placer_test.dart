import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/balanced_flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// V3-402B：栏高平衡、页界 contain、protected 绕置、密度报告、
/// figure 等比/caption 栈、preserved 原位 golden。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const placer = BalancedFlowPlacer();
  const tokens = SmartLayoutDesignTokens.v1;
  final measure = TextMeasureAdapter();

  CompositionCandidate candidate({
    bool twoColumn = false,
  }) =>
      CompositionCandidate(
        id: twoColumn ? 'twoColumn#0' : 'single#0',
        skeleton: twoColumn ? LayoutSkeleton.twoColumn : LayoutSkeleton.single,
        params: CompositionParams(
          columnGutter: tokens.columnGutter,
          pageMargin: tokens.pageMargin,
          mainColumnWidth: 588,
        ),
        index: 0,
      );

  LayoutBlock para(String id, String text) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.paragraph,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: false,
        textOrigin: LayoutTextOrigin.typed,
        text: TextBlockSpec(
          text: text,
          fontFamily: 'Excalifont',
          fontSize: 20,
          lineHeight: tokens.lineHeight,
        ),
      );

  LayoutBlock preservedBlock(String id, Map<String, Object?> bounds) =>
      LayoutBlock(
        id: id,
        kind: LayoutBlockKind.preserved,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: true,
        extras: {'bounds': bounds},
      );

  LayoutBlock protectedBlock(
    String id,
    LayoutRect rect,
  ) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.protected,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: true,
        extras: {
          'bounds': {
            'left': rect.left,
            'top': rect.top,
            'width': rect.width,
            'height': rect.height,
          },
        },
      );

  LayoutBlockAssembly assemblyOf(List<LayoutBlock> blocks,
          {List<List<String>> groups = const []}) =>
      LayoutBlockAssembly(
        blocks: List.unmodifiable(blocks),
        relationships: const [],
        atomicGroups: List.unmodifiable(groups),
        documentConsumedSourceIds: const [],
        documentPreservedSourceIds: const [],
      );

  const content = LayoutRect(left: 0, top: 0, width: 1200, height: 800);
  const columns2 = [
    LayoutRect(left: 0, top: 0, width: 588, height: 800),
    LayoutRect(left: 612, top: 0, width: 588, height: 800),
  ];

  test('栏高平衡：两栏最大已用高小于顺序流，阅读序保持', () {
    final blocks = [
      para('a', List.filled(40, '甲').join()),
      para('b', List.filled(40, '乙').join()),
      para('c', List.filled(40, '丙').join()),
      para('d', List.filled(40, '丁').join()),
    ];
    final outcome = placer.placeBalanced(
      assembly: assemblyOf(blocks),
      candidate: candidate(twoColumn: true),
      pageContent: content,
      columnRects: columns2,
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<BalancedPlacement>());
    final balanced = outcome as BalancedPlacement;
    // 顺序流基线：同一 fixture 走 402A 语义（栏 0 放不下才溢栏），
    // 4 段全进栏 0 → usedHeights=[总高, 0]。
    final sequential = const FlowPlacer().place(
      assembly: assemblyOf(blocks),
      candidate: candidate(twoColumn: true),
      columnRects: columns2,
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    ) as FlowPlacementSuccess;
    final sequentialMax = sequential.usedHeights.reduce(
      (a, b) => a > b ? a : b,
    );
    final balancedMax = balanced.usedHeights.reduce((a, b) => a > b ? a : b);
    expect(balancedMax, lessThan(sequentialMax),
        reason: '平衡切分必须优于顺序流');
    // 阅读序：栏 0 的内容全部先于栏 1（orderIndex 序在栏序上单调）。
    final order = {
      for (var i = 0; i < blocks.length; i++) blocks[i].id: i,
    };
    var lastColumn = 0;
    for (final p in balanced.placed) {
      expect(p.columnIndex, greaterThanOrEqualTo(lastColumn),
          reason: '阅读序跨栏单调');
      lastColumn = p.columnIndex;
    }
    expect(order[balanced.placed.first.blockId], lessThan(order[balanced.placed.last.blockId]!));
  });

  test('页界 contain：全部放置盒 ⊆ 内容区', () {
    final outcome = placer.placeBalanced(
      assembly: assemblyOf([para('a', '短文')]),
      candidate: candidate(),
      pageContent: content,
      columnRects: const [LayoutRect(left: 0, top: 0, width: 588, height: 800)],
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    final balanced = outcome as BalancedPlacement;
    for (final p in balanced.placed) {
      expect(content.containsRect(p.rect), isTrue, reason: p.blockId);
    }
  });

  test('protected 绕置：障碍切割段流，零硬碰撞', () {
    // 障碍占栏 0 中部 y∈[300,400]。
    final obstacle = const LayoutRect(left: 100, top: 300, width: 380, height: 100);
    final outcome = placer.placeBalanced(
      assembly: assemblyOf([
        protectedBlock('lock-1', obstacle),
        para('a', List.filled(60, '文').join()),
        para('b', List.filled(60, '字').join()),
      ]),
      candidate: candidate(),
      pageContent: content,
      columnRects: const [LayoutRect(left: 0, top: 0, width: 588, height: 800)],
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<BalancedPlacement>());
    final balanced = outcome as BalancedPlacement;
    // 构造性零碰撞 + 防御复核：任何放置盒不与障碍相交。
    for (final p in balanced.placed) {
      expect(p.rect.intersects(obstacle), isFalse,
          reason: '${p.blockId} 硬碰撞');
    }
    // protected 原位投影（golden 输入；键 = 块 id）。
    expect(balanced.preservedRects['lock-1'], obstacle);
  });

  test('protected 全覆盖栏 → columnsExhausted', () {
    final outcome = placer.placeBalanced(
      assembly: assemblyOf([
        protectedBlock(
          'wall',
          const LayoutRect(left: 0, top: 0, width: 588, height: 800),
        ),
        para('a', '内容'),
      ]),
      candidate: candidate(),
      pageContent: content,
      columnRects: const [LayoutRect(left: 0, top: 0, width: 588, height: 800)],
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<BalancedPlacementFailure>());
    expect(
      (outcome as BalancedPlacementFailure).kind,
      FlowPlacementFailureKind.columnsExhausted,
    );
  });

  test('figure 等比不变 + caption 栈（golden geometry 确定）', () {
    final figure = LayoutBlock(
      id: 'fig',
      kind: LayoutBlockKind.figure,
      sourceRefs: const ['fig'],
      orderIndex: 0,
      keepTogether: true,
      figure: const FigureBlockSpec(
        fileId: 'f1',
        displayAspectRatio: 1.5,
      ),
    );
    final caption = LayoutBlock(
      id: 'cap',
      kind: LayoutBlockKind.caption,
      sourceRefs: const ['cap'],
      orderIndex: 1,
      keepTogether: false,
      textOrigin: LayoutTextOrigin.typed,
      text: TextBlockSpec(
        text: '图 1 示意',
        fontFamily: 'Excalifont',
        fontSize: 20,
        lineHeight: tokens.lineHeight,
      ),
    );
    final assembly = assemblyOf([figure, caption], groups: const [
      ['fig', 'cap'],
    ]);
    Object run() => placer.placeBalanced(
          assembly: assembly,
          candidate: candidate(),
          pageContent: content,
          columnRects: const [
            LayoutRect(left: 0, top: 0, width: 588, height: 800),
          ],
          contentHeight: 800,
          measure: measure,
          tokens: tokens,
        );
    final first = run() as BalancedPlacement;
    final second = run() as BalancedPlacement;
    final fig = first.placed.firstWhere((p) => p.blockId == 'fig');
    final cap = first.placed.firstWhere((p) => p.blockId == 'cap');
    // 等比：ratio = w/h 不变（1.5）。
    expect(fig.rect.width / fig.rect.height, closeTo(1.5, 1e-9));
    // caption 栈：同栏且在 figure 正下方。
    expect(cap.columnIndex, fig.columnIndex);
    expect(cap.rect.top, greaterThanOrEqualTo(fig.rect.top + fig.rect.height));
    // golden：双跑一致（结果确定）。
    expect(second.goldenHash, first.goldenHash);
    expect(first.density, inInclusiveRange(0, 1));
  });

  test('preserved 路径：原位坐标进入 golden，不参与重排', () {
    final preserved = preservedBlock('keep', {
      'left': 950.0,
      'top': 700.0,
      'width': 120.0,
      'height': 60.0,
    });
    final outcome = placer.placeBalanced(
      assembly: assemblyOf([preserved, para('a', '正文')]),
      candidate: candidate(),
      pageContent: content,
      columnRects: const [LayoutRect(left: 0, top: 0, width: 588, height: 800)],
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    final balanced = outcome as BalancedPlacement;
    expect(
      balanced.preservedRects['keep'],
      const LayoutRect(left: 950, top: 700, width: 120, height: 60),
      reason: '保留路径原位坐标',
    );
    expect(
      balanced.placed.map((p) => p.blockId),
      isNot(contains('keep')),
      reason: 'preserved 不参与重排',
    );
  });

  test('综合 fixture：多块+figure+protected+双栏，零硬碰撞且 golden 确定',
      () {
    final obstacle = const LayoutRect(left: 640, top: 100, width: 300, height: 80);
    final blocks = [
      for (var i = 0; i < 6; i++)
        para('p$i', List.filled(30, '段$i').join()),
      LayoutBlock(
        id: 'fig1',
        kind: LayoutBlockKind.figure,
        sourceRefs: const ['fig1'],
        orderIndex: 0,
        keepTogether: true,
        figure: const FigureBlockSpec(fileId: 'f9', displayAspectRatio: 2.0),
      ),
      protectedBlock('lock', obstacle),
      preservedBlock('keep', {
        'left': 1100.0,
        'top': 750.0,
        'width': 80.0,
        'height': 40.0,
      }),
    ];
    Object run() => placer.placeBalanced(
          assembly: assemblyOf(blocks),
          candidate: candidate(twoColumn: true),
          pageContent: content,
          columnRects: columns2,
          contentHeight: 800,
          measure: measure,
          tokens: tokens,
        );
    final first = run();
    final second = run();
    expect(first, isA<BalancedPlacement>());
    final balanced = first as BalancedPlacement;
    for (final p in balanced.placed) {
      expect(p.rect.intersects(obstacle), isFalse, reason: '${p.blockId} 零硬碰撞');
      expect(content.containsRect(p.rect), isTrue);
    }
    expect(
      (second as BalancedPlacement).goldenHash,
      balanced.goldenHash,
      reason: '综合 fixture 双跑 golden 一致',
    );
  });
}
