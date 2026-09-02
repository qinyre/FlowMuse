/// V3-702A：合成稳定性与故障注入矩阵测试——48 dev 样本 × 8 故障
/// 全矩阵重放，critical=0、每故障预期结果类、失败样本不排除。
///
/// 证据生成：FLOWMUSE_GENERATE_V3_702A_EVIDENCE=1 一次性写入
/// docs/研发记录/evidence/smart-layout-v3/competition/
/// v3-702a-stability-report.json；常规 flutter test 只读校验不重写。
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import '../../../../../tool/smart_layout_v3/competition/synthetic_stability_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter test 的 cwd = FlowMuse-App 包目录；仓库根 = ../。
  final repoRoot = '${io.Directory.current.path}/..';

  test('48 样本 × 8 故障全矩阵重放：critical=0 且每故障结果类符合语义',
      () async {
    final evaluator = SyntheticStabilityEvaluator(repoRoot: repoRoot);
    final report = await evaluator.evaluate();

    // ---- 总量与样本锚点 ----
    final totals = report['totals']! as Map<String, Object?>;
    final sampleSource = report['sample_source']! as Map<String, Object?>;
    expect(sampleSource['sample_count'], 48);
    expect(sampleSource['replay_order_seed'], 20260902);
    expect(
      sampleSource['samples_sha256'] as String,
      hasLength(64),
      reason: '样本集哈希必须为 sha256 hex',
    );
    expect(totals['runs'], 384);
    expect(totals['failed_samples_excluded'], isFalse);
    expect(totals['critical'], 0, reason: 'critical 必须为零');
    expect(totals['error_rate'], 1.0, reason: '全注入矩阵：每注入必失败或被拒');
    expect((report['critical_events']! as List).isEmpty, isTrue);

    // ---- 每故障预期结果类 ----
    final byFault = report['by_fault']! as Map<String, Object?>;
    expect(byFault.keys, containsAll(SmartLayoutFaultInjectionMatrix.faultIds));

    Map<String, Object?> fault(String id) =>
        byFault[id]! as Map<String, Object?>;
    Map<String, int> failureKinds(String id) =>
        (fault(id)['failure_kinds']! as Map<String, Object?>)
            .map((k, v) => MapEntry(k, v as int));
    List<Map<String, Object?>> faultRuns(String id) => (report['runs']!
        as List)
        .whereType<Map<String, Object?>>()
        .where((r) => r['fault_id'] == id)
        .toList();

    for (final id in SmartLayoutFaultInjectionMatrix.faultIds) {
      expect(fault(id)['runs'], 48, reason: '$id 样本数');
      expect(fault(id)['critical'], 0, reason: '$id critical');
    }

    // 可重试网络类：耗尽后 failed，两次尝试。
    for (final id in ['offline', 'timeout']) {
      expect(fault(id)['failed'], 48, reason: '$id 全部失败');
      expect(fault(id)['guard_rejected'], 0);
      expect(
        faultRuns(id).every((r) => r['attempts'] == 2),
        isTrue,
        reason: '$id 默认策略重试一次',
      );
    }
    expect(failureKinds('offline'), {'network': 48});
    expect(failureKinds('timeout'), {'timeout': 48});

    // HTTP 429/500/503：badStatus 可重试，耗尽后 failed。
    for (final id in ['http-429', 'http-500', 'http-503']) {
      expect(fault(id)['failed'], 48, reason: '$id 全部失败');
      expect(failureKinds(id), {'badStatus': 48});
      expect(faultRuns(id).every((r) => r['attempts'] == 2), isTrue);
    }

    // 坏 schema：200 + 非合约体 → 稳定失败不重试。
    expect(fault('bad-schema')['failed'], 48);
    expect(failureKinds('bad-schema'), {'badSchema': 48});
    expect(
      faultRuns('bad-schema').every((r) => r['attempts'] == 1),
      isTrue,
      reason: 'badSchema 不重试',
    );

    // 在途取消（即时响应，取消先落地）：late-guard 拒绝。
    expect(fault('cancel')['guard_rejected'], 48);
    expect(fault('cancel')['failed'], 0);
    expect(
      faultRuns('cancel').every((r) => r['attempts'] == 1),
      isTrue,
      reason: '取消针对在途操作：请求已发出，响应被 late-guard 丢弃',
    );

    // 迟到回调（延迟 50ms 到达，操作已取消）：落地前 late-guard 拒绝。
    expect(fault('late-callback')['guard_rejected'], 48);
    expect(fault('late-callback')['failed'], 0);
    expect(
      faultRuns('late-callback').every((r) => r['attempts'] == 1),
      isTrue,
      reason: '迟到回调=请求已发出后被拒',
    );

    // 拒绝率 = 2/8（cancel + late-callback）。
    expect(totals['guard_rejected'], 96);
    expect(totals['rejection_rate'], closeTo(0.25, 1e-9));

    // ---- 证据生成（一次性）与只读一致性 ----
    final target = io.File(
      '$repoRoot/docs/研发记录/evidence/smart-layout-v3/competition/'
      'v3-702a-stability-report.json',
    );
    final generate =
        io.Platform.environment['FLOWMUSE_GENERATE_V3_702A_EVIDENCE'] == '1';
    if (generate) {
      target.createSync(recursive: true);
      target.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }
    if (target.existsSync()) {
      final persisted =
          jsonDecode(target.readAsStringSync()) as Map<String, Object?>;
      expect(
        (persisted['totals']! as Map<String, Object?>)['critical'],
        0,
      );
      expect(
        (persisted['sample_source']! as Map<String, Object?>)[
            'samples_sha256'],
        sampleSource['samples_sha256'],
      );
      expect((persisted['runs']! as List).length, 384);
    }
  }, timeout: const Timeout(Duration(seconds: 180)));
}
