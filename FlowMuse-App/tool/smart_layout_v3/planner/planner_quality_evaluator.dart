import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/composition/hard_feasibility_pruning.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_composition_planner.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_structure_signature.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/balanced_flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/preflight_layout.dart';

/// G3 规划质量评估器（V3-406A；经 flutter test 执行）：
///   flutter test tool/smart_layout_v3/planner/planner_quality_cli_test.dart
///
/// 确定性 fixture 集上跑完整生成链（401A 枚举 → 403A 硬 preflight →
/// 402B 栏平衡放置 → 405A 结构签名去重），与**独立 oracle**（对全部
/// 域候选直接放置，成功即可行）对照，汇总：
/// 漏解（oracle 可行但被 preflight 拒）、误判（宣称无解但 oracle 有解）、
/// 结构多样性（各 skeleton 单独报告）、确定性（双跑 canonical 相等）、
/// 最差分组、性能（确定性尝试次数 + 预算；墙钟仅记录不参与判定）、
/// 契约版本与复现命令。
///
/// 机器判定（全局冻结，禁止单张 fixture 调参绕过）：
///   missed_feasible==0 && false_no_feasible==0 && determinism_failures==0
///   && unique_skeletons_accepted>=4 && placement_attempts<=budget
class PlannerQualityEvaluator {
  const PlannerQualityEvaluator({this.budget = 300});

  /// 确定性操作预算（放置尝试次数上限；fixtures×域×(管线+oracle)×2 跑）。
  final int budget;

  static const String evidenceRoot =
      '../docs/研发记录/evidence/smart-layout-v3/gates/G3';

  Report execute({void Function(String)? log}) {
    final logLine = log ?? stdout.writeln;
    final stopwatch = Stopwatch()..start();
    final fixtures = buildFixtures();
    final cells = <FixtureCell>[];
    var placementAttempts = 0;
    for (final fixture in fixtures) {
      final cell = _evaluateFixture(fixture, (n) => placementAttempts += n);
      cells.add(cell);
      logLine(
        'G3 fixture ${fixture.id}: accepted=${cell.screenAccepted} '
        'rejected=${cell.screenRejected} placed=${cell.placedSucceeded} '
        'missed=${cell.missedFeasible.length} '
        'falseNoFeasible=${cell.falseNoFeasible} '
        'determinism=${cell.determinismEqual}',
      );
    }

    final missedTotal = cells
        .map((c) => c.missedFeasible.length)
        .reduce((a, b) => a + b);
    final falseNoFeasibleTotal = cells
        .map((c) => c.falseNoFeasible ? 1 : 0)
        .reduce((a, b) => a + b);
    final determinismFailures = cells
        .map((c) => c.determinismEqual ? 0 : 1)
        .reduce((a, b) => a + b);
    final uniqueSkeletons = <String>{
      for (final cell in cells)
        for (final s in cell.acceptedSkeletons) s,
    }.length;

    // 各 skeleton 单独报告（fixture 数、接受数、放置成功数）。
    final perSkeleton = <String, Map<String, Object?>>{};
    for (final skeleton in LayoutSkeleton.values) {
      final name = skeleton.name;
      final cellsWithSkeletonDomain = cells
          .where((c) => c.domainSkeletons.contains(name))
          .toList();
      final accepted = cells
          .where((c) => c.acceptedSkeletons.contains(name))
          .length;
      perSkeleton[name] = {
        'fixtures_in_domain': cellsWithSkeletonDomain.length,
        'fixtures_accepted': accepted,
        'accepted_ids': [
          for (final c in cells)
            for (final id in c.acceptedCandidateIds)
              if (id.startsWith('$name#')) id,
        ],
      };
    }

    // 最差分组（逐维度挑最差 fixture；信息性 + 留档）。
    FixtureCell worstBy<T extends num>(T Function(FixtureCell) measure) =>
        cells.reduce((a, b) => measure(b) > measure(a) ? b : a);

    final verdict =
        missedTotal == 0 &&
            falseNoFeasibleTotal == 0 &&
            determinismFailures == 0 &&
            uniqueSkeletons >= 4 &&
            placementAttempts <= budget;
    final report = Report(
      generatedAtUtc: DateTime.now().toUtc().toIso8601String(),
      contractVersions: {
        'design_tokens': 'v1',
        'metric_contract': LayoutMetricContract.version,
        'rubric_version': LayoutMetricContract.rubricVersion,
        'metric_rubric_dimension': LayoutMetricContract.rubricDimension,
        'structure_signature': 'v1',
        'planner_quota': LayoutCompositionPlanner.defaultQuota,
        'prune_verdicts': [
          for (final v in PruneVerdict.values) v.name,
        ],
      },
      reproductionCommands: [
        'flutter test tool/smart_layout_v3/planner/planner_quality_cli_test.dart',
        'powershell -NoProfile -ExecutionPolicy Bypass -File '
            'scripts/smart-layout-v3/AgentExecution.ps1 -Action Gate -GateId G3',
      ],
      fixtures: cells,
      perSkeleton: perSkeleton,
      summary: {
        'fixtures': cells.length,
        'missed_feasible': missedTotal,
        'false_no_feasible': falseNoFeasibleTotal,
        'determinism_failures': determinismFailures,
        'unique_skeletons_accepted': uniqueSkeletons,
        'placement_attempts': placementAttempts,
        'budget': budget,
      },
      worstGroup: {
        'most_rejections': worstBy((c) => c.screenRejected.length).fixtureId,
        'most_placement_failures': worstBy(
          (c) => c.placedFailed,
        ).fixtureId,
        'lowest_diversity': cells
            .reduce((a, b) =>
                a.acceptedSkeletons.length <= b.acceptedSkeletons.length
                    ? a
                    : b)
            .fixtureId,
      },
      verdictRule:
          'missed_feasible==0 && false_no_feasible==0 && '
          'determinism_failures==0 && unique_skeletons_accepted>=4 && '
          'placement_attempts<=budget',
      verdict: verdict ? 'pass' : 'fail',
      elapsedMs: stopwatch.elapsedMilliseconds,
    );

    final outDir = Directory(evidenceRoot);
    outDir.createSync(recursive: true);
    _writeJson(outDir, 'planner-quality-report.json', report.toJson());
    _writeJson(outDir, 'gate-three-report.json', {
      'gate': 'G3',
      'terminal_task': 'V3-406A',
      'status': report.verdict,
      'summary': report.summary,
      'worst_group': report.worstGroup,
      'per_skeleton': perSkeleton,
      'contract_versions': report.contractVersions,
      'reproduction_commands': report.reproductionCommands,
      'generated_at_utc': report.generatedAtUtc,
    });
    return report;
  }

