import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../src/benchmark_spec.dart';
import '../src/controlled_replay.dart';
import '../src/fixture_manifest.dart';
import '../src/fixture_runner.dart';
import 'benchmark_determinism_test_helpers.dart';

/// V3-001C Runner、受控 replay、报告与 hash 测试。
void main() {
  late Directory tempRoot;
  late Map<String, Object?> manifestJson;
  final spec = _repoSpec();

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('smart_layout_v3_001c_');
    manifestJson = buildAdmissibleManifest(tempRoot);
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  FixtureManifest parse() {
    final outcome = FixtureManifest.parse(manifestJson);
    if (!outcome.isOk) {
      fail('manifest 解析失败：${outcome.errors.join('; ')}');
    }
    return outcome.manifest!;
  }

  test('五层全过：status=passed、分层报告与批量报告写盘、内容哈希稳定', () {
    final manifest = parse();
    final runner = FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out');
    final batch = runner.runBatch(manifest);
    expect(batch.ok, isTrue);
    final report = batch.fixtureReports.single;
    expect(report.status, 'passed');
    expect(report.layers.keys, containsAll(['admission', 'data_policy', 'environment', 'replay', 'artifacts']));
    expect(
      File('${tempRoot.path}${Platform.pathSeparator}runs-out${Platform.pathSeparator}'
              '${report.fixtureId}${Platform.pathSeparator}report.json')
          .existsSync(),
      isTrue,
      reason: 'fixture 报告必须写盘',
    );
    final batchFile = File(
        '${tempRoot.path}${Platform.pathSeparator}runs-out${Platform.pathSeparator}batch-report.json');
    expect(batchFile.existsSync(), isTrue);
    final batchJson = jsonDecode(batchFile.readAsStringSync()) as Map<String, Object?>;
    expect(batchJson['content_sha256'], batch.contentHash);

    // 同输入再跑一次：内容哈希一致。
    final again = FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out').runBatch(parse());
    expect(again.contentHash, batch.contentHash);
  });

  test('故意失败：篡改产物 → admission 层失败、报告保留、批量 ok=false', () {
    final runner = FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out');
    final okBatch = runner.runBatch(parse());
    expect(okBatch.ok, isTrue);

    tamperFile(tempRoot, 'artifacts/scene.json', utf8.encode('{"elements":["tampered"]}'));
    final failedBatch = FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out').runBatch(parse());
    expect(failedBatch.ok, isFalse);
    final report = failedBatch.fixtureReports.single;
    expect(report.status, 'rejected');
    expect(report.layers['admission']!.ok, isFalse);
    expect(report.layers['admission']!.errors.join(), contains('sha256 不匹配'));
    // 失败保留：失败报告仍写盘。
    final kept = File('${tempRoot.path}${Platform.pathSeparator}runs-out${Platform.pathSeparator}'
        '${report.fixtureId}${Platform.pathSeparator}report.json');
    expect(kept.existsSync(), isTrue);
    expect((jsonDecode(kept.readAsStringSync()) as Map<String, Object?>)['status'], 'rejected');
  });

  test('受控回放：哈希不匹配/未声明响应 fail-closed，无网络回退', () {
    final manifest = parse();
    final fixture = manifest.fixtures.single;
    var replay = ControlledReplay(repoRoot: tempRoot.path, fixture: fixture);
    expect(replay.fetchAll().every((r) => r.ok), isTrue);

    tamperFile(tempRoot, 'replay/vlm_overview.json', utf8.encode('{"tampered":true}'));
    replay = ControlledReplay(repoRoot: tempRoot.path, fixture: fixture);
    final results = replay.fetchAll();
    expect(results.single.ok, isFalse);
    expect(results.single.errors.join(), contains('replay_hash_mismatch'));

    final ghost = replay.fetch('not-declared');
    expect(ghost.ok, isFalse);
    expect(ghost.errors.join(), contains('replay_response_not_declared'));

    // 回放失败会落到 runner 的 replay 层。
    final batch = FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out').runBatch(parse());
    expect(batch.fixtureReports.single.layers['replay']!.ok, isFalse);
  });

  test('真实录制机器拒绝：缺删除策略在准入层拒；政策层拒 authorized_real 录制', () {
    // 1) authorized_real 但缺 deletion → manifest 级拒绝（V3-001A 边界）。
    final missingDeletion = authorizedRealManifest(tempRoot);
    (missingDeletion['data_boundary'] as Map<String, Object?>).remove('deletion');
    final outcome = FixtureManifest.parse(missingDeletion);
    expect(outcome.isOk, isFalse);
    expect(outcome.errors.map((e) => e.code), contains('data_boundary_missing_deletion'));

    // 2) 边界完整 + authorized_real 录制 → runner data_policy 层拒绝。
    final full = FixtureManifest.parse(authorizedRealManifest(tempRoot)).manifest!;
    final batch =
        FixtureRunner(repoRoot: tempRoot.path, spec: spec, outputRoot: 'runs-out').runBatch(full);
    expect(batch.ok, isFalse);
    final report = batch.fixtureReports.single;
    expect(report.status, 'rejected');
    expect(report.layers['data_policy']!.ok, isFalse);
    expect(report.layers['data_policy']!.errors.join(), contains('synthetic_only'));
  });

  test('批量 CLI：exit 0 全过；篡改后 exit 非零（故意失败退出非零）+ 三次运行 hash 一致', () {
    final dart = findDart();
    final manifestPath = '${tempRoot.path}${Platform.pathSeparator}manifest.json';
    File(manifestPath).writeAsStringSync(jsonEncode(manifestJson));
    final outDir = '${tempRoot.path}${Platform.pathSeparator}runs-out';

    (int, Map<String, Object?>) runOnce() {
      final result = Process.runSync(dart, [
        'run', 'tool/smart_layout_v3/main.dart', 'run',
        '--manifest', manifestPath,
        '--repo-root', tempRoot.path,
        '--output', 'runs-out',
      ], workingDirectory: Directory.current.path);
      final text = (result.stdout as String).trim();
      final jsonStart = text.indexOf('{');
      return (result.exitCode, jsonDecode(text.substring(jsonStart)) as Map<String, Object?>);
    }

    final hashes = <String>{};
    for (var i = 0; i < 3; i++) {
      final (exitCode, payload) = runOnce();
      expect(exitCode, 0, reason: payload.toString());
      expect(payload['ok'], isTrue);
      hashes.add(payload['content_sha256'] as String);
    }
    expect(hashes.length, 1, reason: '三次运行的内容哈希必须一致：$hashes');
    expect(File('$outDir${Platform.pathSeparator}batch-report.json').existsSync(), isTrue);

    // 准入层只核对录制响应的存在性；回放层的完整性哈希在此拦截：
    // 故意失败落在 run 管线内部而非整单准入。
    tamperFile(tempRoot, 'replay/vlm_overview.json', utf8.encode('{"tampered":true}'));
    final (failExit, failPayload) = runOnce();
    expect(failExit, isNot(0), reason: '故意失败必须退出非零');
    expect(failPayload['ok'], isFalse);
    expect(failPayload['failed'], 1);
    final failedReport = jsonDecode(File(
            '${tempRoot.path}${Platform.pathSeparator}runs-out${Platform.pathSeparator}f-det${Platform.pathSeparator}report.json')
        .readAsStringSync()) as Map<String, Object?>;
    expect(failedReport['status'], 'failed', reason: '失败报告必须保留在盘');
    expect((failedReport['layers'] as Map<String, Object?>)['replay'].toString(), contains('replay_hash_mismatch'));
  }, timeout: const Timeout(Duration(minutes: 4)));
}

BenchmarkSpec _repoSpec() {
  final path =
      'tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
  return BenchmarkSpec.load(jsonDecode(File(path).readAsStringSync())).spec!;
}
