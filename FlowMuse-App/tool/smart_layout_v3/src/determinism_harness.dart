import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'benchmark_spec.dart';
import 'canonical_artifacts.dart';
import 'deterministic_execution_environment.dart';
import 'fixture_manifest.dart';

/// 固定时钟：只随显式 tick 前进，任何路径都读不到真实墙钟。
class DeterministicClock {
  DeterministicClock({required DeterministicExecutionEnvironment environment})
      : _instant = environment.fixedClockUtc,
        _ticks = 0;

  final String _instant;
  int _ticks;

  /// 固定起始时刻（环境声明值）。
  String get fixedAtUtc => _instant;

  /// 显式推进的 tick 数；用于排序与超时计数，与真实时间无关。
  int get ticks => _ticks;

  void tick() => _ticks++;

  /// 超时判定：以 tick 为单位，不用墙钟。
  bool timedOut(int timeoutTicks) => _ticks >= timeoutTicks;
}

/// 种子随机源：dart:math Random(同种子) 在同一 Dart VM 版本上跨运行/跨进程
/// 确定性一致；工具只在 VM（dart run / flutter test）下执行。
class SeededRandom {
  SeededRandom({required int seed}) : _next = seed;

  int _next;

  int nextInt(int max) {
    _next = (_next * 1103515245 + 12345) & 0x7fffffff;
    return _next % max;
  }

  /// 序列指纹：抽取固定数量样本后对序列做稳定哈希，用于三次运行一致性比对。
  String sequenceFingerprint({int samples = 32, int max = 1 << 30}) {
    final values = [for (var i = 0; i < samples; i++) nextInt(max)];
    return crypto.sha256.convert(utf8.encode(values.join(','))).toString();
  }
}

/// 环境冻结结果：字体文件哈希全部核对一致才算冻结成功。
class EnvironmentFreeze {
  const EnvironmentFreeze.ok(this.environment, this.identityHash)
      : errors = const [],
        fontsVerified = true;
  const EnvironmentFreeze.failed(this.errors)
      : environment = null,
        identityHash = null,
        fontsVerified = false;

  final DeterministicExecutionEnvironment? environment;
  final String? identityHash;
  final List<String> errors;
  final bool fontsVerified;
  bool get ok => environment != null;
}

/// 确定性执行环境冻结与一致性运行（V3-001B）。
///
/// 职责：
/// 1. 字体冻结：manifest 声明的每个字体文件必须存在且 SHA-256 与声明一致；
/// 2. 环境身份 hash：对 DeterministicExecutionEnvironment 的规范化字段计算
///    稳定哈希，同一环境跨进程跨运行必须相同；
/// 3. 合成数据政策：BenchmarkSpec.data_policy 为 synthetic_only 时，任何
///    authorized_real 录制响应都被拒绝（V3-002A 数据治理落地前的硬规则）；
/// 4. 单次确定性运行：时钟/随机源指纹 + 规范化 scene/golden 哈希组成
///    DeterminismRunReport，供三次隔离子进程比对。
class DeterminismHarness {
  const DeterminismHarness({required this.repoRoot});

  final String repoRoot;

  EnvironmentFreeze freezeEnvironment(FixtureEntry fixture, {bool verifyFontFiles = true}) {
    final errors = <String>[];
    if (verifyFontFiles) {
      for (final font in fixture.environment.fonts) {
        final file = File('$repoRoot${Platform.pathSeparator}${font.file.replaceAll('/', Platform.pathSeparator)}');
        if (!file.existsSync()) {
          errors.add('字体文件不存在：${font.file}');
          continue;
        }
        final actual = crypto.sha256.convert(file.readAsBytesSync()).toString();
        if (actual != font.sha256) {
          errors.add('字体哈希不匹配：${font.file} 声明 ${font.sha256} 实际 $actual');
        }
      }
    }
    if (errors.isNotEmpty) {
      return EnvironmentFreeze.failed(errors);
    }
    return EnvironmentFreeze.ok(
      fixture.environment,
      CanonicalArtifacts.canonicalJsonSha256(fixture.environment.toJson()),
    );
  }

  /// 合成数据政策检查：spec 要求 synthetic_only 时拒绝真实录制。
  List<String> checkDataPolicy(FixtureManifest manifest, BenchmarkSpec spec) {
    if (!spec.syntheticOnly) return const [];
    final violations = <String>[];
    for (final fixture in manifest.fixtures) {
      for (final response in fixture.recordedResponses) {
        if (response.contentOrigin != 'synthetic') {
          violations.add(
              'fixture ${fixture.id} 录制响应 ${response.name} content_origin=${response.contentOrigin}：'
              'benchmark spec 数据政策为 synthetic_only（V3-002A 前 record/replay 只接受合成数据）');
        }
      }
    }
    return violations;
  }