  FixtureCell _evaluateFixture(
    Fixture fixture,
    void Function(int) countAttempt,
  ) {
    final tokens = SmartLayoutDesignTokens.v1;
    final measure = TextMeasureAdapter();
    final enumeration = const LayoutCompositionPlanner().enumerate(
      constraint: CompositionConstraint(
        contentWidth: fixture.contentWidth,
        tokens: tokens,
      ),
    );
    final domain = enumeration.candidates;

    // 管线：preflight → 放置 → 去重。
    PipelineRun run() {
      final screen = const LayoutPreflight().screen(
        assembly: fixture.assembly,
        candidates: domain,
        contentHeight: fixture.contentHeight,
        measure: measure,
        tokens: tokens,
      );
      if (screen is NoFeasibleLayout) {
        return PipelineRun(
          screenAccepted: const [],
          screenRejected: [
            for (final r in screen.rejections) r.candidateId,
          ],
          placedSucceeded: const [],
          placedFailed: const {},
          dedupKept: const [],
          dedupDropped: const {},
          noFeasible: true,
          canonical: 'no-feasible|${screen.rejections.map((r) => r.candidateId).join(',')}',
        );
      }
      final screened = screen as LayoutGenerationScreened;
      final succeeded = <String, BalancedPlacement>{};
      final failed = <String, String>{};
      for (final candidate in screened.accepted) {
        countAttempt(1);
        final outcome = const BalancedFlowPlacer().placeBalanced(
          assembly: fixture.assembly,
          candidate: candidate,
          pageContent: LayoutRect(
            left: 0,
            top: 0,
            width: fixture.contentWidth,
            height: fixture.contentHeight,
          ),
          columnRects: _columnsOf(candidate, fixture.contentHeight),
          contentHeight: fixture.contentHeight,
          measure: measure,
          tokens: tokens,
        );
        if (outcome is BalancedPlacement) {
          succeeded[candidate.id] = outcome;
        } else {
          failed[candidate.id] = (outcome as BalancedPlacementFailure)
              .kind
              .name;
        }
      }
      final dedup = const LayoutPlacementDeduplicator().dedupe([
        for (final entry in succeeded.entries)
          PlacementEntry(
            candidateId: entry.key,
            skeleton: domain
                .firstWhere((c) => c.id == entry.key)
                .skeleton,
            placed: entry.value.placed,
          ),
      ]);
      return PipelineRun(
        screenAccepted: [for (final c in screened.accepted) c.id],
        screenRejected: [
          for (final r in screened.rejected) r.candidateId,
        ],
        placedSucceeded: succeeded.keys.toList(),
        placedFailed: failed,
        dedupKept: [for (final k in dedup.kept) k.candidateId],
        dedupDropped: {
          for (final d in dedup.dropped)
            d.candidateId: d.equivalentToCandidateId,
        },
        noFeasible: false,
        canonical: jsonEncode({
          'accepted': screened.accepted.map((c) => c.id).toList(),
          'placed': {
            for (final e in succeeded.entries)
              e.key: e.value.goldenHash,
          },
          'failed': failed,
          'dedupKept': [for (final k in dedup.kept) k.candidateId],
        }),
      );
    }

    final first = run();
    final second = run();

    // 独立 oracle：对全部域候选（含被 preflight 拒的）直接放置。
    final oracleFeasible = <String>[];
    for (final candidate in domain) {
      countAttempt(1);
      final outcome = const BalancedFlowPlacer().placeBalanced(
        assembly: fixture.assembly,
        candidate: candidate,
        pageContent: LayoutRect(
          left: 0,
          top: 0,
          width: fixture.contentWidth,
          height: fixture.contentHeight,
        ),
        columnRects: _columnsOf(candidate, fixture.contentHeight),
        contentHeight: fixture.contentHeight,
        measure: measure,
        tokens: tokens,
      );
      if (outcome is BalancedPlacement) oracleFeasible.add(candidate.id);
    }

    // 漏解：oracle 可行但被 preflight 拒（误剪）。
    final missed = oracleFeasible
        .where((id) => first.screenRejected.contains(id))
        .toList();
    // 误判：管线宣称无解但 oracle 有解。
    final falseNoFeasible = first.noFeasible && oracleFeasible.isNotEmpty;

    return FixtureCell(
      fixtureId: fixture.id,
      scenario: fixture.scenario,
      blockCount: fixture.assembly.blocks.length,
      domainSize: domain.length,
      domainSkeletons: {
        for (final c in domain) c.skeleton.name,
      }.toList(),
      screenAccepted: first.screenAccepted,
      screenRejected: first.screenRejected,
      acceptedCandidateIds: first.placedSucceeded,
      acceptedSkeletons: {
        for (final id in first.placedSucceeded)
          domain.firstWhere((c) => c.id == id).skeleton.name,
      }.toList(),
      placedSucceeded: first.placedSucceeded.length,
      placedFailed: first.placedFailed.length,
      placementFailureKinds: {
        for (final e in first.placedFailed.entries)
          e.value: (first.placedFailed.values
                  .where((k) => k == e.value)
                  .length),
      },
      dedupKept: first.dedupKept,
      dedupDropped: first.dedupDropped,
      oracleFeasible: oracleFeasible,
      missedFeasible: missed,
      falseNoFeasible: falseNoFeasible,
      determinismEqual: first.canonical == second.canonical,
    );
  }

