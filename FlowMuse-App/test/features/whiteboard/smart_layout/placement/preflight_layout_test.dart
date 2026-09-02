import 'dart:io';
import 'dart:ui' as ui;

import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/preflight_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// V3-403A：生成期硬 preflight 四型分型——无解/内部错误/可重试/零修改
/// preserveFallback；preflight 无 scorer 通道；reject 可映射建议。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const tokens = SmartLayoutDesignTokens.v1;
  const preflight = LayoutPreflight();
  final measure = TextMeasureAdapter();

  List<CompositionCandidate> enumerateAll() => const LayoutCompositionPlanner()
      .enumerate(
        constraint: CompositionConstraint(
          contentWidth: 1200,
          tokens: tokens,
        ),
      )
      .candidates;

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

  LayoutBlock protectedBlock(String id, LayoutRect rect) => LayoutBlock(
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

  LayoutBlockAssembly assemblyOf(
    List<LayoutBlock> blocks, {
    List<String> consumed = const [],
    List<String> preserved = const [],
  }) => LayoutBlockAssembly(
        blocks: List.unmodifiable(blocks),
        relationships: const [],
        atomicGroups: const [],
        documentConsumedSourceIds: consumed,
        documentPreservedSourceIds: preserved,
      );

  LayoutBlockAssembly simpleAssembly(List<LayoutBlock> blocks) =>
      assemblyOf(
        blocks,
        consumed: [for (final b in blocks) b.id],
      );

  test('全候选硬下界超出 → NoFeasibleLayout + splitIntoPages + 零修改 fallback', () {
    // 3 个短段（最小字号 12 单行 h=15）：LB(single)=45+16=61、
    // LB(twoCol/mainSide)=45+8=53；H=26 → 53 > 2×26=52，全部拒绝。
    final assembly = simpleAssembly(
      [para('a', '短文'), para('b', '正文'), para('c', '内容')],
    );
    final candidates = enumerateAll();
    final outcome = preflight.screen(
      assembly: assembly,
      candidates: candidates,
      contentHeight: 26,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<NoFeasibleLayout>());
    final no = outcome as NoFeasibleLayout;
    expect(no.rejectedCandidateCount, candidates.length);
    for (final r in no.rejections) {
      expect(r.reason, PreflightRejectReason.hardHeightLowerBoundExceeded,
          reason: r.candidateId);
    }
    expect(no.suggestions, [LayoutSuggestion.splitIntoPages]);
    // fallback 伴随但不替代无解（no-candidate rate 不被稀释）。
    expect(no.fallback.reason, PreserveFallbackReason.allCandidatesInfeasible);
    expect(no.fallback.preservedSourceIds, ['a', 'b', 'c']);
    // 确定性：双跑拒绝序列一致。
    final again = preflight.screen(
      assembly: assembly,
      candidates: candidates,
      contentHeight: 26,
      measure: measure,
      tokens: tokens,
    ) as NoFeasibleLayout;
    expect(
      again.rejections.map((r) => '${r.candidateId}:${r.reason.name}').toList(),
      no.rejections.map((r) => '${r.candidateId}:${r.reason.name}').toList(),
    );
  });

  test('LB 分型钉子：同 Σh 下 single 拒、twoColumn 收（k=2 摊倍）', () {
    // 2 短段：LB(single)=30+8=38 > H=30 拒；LB(twoColumn)=30 ≤ 60 收。
    final outcome = preflight.screen(
      assembly: simpleAssembly([para('a', '短文'), para('b', '正文')]),
      candidates: enumerateAll(),
      contentHeight: 30,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<LayoutGenerationScreened>());
    final screened = outcome as LayoutGenerationScreened;
    final rejectedIds = {
      for (final r in screened.rejected) r.candidateId,
    };
    expect(rejectedIds, containsAll(['single#0', 'conservativeLayout#8']));
    expect(
      screened.accepted.map((c) => c.id),
      contains('twoColumn#1'),
    );
    for (final r in screened.rejected) {
      expect(r.reason, PreflightRejectReason.hardHeightLowerBoundExceeded);
    }
  });

  test('原子簇宽于最窄栏（最小字号）→ 部分拒绝 + widenColumns', () {
    // 适配器契约情形："原子字素簇宽于栏宽" 时 overflows=true（真实
    // TextPainter 会折断可断内容，长英文词不属此类）。用固定 1000px
    // 不可断簇的 fake 钉住分型：窄于它的栏（twoColumn 588、
    // conservative 560、mainSide 侧栏 ≤560）全拒，single(1200) 收。
    final outcome = preflight.screen(
      assembly: simpleAssembly([para('wide', '正文')]),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: _WideClusterMeasure(),
      tokens: tokens,
    );
    expect(outcome, isA<LayoutGenerationScreened>());
    final screened = outcome as LayoutGenerationScreened;
    expect(screened.accepted.map((c) => c.id), ['single#0']);
    expect(screened.rejected.length, 8);
    for (final r in screened.rejected) {
      expect(r.reason, PreflightRejectReason.blockWiderThanNarrowestColumnAtMinSize,
          reason: r.candidateId);
      expect(r.suggestions, [LayoutSuggestion.widenColumns]);
    }
  });

  test('protected 吃满全部栏 → protectedColumnFullyCovered + reduceProtectedZones（优先于 LB）', () {
    final outcome = preflight.screen(
      assembly: assemblyOf(
        [
          para('a', '正文'),
          protectedBlock('wall', const LayoutRect(left: 0, top: 0, width: 1200, height: 800)),
        ],
        consumed: ['a'],
        preserved: ['wall'],
      ),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<NoFeasibleLayout>());
    final no = outcome as NoFeasibleLayout;
    for (final r in no.rejections) {
      expect(r.reason, PreflightRejectReason.protectedColumnFullyCovered,
          reason: r.candidateId);
    }
    expect(no.suggestions, [LayoutSuggestion.reduceProtectedZones]);
    // 障碍原位进入零修改保留路径。
    expect(no.fallback.preservedSourceIds, ['a', 'wall']);
  });

  test('文本块无 spec → textualBlockWithoutContent + fixSourceContent', () {
    final ghost = LayoutBlock(
      id: 'g',
      kind: LayoutBlockKind.paragraph,
      sourceRefs: const ['g'],
      orderIndex: 0,
      keepTogether: false,
    );
    final outcome = preflight.screen(
      assembly: simpleAssembly([ghost, para('a', '正文')]),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<NoFeasibleLayout>());
    for (final r in (outcome as NoFeasibleLayout).rejections) {
      expect(r.reason, PreflightRejectReason.textualBlockWithoutContent);
      expect(r.suggestions, [LayoutSuggestion.fixSourceContent]);
    }
  });

  test('空文档（全 preserved/protected）→ PreserveFallback emptyDocument，非无解', () {
    final keep = LayoutBlock(
      id: 'k2',
      kind: LayoutBlockKind.preserved,
      sourceRefs: const ['k2'],
      orderIndex: 0,
      keepTogether: true,
      extras: const {
        'bounds': {'left': 10.0, 'top': 10.0, 'width': 50.0, 'height': 20.0},
      },
    );
    final outcome = preflight.screen(
      assembly: assemblyOf(
        [keep, protectedBlock('k1', const LayoutRect(left: 0, top: 300, width: 100, height: 50))],
        preserved: ['k2', 'k1'],
      ),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<PreserveFallback>());
    expect(outcome, isNot(isA<NoFeasibleLayout>()));
    final fallback = outcome as PreserveFallback;
    expect(fallback.reason, PreserveFallbackReason.emptyDocument);
    expect(fallback.preservedSourceIds, ['k1', 'k2']);
  });

  test('测量依赖异常 → RetryableGenerationFailure（非内部错误）', () {
    final outcome = preflight.screen(
      assembly: simpleAssembly([para('a', '正文')]),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: _UnavailableMeasure(),
      tokens: tokens,
    );
    expect(outcome, isA<RetryableGenerationFailure>());
    final retry = outcome as RetryableGenerationFailure;
    expect(retry.dependency, 'text-measure');
    expect(retry, isNot(isA<InternalGenerationError>()));
  });

  test('程序缺陷 → InternalGenerationError（空候选域 / ledger 不守恒）', () {
    expect(
      preflight.screen(
        assembly: simpleAssembly([para('a', '正文')]),
        candidates: const [],
        contentHeight: 800,
        measure: measure,
        tokens: tokens,
      ),
      isA<InternalGenerationError>(),
    );
    final broken = LayoutBlockAssembly(
      blocks: List.unmodifiable([para('a', '正文')]),
      relationships: const [],
      atomicGroups: const [],
      documentConsumedSourceIds: const ['a', 'ghost'],
      documentPreservedSourceIds: const [],
    );
    final outcome = preflight.screen(
      assembly: broken,
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(outcome, isA<InternalGenerationError>());
    expect(
      (outcome as InternalGenerationError).detail,
      contains('ledger'),
    );
  });

  test('preflight 无 scorer/metrics/profile 通道（源码门禁）', () {
    final source = File(
      'lib/features/whiteboard/smart_layout/placement/preflight_layout.dart',
    ).readAsStringSync();
    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('import ')) {
        expect(
          RegExp(r'(scorer|metrics|profile)\.dart').hasMatch(trimmed),
          isFalse,
          reason: 'preflight 不得依赖软分/指标/profile: $trimmed',
        );
      }
    }
    expect(source.contains('Scorer'), isFalse);
    // PreserveFallback 不携带候选字段（score/skeleton/params/structureHash）。
    final body = source.split('class PreserveFallback')[1].split('\nclass ')[0];
    expect(
      RegExp(r'\b(score|skeleton|params|structureHash)\b').hasMatch(body),
      isFalse,
      reason: 'PreserveFallback 不是候选，不得出现候选字段',
    );
  });

  test('建议映射完备：每个拒绝原因/放置失败稳定码都有非空建议', () {
    for (final reason in PreflightRejectReason.values) {
      expect(suggestionsFor(reason), isNotEmpty, reason: reason.name);
    }
    for (final kind in FlowPlacementFailureKind.values) {
      expect(suggestionsForPlacementFailure(kind), isNotEmpty,
          reason: kind.name);
    }
    expect(
      suggestionsFor(PreflightRejectReason.protectedColumnFullyCovered),
      [LayoutSuggestion.reduceProtectedZones],
    );
  });

  test('NoFeasibleLayout.fromPlacementFailures：放置失败 → 稳定原因/建议/fallback', () {
    final no = NoFeasibleLayout.fromPlacementFailures(
      [
        ('single#0', const FlowPlacementFailure(kind: FlowPlacementFailureKind.keepGroupTooTall, blockId: 'g', detail: 'd1')),
        ('twoColumn#1', const FlowPlacementFailure(kind: FlowPlacementFailureKind.blockOverflowsAtMinFontSize, blockId: 'b', detail: 'd2')),
        ('mainSide#2', const FlowPlacementFailure(kind: FlowPlacementFailureKind.columnsExhausted, blockId: 'c', detail: 'd3')),
        ('conservativeLayout#8', const FlowPlacementFailure(kind: FlowPlacementFailureKind.textualBlockWithoutContent, blockId: 't', detail: 'd4')),
      ],
      documentSourceIds: ['a', 'b'],
    );
    expect(no.rejectedCandidateCount, 4);
    expect(
      no.rejections.map((r) => r.reason).toList(),
      [
        PreflightRejectReason.hardHeightLowerBoundExceeded,
        PreflightRejectReason.blockWiderThanNarrowestColumnAtMinSize,
        PreflightRejectReason.hardHeightLowerBoundExceeded,
        PreflightRejectReason.textualBlockWithoutContent,
      ],
    );
    expect(no.suggestions, [
      LayoutSuggestion.splitIntoPages,
      LayoutSuggestion.widenColumns,
      LayoutSuggestion.fixSourceContent,
    ]);
    expect(no.fallback.reason, PreserveFallbackReason.allCandidatesInfeasible);
  });

  test('放置全失败兜底与 preflight 同源：fallback 不进候选域', () {
    // 编译期契约：PreserveFallback 不是 CompositionCandidate；成功型
    // 结果只暴露 accepted 候选——fallback 无通道进入配额/Top3。
    final screened = preflight.screen(
      assembly: simpleAssembly([para('a', '正文')]),
      candidates: enumerateAll(),
      contentHeight: 800,
      measure: measure,
      tokens: tokens,
    );
    expect(screened, isA<LayoutGenerationScreened>());
    expect(
      (screened as LayoutGenerationScreened).accepted,
      isNot(contains(isA<PreserveFallback>())),
    );
  });
}

/// 模拟测量依赖不可用（字体资产加载失败等瞬时故障）。
class _UnavailableMeasure extends TextMeasureAdapter {
  @override
  TextMeasureResult measure({
    required String text,
    required String fontFamily,
    required double fontSize,
    double? lineHeight,
    double? maxWidth,
    ui.TextDirection direction = ui.TextDirection.ltr,
  }) => throw Exception('font asset unavailable');
}

/// 模拟"原子字素簇宽于栏宽"（适配器契约：overflows = 簇宽 > 栏宽；
/// 簇宽固定 1000px、单行高 15）。
class _WideClusterMeasure extends TextMeasureAdapter {
  @override
  TextMeasureResult measure({
    required String text,
    required String fontFamily,
    required double fontSize,
    double? lineHeight,
    double? maxWidth,
    ui.TextDirection direction = ui.TextDirection.ltr,
  }) =>
      TextMeasureResult(
        width: 1000,
        height: 15,
        lineCount: 1,
        maxWidth: maxWidth ?? double.infinity,
        overflows: maxWidth != null && 1000 > maxWidth,
      );
}
