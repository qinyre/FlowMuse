import 'package:flutter_test/flutter_test.dart';

import 'transform_invariant_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'G2 变换矩阵全链（元素/关系矩阵 + 零漏检 + 性能 + 兼容）',
    () async {
      final code = await runG2TransformMatrix();
      expect(code, 0, reason: 'G2 矩阵必须机器判定 pass（exit 2=fail）');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