  /// 候选栏几何（与 preflight/planner 同源推导：single/conservative
  /// 全宽、twoColumn 等分、mainSide 主+侧按 sideOnRight 排列）。
  static List<LayoutRect> _columnsOf(
    CompositionCandidate candidate,
    double contentHeight,
  ) {
    final p = candidate.params;
    LayoutRect rect(double left, double width) => LayoutRect(
          left: left,
          top: 0,
          width: width,
          height: contentHeight,
        );
    final widths = switch (candidate.skeleton) {
      LayoutSkeleton.single => [p.mainColumnWidth],
      LayoutSkeleton.twoColumn => [p.mainColumnWidth, p.mainColumnWidth],
      LayoutSkeleton.mainSide => p.sideOnRight
          ? [p.mainColumnWidth, p.sideColumnWidth!]
          : [p.sideColumnWidth!, p.mainColumnWidth],
      LayoutSkeleton.conservativeLayout => [p.mainColumnWidth],
    };
    final rects = <LayoutRect>[];
    var left = 0.0;
    for (var i = 0; i < widths.length; i++) {
      rects.add(rect(left, widths[i]));
      left += widths[i] + p.columnGutter;
    }
    return rects;
  }

  static void _writeJson(Directory dir, String name, Object? payload) {
    File('${dir.path}/$name').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}

/// 单次管线运行（canonical 串用于双跑确定性比对）。
class PipelineRun {
  const PipelineRun({
    required this.screenAccepted,
    required this.screenRejected,
    required this.placedSucceeded,
    required this.placedFailed,
    required this.dedupKept,
    required this.dedupDropped,
    required this.noFeasible,
    required this.canonical,
  });

