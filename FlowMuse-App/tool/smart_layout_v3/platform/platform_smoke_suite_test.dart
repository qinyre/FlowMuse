import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

import 'platform_smoke_suite.dart';

/// V3-605A：跨端 smoke 测试入口——入口→commit→undo→reopen 四段全真链。
///
/// 证据：FLOWMUSE_GENERATE_V3_605A_EVIDENCE=1 一次性写入
/// docs/研发记录/evidence/smart-layout-v3/platform/v3-605a-smoke.json；
/// 常规 flutter test 只读校验已提交证据结论一致（防 sha 漂移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('V3-605A 跨端 smoke：入口→commit→undo→reopen 全链绿', () {
    final suite = PlatformSmokeSuite();
    final steps = suite.run();

    expect(steps.map((s) => s.id), const [
      'entry-load',
      'commit-applyResult',
      'undo-restore',
      'reopen-equiv',
    ]);
    for (final step in steps) {
      expect(
        step.passed,
        isTrue,
        reason: '${step.id} 失败：${step.detail}',
      );
    }
    expect(suite.allPassed(steps), isTrue);

    final appDir = io.Directory.current.path;
    final target = io.File(
      '$appDir/../docs/研发记录/evidence/smart-layout-v3/platform/'
      'v3-605a-smoke.json',
    );
    final generate =
        io.Platform.environment['FLOWMUSE_GENERATE_V3_605A_EVIDENCE'] == '1';
    if (generate) {
      target.createSync(recursive: true);
      target.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'task_id': 'V3-605A',
          'suite': 'PlatformSmokeSuite',
          'host': io.Platform.operatingSystem,
          'steps': [for (final s in steps) s.toJson()],
          'all_passed': suite.allPassed(steps),
        }),
        flush: true,
      );
      // ignore: avoid_print
      print('[smoke] evidence written: ${target.path}');
    } else if (target.existsSync()) {
      final committed =
          jsonDecode(target.readAsStringSync()) as Map<String, Object?>;
      expect(committed['all_passed'], isTrue, reason: '已提交 smoke 证据未全绿');
      final committedSteps = (committed['steps'] as List).cast<Map>();
      expect(
        [for (final s in committedSteps) [s['id'], s['passed']]],
        [for (final s in steps) [s.id, s.passed]],
        reason: '已提交 smoke 证据与现场结论不一致',
      );
    }
  });
}
