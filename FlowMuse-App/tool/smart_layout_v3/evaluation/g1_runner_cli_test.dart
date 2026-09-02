import 'package:flutter_test/flutter_test.dart';

import 'g1_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'G1 评测全链（质量/延迟/前置；blocked→exit 2）',
    () async {
      final code = await runG1Evaluation();
      // 前置缺失是合法产出（planner blocked），测试本身只在崩溃时失败。
      expect(code, anyOf(0, 2));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