  final List<String> screenAccepted;
  final List<String> screenRejected;
  final List<String> placedSucceeded;
  final Map<String, String> placedFailed;
  final List<String> dedupKept;
  final Map<String, String> dedupDropped;
  final bool noFeasible;
  final String canonical;
}

class Fixture {
  const Fixture({
    required this.id,
    required this.scenario,
    required this.assembly,
    required this.contentWidth,
    required this.contentHeight,
  });

  final String id;
  final String scenario;
  final LayoutBlockAssembly assembly;
  final double contentWidth;
  final double contentHeight;
}

class FixtureCell {
  const FixtureCell({
    required this.fixtureId,
    required this.scenario,
    required this.blockCount,
    required this.domainSize,
    required this.domainSkeletons,
    required this.screenAccepted,
    required this.screenRejected,
    required this.acceptedCandidateIds,
    required this.acceptedSkeletons,
    required this.placedSucceeded,
    required this.placedFailed,
    required this.placementFailureKinds,
    required this.dedupKept,
    required this.dedupDropped,
    required this.oracleFeasible,
    required this.missedFeasible,
    required this.falseNoFeasible,
    required this.determinismEqual,
  });

  final String fixtureId;
  final String scenario;
  final int blockCount;
  final int domainSize;
  final List<String> domainSkeletons;
  final List<String> screenAccepted;
  final List<String> screenRejected;
  final List<String> acceptedCandidateIds;
  final List<String> acceptedSkeletons;
  final int placedSucceeded;
  final int placedFailed;
  final Map<String, int> placementFailureKinds;
  final List<String> dedupKept;
  final Map<String, String> dedupDropped;
  final List<String> oracleFeasible;
  final List<String> missedFeasible;
  final bool falseNoFeasible;
  final bool determinismEqual;

  Map<String, Object?> toJson() => {
    'fixture': fixtureId,
    'scenario': scenario,
    'block_count': blockCount,
    'domain_size': domainSize,
    'domain_skeletons': domainSkeletons,
    'screen_accepted': screenAccepted,
    'screen_rejected': screenRejected,
    'placed_succeeded': placedSucceeded,
    'placed_failed': placedFailed,
    'placement_failure_kinds': placementFailureKinds,
    'accepted_skeletons': acceptedSkeletons,
    'dedup_kept': dedupKept,
    'dedup_dropped': dedupDropped,
    'oracle_feasible': oracleFeasible,
    'missed_feasible': missedFeasible,
    'false_no_feasible': falseNoFeasible,
    'determinism_equal': determinismEqual,
  };
}

class Report {
  const Report({
    required this.generatedAtUtc,
    required this.contractVersions,
    required this.reproductionCommands,
    required this.fixtures,
    required this.perSkeleton,
    required this.summary,
    required this.worstGroup,
    required this.verdictRule,
    required this.verdict,
    required this.elapsedMs,
  });

  final String generatedAtUtc;
  final Map<String, Object?> contractVersions;
  final List<String> reproductionCommands;
  final List<FixtureCell> fixtures;
  final Map<String, Map<String, Object?>> perSkeleton;
  final Map<String, Object?> summary;
  final Map<String, String> worstGroup;
  final String verdictRule;
  final String verdict;
  final int elapsedMs;

