import 'dart:convert';
import 'dart:io';

import 'src/smart_layout_fixture_runner.dart';

/// 智能排版 v3 fixture manifest 校验 CLI（V3-001A）。
///
/// 用法：
///   dart run tool/smart_layout_v3/main.dart validate --manifest {path} [--repo-root {dir}]
///
/// 输出机器可读 JSON：{"admitted":bool,"errors":[{"code","pointer","message"}]}
/// 退出码：0=准入；2=拒绝；64=用法错误。V3-001C 在同一入口上扩展批量执行。
void main(List<String> args) {
  if (args.isEmpty || args[0] != 'validate') {
    stderr.writeln('usage: main.dart validate --manifest <path> [--repo-root <dir>]');
    exit(64);
  }
  String? manifestPath;
  String? repoRoot;
  for (var i = 1; i < args.length - 1; i++) {
    if (args[i] == '--manifest') manifestPath = args[i + 1];
    if (args[i] == '--repo-root') repoRoot = args[i + 1];
  }
  if (manifestPath == null) {
    stderr.writeln('usage: main.dart validate --manifest <path> [--repo-root <dir>]');
    exit(64);
  }
  final runner = SmartLayoutFixtureRunner(repoRoot: repoRoot ?? Directory.current.path);
  final admission = runner.loadAndAdmit(manifestPath);
  stdout.writeln(jsonEncode({
    'admitted': admission.admitted,
    'errors': [for (final error in admission.errors) error.toJson()],
  }));
  exit(admission.admitted ? 0 : 2);
}
