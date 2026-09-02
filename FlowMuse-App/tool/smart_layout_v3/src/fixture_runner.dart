import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'benchmark_spec.dart';
import 'canonical_artifacts.dart';
import 'controlled_replay.dart';
import 'determinism_harness.dart';
import 'fixture_manifest.dart';

/// 智能排版 v3 fixture runner 执行层（V3-001C）。
///
/// 在准入层（V3-001A）与确定性环境（V3-001B）之上执行 fixture：
/// admission → data_policy → environment → replay → artifacts 五层逐步执行，
/// 每层结果落入分层报告；报告写盘后无论成败一律保留（失败保留）。
/// 机器退出码：0=全部通过；2=任何 fixture 失败或被拒。
/// 全程离线：响应只经 ControlledReplay 回放，不访问真实网络。
class FixtureRunner {
  const FixtureRunner({
    required this.repoRoot,
    required this.spec,
    this.outputRoot = 'build/smart-layout-v3-runs',
  });

  final String repoRoot;
  final BenchmarkSpec spec;
  final String outputRoot;

  /// 批量执行：逐 fixture 串行（spec.concurrency 冻结为 1），
  /// 返回批量报告并写盘。
  BatchRunReport runBatch(FixtureManifest manifest) {
    final fixtureReports = <FixtureRunReport>[];
    for (final fixture in manifest.fixtures) {
      fixtureReports.add(runFixture(manifest, fixture));
    }
    final batch = BatchRunReport(
      manifestName: manifest.name,
      fixtureReports: fixtureReports,
    );
    _writeJson(batch.writePath(repoRoot, outputRoot), batch.toJson());
    return batch;
  }

  /// 单页执行：五层顺序执行，任何一层失败即停止并保留失败报告。
  FixtureRunReport runFixture(FixtureManifest manifest, FixtureEntry fixture) {
    final layers = <String, LayerResult>{};

    // L1 admission：复用准入层（含数据边界与产物哈希核对）。
    final admission = SmartLayoutFixtureRunnerProxy.admitFixture(manifest, fixture, repoRoot);
    layers['admission'] = admission;
    if (!admission.ok) {
      return _finish(fixture, layers, 'rejected');
    }

    // L2 data_policy：V3-002A 前 record/replay 只接受合成数据。
    final policyViolations = DeterminismHarness(repoRoot: repoRoot).checkDataPolicy(manifest, spec);
    layers['data_policy'] = LayerResult(
      ok: policyViolations.isEmpty,
      errors: policyViolations,
    );
    if (policyViolations.isNotEmpty) {
      return _finish(fixture, layers, 'rejected');
    }

    // L3 environment：字体冻结与确定性指纹。
    final harness = DeterminismHarness(repoRoot: repoRoot);
    final determinism = harness.runOnce(fixture, spec);
    layers['environment'] = LayerResult(ok: determinism.ok, errors: determinism.errors);
    if (!determinism.ok) {
      return _finish(fixture, layers, 'failed');
    }

    // L4 replay：受控回放全部声明响应（存在性+哈希+离线模式）。
    final replay = ControlledReplay(repoRoot: repoRoot, fixture: fixture);
    final replayErrors = <String>[];
    final replayed = <String, String>{};
    for (final result in replay.fetchAll()) {
      if (result.ok) {
        replayed[result.name] = result.sha256!;
      } else {
        replayErrors.addAll(result.errors);
      }
    }
    layers['replay'] = LayerResult(ok: replayErrors.isEmpty, errors: replayErrors);
    if (replayErrors.isNotEmpty) {
      return _finish(fixture, layers, 'failed');
    }

    // L5 artifacts：期望产物核对（scene/golden 已在准入层核哈希；此处登记
    // 规范化哈希，供三次运行一致性与基线对账）。
    layers['artifacts'] = LayerResult(
      ok: true,
      errors: const [],
      values: {
        'normalized_scene_sha256': determinism.normalizedSceneSha256,
        'normalized_golden_sha256': determinism.normalizedGoldenSha256,
        'environment_identity_hash': determinism.environmentIdentityHash,
        'replayed_responses': replayed,
      },
    );

    return _finish(fixture, layers, 'passed');
  }