  Map<String, Object?> toJson() => {
    'gate': 'G3',
    'generated_at_utc': generatedAtUtc,
    'contract_versions': contractVersions,
    'reproduction_commands': reproductionCommands,
    'fixtures': [for (final f in fixtures) f.toJson()],
    'per_skeleton': perSkeleton,
    'summary': summary,
    'worst_group': worstGroup,
    'verdict_rule': verdictRule,
    'verdict': verdict,
    'elapsed_ms': elapsedMs,
  };
}

/// 确定性 fixture 集（场景族覆盖：图文混排/障碍/长文需双栏/不可解/
/// 宽松全骨架；文本为 CJK，测试字体 1em/字符 → 行为确定）。
List<Fixture> buildFixtures() {
  const tokens = SmartLayoutDesignTokens.v1;

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
          fontSize: tokens.bodySize,
          lineHeight: tokens.lineHeight,
        ),
      );

  LayoutBlock figure(String id) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.figure,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: true,
        figure: FigureBlockSpec(fileId: 'img-$id', displayAspectRatio: 1.5),
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

  LayoutBlockAssembly assemblyOf(
    List<LayoutBlock> blocks, {
    List<String> preserved = const [],
    List<BlockRelationship> relationships = const [],
    List<List<String>> groups = const [],
  }) =>
      LayoutBlockAssembly(
        blocks: List.unmodifiable(blocks),
        relationships: relationships,
        atomicGroups: groups,
        documentConsumedSourceIds: [
          for (final b in blocks)
            if (b.kind != LayoutBlockKind.preserved &&
                b.kind != LayoutBlockKind.protected)
              b.id,
        ],
        documentPreservedSourceIds: preserved,
      );

  return [
    // 1. 图文混排：段落 + figure/caption 原子组 + 保留手写。
    Fixture(
      id: 'mixed-figure-text',
      scenario: '图文混排 + caption 原子组 + preserved',
      assembly: assemblyOf(
        [
          for (var i = 0; i < 4; i++)
            para('p$i', List.filled(40, '文$i').join()),
          figure('fig'),
          para('cap', '图 1 说明'),
          preservedBlock('ink', {
            'left': 1000.0,
            'top': 740.0,
            'width': 160.0,
            'height': 40.0,
          }),
        ],
        preserved: ['ink'],
        relationships: [
          const BlockRelationship(
            kind: BlockRelationKind.captionOf,
            fromBlockId: 'cap',
            toBlockId: 'fig',
          ),
        ],
        groups: [
          ['fig', 'cap'],
        ],
      ),
      contentWidth: 1200,
      contentHeight: 800,
    ),
    // 2. protected 障碍：右栏中部被吃掉一段。
    Fixture(
      id: 'protected-obstacle',
      scenario: 'protected 障碍绕置',
      assembly: assemblyOf([
        for (var i = 0; i < 4; i++)
          para('p$i', List.filled(60, '字$i').join()),
        protectedBlock(
          'lock',
          const LayoutRect(left: 640, top: 200, width: 300, height: 120),
        ),
      ], preserved: [
        'lock',
      ]),
      contentWidth: 1200,
      contentHeight: 800,
    ),
    // 3. 长文超容量：30 段 60 字——body 档聚合溢出（402A 缩档只对
    //    单块溢出触发，聚合溢出=columnsExhausted 稳定失败）；落进
    //    401B LB 松弛带：screen 接受、放置全败、oracle 一致（零误剪）。
    Fixture(
      id: 'long-two-column',
      scenario: '长文超容量（LB 带内接受、放置稳定失败、oracle 一致）',
      assembly: assemblyOf([
        for (var i = 0; i < 30; i++)
          para('p$i', List.filled(60, '长$i').join()),
      ]),
      contentWidth: 1200,
      contentHeight: 800,
    ),
    // 4. 不可解：60 段塞 300 高——全部候选硬不可行。
    Fixture(
      id: 'infeasible-tight',
      scenario: '超容量（期望 NoFeasibleLayout，oracle 一致全败）',
      assembly: assemblyOf([
        for (var i = 0; i < 60; i++)
          para('p$i', List.filled(60, '满$i').join()),
      ]),
      contentWidth: 1200,
      contentHeight: 300,
    ),
    // 5. 宽松：短内容大页面——全部骨架可行（多样性）。
    Fixture(
      id: 'loose-all-skeletons',
      scenario: '宽松短文（全部骨架可放置）',
      assembly: assemblyOf([
        para('a', '短文一段'),
        para('b', '短文两段'),
        figure('fig2'),
      ]),
      contentWidth: 1200,
      contentHeight: 800,
    ),
  ];
}

/// CLI 入口（flutter test 侧调用）。
Future<int> runG3PlannerQuality() async {
  final report = const PlannerQualityEvaluator().execute();
  stdout.writeln(
    'G3 planner quality: fixtures=${report.summary['fixtures']} '
    'missed=${report.summary['missed_feasible']} '
    'falseNoFeasible=${report.summary['false_no_feasible']} '
    'determinismFailures=${report.summary['determinism_failures']} '
    'skeletons=${report.summary['unique_skeletons_accepted']} '
    'attempts=${report.summary['placement_attempts']}/'
    '${report.summary['budget']} → ${report.verdict}',
  );
  return report.verdict == 'pass' ? 0 : 1;
}
