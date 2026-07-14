import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_library_index_notifier.dart';

void main() {
  testWidgets('首页自动化首帧性能门禁（预算3秒）', (tester) async {
    const budget = Duration(seconds: 3);
    final stopwatch = Stopwatch()..start();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryIndexProvider.overrideWith(TestLibraryIndexNotifier.new),
        ],
        child: FlowMuseApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    stopwatch.stop();

    final elapsedMs = stopwatch.elapsedMilliseconds;
    final budgetMs = budget.inMilliseconds;
    final utilization = elapsedMs / budgetMs * 100;
    final headroomMs = budgetMs - elapsedMs;
    final verdict = stopwatch.elapsed < budget ? 'PASS' : 'FAIL';
    String row(String label, String value) =>
        '│ ${label.padRight(13)}${value.padRight(55)}│';

    debugPrint('''
╭──────────────── FlowMuse · Sprint 2 Performance Gate ────────────────╮
${row('Benchmark', 'Homepage automated first-frame baseline')}
${row('Runtime', 'Flutter Widget Test')}
${row('Budget', '≤ $budgetMs ms')}
${row('Observed', '$elapsedMs ms')}
${row('Utilization', '${utilization.toStringAsFixed(1)}% of performance budget')}
${row('Headroom', '$headroomMs ms')}
${row('Verdict', verdict)}
╰──────────────────────────────────────────────────────────────────────╯''');
    debugPrint(
      '[Sprint2Performance] metric=home_first_frame '
      'duration_ms=$elapsedMs budget_ms=$budgetMs '
      'utilization_pct=${utilization.toStringAsFixed(1)} '
      'headroom_ms=$headroomMs verdict=$verdict',
    );
    expect(find.text('全部笔记'), findsWidgets);
    expect(stopwatch.elapsed, lessThan(budget));
  });
}
