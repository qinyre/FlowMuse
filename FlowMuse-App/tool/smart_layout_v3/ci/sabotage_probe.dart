import 'dart:convert';
import 'dart:io';

/// V3-602A 故意破坏探针：以受控方式失败——退出码 1 + 结构化诊断 +
/// 落盘失败产物（仓库根从脚本位置推导，不依赖进程 CWD），证明 CI
/// 矩阵能被真实失败阻断且保留必要诊断。
Future<void> main() async {
  final script = Platform.script.toFilePath().replaceAll('\\', '/');
  final marker = '/FlowMuse-App/tool/';
  final idx = script.lastIndexOf(marker);
  if (idx <= 0) {
    throw StateError('无法从脚本位置推导仓库根: $script');
  }
  final repoRoot = script.substring(0, idx);
  const failureDir =
      'docs/研发记录/evidence/smart-layout-v3/ci/sabotage/probe-artifacts';
  final artifact = File('$repoRoot/$failureDir/sabotage-diagnostic.json');
  await artifact.create(recursive: true);
  await artifact.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'probe': 'sabotage',
      'reason': '受控故意失败：验证矩阵聚合退出码与诊断归档',
      'hint': '修复本探针注入的假设后重跑矩阵应回到全绿',
    }),
  );
  stderr.writeln('[sabotage-probe] 故意失败：诊断已写入 $failureDir');
  exit(1);
}
