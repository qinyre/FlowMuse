import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'transaction_matrix.dart';

/// V3-506A 事务体验矩阵（Gate 4 机器证据）：loopback 真实 HTTP +
/// 真实 NativeHttpClient（HttpOverrides 摘除）驱动七类事务场景，
/// 全部六态断言必须通过。
///
/// 证据生成：设置 FLOWMUSE_GENERATE_GATE4_EVIDENCE=1 时额外把报告
/// 写入 docs/研发记录/evidence/smart-layout-v3/gates/G4/
/// transaction-matrix-report.json（一次性生成后随任务提交；常规
/// flutter test 运行只读验证，不重写证据文件以免 sha 漂移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(int, String)> okHandler(_) async => (
    200,
    TransactionMatrixRunner.regionBody(),
  );

  test('事务矩阵：七场景全绿（preview=commit/undo-redo/cancel-late/'
      'draft/conflict×2/correction/render-ranking）', () async {
    final previousOverrides = io.HttpOverrides.current;
    io.HttpOverrides.global = null;
    late final TransactionMatrixReport report;
    try {
      report = await TransactionMatrixRunner.run(
        handler: okHandler,
        onTrace: (line) {
          // ignore: avoid_print
          print('[matrix] $line');
        },
      );
    } finally {
      io.HttpOverrides.global = previousOverrides;
    }

    expect(report.cases.map((c) => c.id), const [
      'S1-preview-commit',
      'S2-undo-redo',
      'S3-cancel-late',
      'S4-draft-release',
      'S5a-conflict-intersect',
      'S5b-conflict-disjoint',
      'S6-correction-rerun',
      'S7-render-ranking',
    ]);
    for (final c in report.cases) {
      expect(
        c.passed,
        isTrue,
        reason: '${c.id} 失败：${c.failure}\nchecks:\n'
            '${c.checks.map((k) => '  - $k').join('\n')}',
      );
    }
    expect(report.allPassed, isTrue);
    expect(report.a11yEvidencePointers, isNotEmpty);

    final generate =
        io.Platform.environment['FLOWMUSE_GENERATE_GATE4_EVIDENCE'] == '1';
    if (generate) {
      // flutter test 的 cwd = FlowMuse-App 包目录；仓库根 = ../。
      final appDir = io.Directory.current.path;
      final target = io.File(
        '$appDir/../docs/研发记录/evidence/smart-layout-v3/gates/G4/'
        'transaction-matrix-report.json',
      );
      await target.create(recursive: true);
      await target.writeAsString(report.toPrettyJson(), flush: true);
      // ignore: avoid_print
      print('[matrix] evidence written: ${target.path}');
    }
  }, timeout: const Timeout(Duration(seconds: 120)));
}
