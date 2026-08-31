import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'fixture_manifest.dart';

/// 受控网络回放（V3-001C）。
///
/// runner 的唯一响应来源：只从 manifest 声明的录制文件读取并核对 SHA-256，
/// 不存在任何真实网络路径。未声明的响应名一律 fail-closed 拒绝，
/// 不得回退到网络或静默返回空。
class ControlledReplay {
  const ControlledReplay({required this.repoRoot, required this.fixture});

  final String repoRoot;
  final FixtureEntry fixture;

  /// 回放一个已声明的录制响应：存在性 + 完整性哈希 + 来源政策复核。
  ReplayResult fetch(String name) {
    final candidates = fixture.recordedResponses.where((r) => r.name == name).toList();
    if (candidates.isEmpty) {
      return ReplayResult.failure(
        name,
        ['replay_response_not_declared: $name（受控回放拒绝未声明响应，禁止网络回退）'],
      );
    }
    final response = candidates.first;
    final errors = <String>[];
    final file = File('$repoRoot${Platform.pathSeparator}${response.path.replaceAll('/', Platform.pathSeparator)}');
    if (!file.existsSync()) {
      return ReplayResult.failure(name, ['replay_file_missing: ${response.path}']);
    }
    final bytes = file.readAsBytesSync();
    final actual = crypto.sha256.convert(bytes).toString();
    if (actual != response.sha256) {
      errors.add('replay_hash_mismatch: ${response.path} 声明 ${response.sha256} 实际 $actual');
    }
    if (fixture.environment.networkMode != 'offline_replay') {
      errors.add('replay_network_mode_invalid: 环境必须是 offline_replay');
    }
    if (errors.isNotEmpty) {
      return ReplayResult.failure(name, errors);
    }
    return ReplayResult.ok(name, bytes, actual);
  }

  /// 回放全部声明响应（执行层消费入口）。
  List<ReplayResult> fetchAll() => [for (final r in fixture.recordedResponses) fetch(r.name)];
}

class ReplayResult {
  const ReplayResult.ok(this.name, this.bytes, this.sha256)
      : errors = const [],
        ok = true;
  const ReplayResult.failure(this.name, this.errors)
      : bytes = null,
        sha256 = null,
        ok = false;

  final String name;
  final List<int>? bytes;
  final String? sha256;
  final List<String> errors;
  final bool ok;
}
