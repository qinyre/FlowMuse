import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

import 'smart_layout_performance_runner.dart';

/// V3-604A：性能、取消与资源压力矩阵（目标符号 SmartLayoutPerformanceRunner）。
///
/// 证据生成：FLOWMUSE_GENERATE_V3_604A_EVIDENCE=1 时把报告写入
/// docs/研发记录/evidence/smart-layout-v3/performance/v3-604a-report.json
/// （一次性生成随任务提交；常规 flutter test 只读验证已提交证据与
/// 现场结论一致，不重写文件防 sha 漂移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'V3-604A 压力矩阵：阶段预算全达标 + 取消/离页/失败注入/内存趋势全绿',
    () async {
      final runner = SmartLayoutPerformanceRunner();
      final report = await runner.run(
        onTrace: (line) {
          // ignore: avoid_print
          print('[perf] $line');
        },
      );

      for (final stage in report.stages) {
        expect(
          stage.passed,
          isTrue,
          reason: '${stage.id} ${stage.medianMs}ms 超预算 '
          '${stage.budgetMs}ms（${stage.detail}）',
        );
      }
      for (final check in report.checks) {
        expect(
          check.passed,
          isTrue,
          reason: '${check.id} 失败：${check.detail}',
        );
      }
      expect(report.allPassed, isTrue);

      final appDir = io.Directory.current.path;
      final target = io.File(
        '$appDir/../docs/研发记录/evidence/smart-layout-v3/performance/'
        'v3-604a-report.json',
      );

      final generate =
          io.Platform.environment['FLOWMUSE_GENERATE_V3_604A_EVIDENCE'] == '1';
      if (generate) {
        target.createSync(recursive: true);
        target.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(report.toJson()),
          flush: true,
        );
        // ignore: avoid_print
        print('[perf] evidence written: ${target.path}');
      } else if (target.existsSync()) {
        // 只读一致性：已提交证据的阶段结论与现场一致。
        final committed =
            jsonDecode(target.readAsStringSync()) as Map<String, Object?>;
        expect(committed['all_passed'], isTrue, reason: '已提交证据未全绿');
        final committedStages = (committed['stages'] as List).cast<Map>();
        final freshStages = (report.toJson()['stages'] as List).cast<Map>();
        expect(
          [for (final s in committedStages) s['id']],
          [for (final s in freshStages) s['id']],
          reason: '阶段集不一致',
        );
        for (var i = 0; i < committedStages.length; i++) {
          expect(
            [committedStages[i]['id'], committedStages[i]['passed']],
            [freshStages[i]['id'], freshStages[i]['passed']],
            reason: '已提交证据与现场结论不一致',
          );
        }
        final committedChecks = (committed['checks'] as List).cast<Map>();
        expect(
          [for (final c in committedChecks) [c['id'], c['passed']]],
          everyElement((pair) => (pair as List)[1] == true),
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 300)),
  );
}
