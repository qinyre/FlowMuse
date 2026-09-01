// ignore_for_file: avoid_print
// tool/natural_media_hash_web_check/main.dart
//
// §3.3 种子跨端门禁的 JS 侧入口：
//   dart compile js -o build/nm_hash_check.js tool/natural_media_hash_web_check/main.dart
//   node build/nm_hash_check.js
// 退出码 0 = 冻结向量在 dart2js 产物上逐值一致（run.ps1 封装了这两步）。
import 'hash_vectors.dart';

void main() {
  final failures = runFrozenVectorChecks();
  if (failures.isEmpty) {
    print('PASS: all frozen seed vectors identical on dart2js/V8');
    return;
  }
  print('FAIL: ${failures.length} vector(s) drifted on dart2js/V8');
  for (final f in failures) {
    print('  - $f');
  }
  // dart2js 下无 exitCode 时的兜底：以异常结束让 CI 判失败。
  throw StateError('frozen seed vectors drifted');
}