  FixtureRunReport _finish(FixtureEntry fixture, Map<String, LayerResult> layers, String status) {
    final report = FixtureRunReport(
      fixtureId: fixture.id,
      status: status,
      layers: layers,
    );
    _writeJson(report.writePath(repoRoot, outputRoot), report.toJson());
    return report;
  }

  void _writeJson(String path, Map<String, Object?> json) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}

/// L1 admission 层结果代理：对单 fixture 复跑准入层的关键校验
/// （数据边界已随整单 manifest 校验；此处复核该 fixture 的产物存在性与哈希）。
class SmartLayoutFixtureRunnerProxy {
  static LayerResult admitFixture(FixtureManifest manifest, FixtureEntry fixture, String repoRoot) {
    final errors = <String>[];
    void verify(ArtifactRef ref, String what) {
      final file = File('$repoRoot${Platform.pathSeparator}${ref.path.replaceAll('/', Platform.pathSeparator)}');
      if (!file.existsSync()) {
        errors.add('$what 文件不存在：${ref.path}');
        return;
      }
      final actual = crypto.sha256.convert(file.readAsBytesSync()).toString();
      if (actual != ref.sha256) {
        errors.add('$what sha256 不匹配：${ref.path}');
      }
    }

    verify(fixture.scene, 'scene');
    final image = fixture.image;
    if (image != null) verify(image, 'image');
    verify(fixture.expected.rendererGolden, 'renderer golden');
    return LayerResult(ok: errors.isEmpty, errors: errors);
  }
}

class LayerResult {
  const LayerResult({required this.ok, required this.errors, this.values});

  final bool ok;
  final List<String> errors;
  final Map<String, Object?>? values;

  Map<String, Object?> toJson() => {
        'ok': ok,
        if (errors.isNotEmpty) 'errors': errors,
        if (values != null) ...values!,
      };
}

/// 单 fixture 分层执行报告。
class FixtureRunReport {
  const FixtureRunReport({required this.fixtureId, required this.status, required this.layers});

  final String fixtureId;
  final String status; // passed | failed | rejected
  final Map<String, LayerResult> layers;

  bool get ok => status == 'passed';

  /// 报告内容哈希：规范化（剥离易变键）后计算；同输入同执行三次必一致。
  String get contentHash => CanonicalArtifacts.canonicalJsonSha256(toJson());

  Map<String, Object?> toJson() => {
        'fixture_id': fixtureId,
        'status': status,
        'layers': {for (final entry in layers.entries) entry.key: entry.value.toJson()},
      };

  String writePath(String repoRoot, String outputRoot) =>
      '$repoRoot${Platform.pathSeparator}${outputRoot.replaceAll('/', Platform.pathSeparator)}'
      '${Platform.pathSeparator}$fixtureId${Platform.pathSeparator}report.json';
}

/// 批量执行报告：manifest 级汇总 + 逐 fixture 报告索引。
class BatchRunReport {
  const BatchRunReport({required this.manifestName, required this.fixtureReports});

  final String manifestName;
  final List<FixtureRunReport> fixtureReports;

  bool get ok => fixtureReports.every((r) => r.ok);

  /// 批量内容哈希：逐 fixture contentHash 排序后拼接计算（与执行顺序无关，
  /// 但 fixture 状态/层结果变化必改哈希）。
  String get contentHash {
    final hashes = [for (final r in fixtureReports) r.contentHash]..sort();
    return crypto.sha256.convert(utf8.encode(hashes.join('|'))).toString();
  }

  Map<String, Object?> toJson() => {
        'manifest': manifestName,
        'ok': ok,
        'fixture_count': fixtureReports.length,
        'passed': fixtureReports.where((r) => r.status == 'passed').length,
        'failed': fixtureReports.where((r) => r.status == 'failed').length,
        'rejected': fixtureReports.where((r) => r.status == 'rejected').length,
        'content_sha256': contentHash,
        'fixtures': [for (final r in fixtureReports) r.toJson()],
      };

  String writePath(String repoRoot, String outputRoot) =>
      '$repoRoot${Platform.pathSeparator}${outputRoot.replaceAll('/', Platform.pathSeparator)}'
      '${Platform.pathSeparator}batch-report.json';
}
