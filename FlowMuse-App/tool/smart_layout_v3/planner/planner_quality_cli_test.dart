import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'planner_quality_evaluator.dart';

/// G3 证据生成 + 机器判定（V3-406A）：
///   flutter test tool/smart_layout_v3/planner/planner_quality_cli_test.dart
///
/// 运行 PlannerQualityEvaluator 全 fixture 评估，写出
/// evidence/gates/G3/{planner-quality-report,gate-three-report}.json，
/// 并断言机器判定为 pass（失败即本测试失败，Gate 3 无法通过）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('G3 planner quality 评估：机器判定 pass 且证据落盘', () {
    final report = const PlannerQualityEvaluator().execute();

    // 证据落盘且非空。
    final quality = File(
      '${PlannerQualityEvaluator.evidenceRoot}/planner-quality-report.json',
    );
    final gate = File(
      '${PlannerQualityEvaluator.evidenceRoot}/gate-three-report.json',
    );
    expect(quality.existsSync(), isTrue, reason: 'planner-quality-report 落盘');
    expect(quality.lengthSync(), greaterThan(0));
    expect(gate.existsSync(), isTrue, reason: 'gate-three-report 落盘');
    expect(gate.lengthSync(), greaterThan(0));

    // 机器判定（全局规则，禁止单 fixture 调参）。
    expect(report.verdict, 'pass', reason: report.verdictRule);
    expect(report.summary['missed_feasible'], 0, reason: '零漏解（零误剪）');
    expect(report.summary['false_no_feasible'], 0, reason: '零无解误判');
    expect(report.summary['determinism_failures'], 0, reason: '双跑确定');
    expect(
      report.summary['unique_skeletons_accepted'] as int,
      greaterThanOrEqualTo(4),
      reason: '各骨架单独报告且均有代表',
    );
    expect(
      report.summary['placement_attempts'] as int,
      lessThanOrEqualTo(report.summary['budget'] as int),
      reason: '确定性操作预算内',
    );
    // 各 skeleton 单独报告存在。
    for (final skeleton in [
      'single',
      'twoColumn',
      'mainSide',
      'conservativeLayout',
    ]) {
      expect(report.perSkeleton, contains(skeleton));
      expect(
        (report.perSkeleton[skeleton]!['fixtures_accepted'] as int),
        greaterThan(0),
        reason: '$skeleton 至少在一个 fixture 上被接受',
      );
    }
    // 契约版本与复现命令齐备。
    expect(report.contractVersions['metric_contract'], isNotNull);
    expect(report.contractVersions['rubric_version'], '1.0.0');
    expect(report.reproductionCommands, isNotEmpty);
  });
}