  /// 单次确定性运行：不读墙钟、不依赖外部状态，输出可跨进程比对的报告。
  DeterminismRunReport runOnce(FixtureEntry fixture, BenchmarkSpec spec) {
    final freeze = freezeEnvironment(fixture);
    if (!freeze.ok) {
      return DeterminismRunReport.failed(fixture.id, freeze.errors);
    }
    final clock = DeterministicClock(environment: fixture.environment);
    final random = SeededRandom(seed: fixture.environment.randomSeed + fixture.elementIntegrity.versionNonceSeed);
    final policyErrors = <String>[];
    final sceneBytes = File(
            '$repoRoot${Platform.pathSeparator}${fixture.scene.path.replaceAll('/', Platform.pathSeparator)}')
        .readAsBytesSync();
    final goldenBytes = File(
            '$repoRoot${Platform.pathSeparator}${fixture.expected.rendererGolden.path.replaceAll('/', Platform.pathSeparator)}')
        .readAsBytesSync();
    final normalizedSceneHash = CanonicalArtifacts.canonicalJsonSha256(
      _decodeJson(sceneBytes),
    );
    final normalizedGoldenHash = CanonicalArtifacts.canonicalPngSha256(goldenBytes);
    // 固定推进若干 tick：任何依赖时钟的逻辑（排序、阶段计数）在同一环境
    // 下走到相同状态；真实管线的超时判定由 V3-001C runner 按 spec 执行。
    const ticksPerRun = 16;
    for (var i = 0; i < ticksPerRun; i++) {
      clock.tick();
    }
    if (clock.timedOut(spec.timeoutTicks)) {
      policyErrors.add('clock budget exhausted: ticks=$ticksPerRun >= timeout_ticks=${spec.timeoutTicks}');
    }
    return DeterminismRunReport(
      fixtureId: fixture.id,
      environmentIdentityHash: freeze.identityHash!,
      clockFingerprint: '${clock.fixedAtUtc}@${clock.ticks}',
      randomFingerprint: random.sequenceFingerprint(),
      normalizedSceneSha256: normalizedSceneHash,
      normalizedGoldenSha256: normalizedGoldenHash,
      errors: policyErrors,
    );
  }

  Object? _decodeJson(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }
}

class DeterminismRunReport {
  const DeterminismRunReport({
    required this.fixtureId,
    required this.environmentIdentityHash,
    required this.clockFingerprint,
    required this.randomFingerprint,
    required this.normalizedSceneSha256,
    required this.normalizedGoldenSha256,
    this.errors = const [],
  }) : ok = true;

  const DeterminismRunReport.failed(this.fixtureId, this.errors)
      : environmentIdentityHash = null,
        clockFingerprint = null,
        randomFingerprint = null,
        normalizedSceneSha256 = null,
        normalizedGoldenSha256 = null,
        ok = false;

  final String fixtureId;
  final String? environmentIdentityHash;
  final String? clockFingerprint;
  final String? randomFingerprint;
  final String? normalizedSceneSha256;
  final String? normalizedGoldenSha256;
  final List<String> errors;
  final bool ok;

  /// 跨进程一致性指纹：全部字段拼接后的稳定哈希（错误报告不含在内，
  /// 失败报告本身即不一致）。
  String? get consistencyHash {
    if (!ok) return null;
    final material = [
      fixtureId,
      environmentIdentityHash,
      clockFingerprint,
      randomFingerprint,
      normalizedSceneSha256,
      normalizedGoldenSha256,
    ].join('|');
    return crypto.sha256.convert(utf8.encode(material)).toString();
  }

  Map<String, Object?> toJson() => {
        'fixture_id': fixtureId,
        'ok': ok,
        if (ok) 'environment_identity_hash': environmentIdentityHash,
        if (ok) 'clock_fingerprint': clockFingerprint,
        if (ok) 'random_fingerprint': randomFingerprint,
        if (ok) 'normalized_scene_sha256': normalizedSceneSha256,
        if (ok) 'normalized_golden_sha256': normalizedGoldenSha256,
        if (ok) 'consistency_hash': consistencyHash,
        if (errors.isNotEmpty) 'errors': errors,
      };
}
