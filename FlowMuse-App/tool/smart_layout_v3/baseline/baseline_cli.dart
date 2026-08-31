/// V3-003A 基线 CLI：对池 manifest 逐样本运行基线策略，
/// 产出 baseline-run.json + scenes/ + pngs/；确定性 run_hash 可复跑对比。
///
/// 用法（FlowMuse-App 目录）：
///   dart run tool/smart_layout_v3/baseline/baseline_cli.dart
///     参数依次为 pool_root、policy(no_op|v2_naive_reflow)、out_dir
/// 退出码：0 全部样本成功；2 存在 failed 样本（崩溃/解析失败绝不计成功）；3 输入错误。
library;

import 'dart:convert';
import 'dart:io' show Directory, File, ProcessInfo, stderr, stdout, exit;

import 'smart_layout_baseline_runner.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: baseline_cli.dart pool_root policy out_dir');
    exit(3);
  }
  final poolRoot = Directory(args[0]);
  final policy = args[1];
  final outDir = Directory(args[2]);
  if (!poolRoot.existsSync() || !SmartLayoutBaselineRunner.policies.contains(policy)) {
    stderr.writeln('pool root missing or unknown policy');
    exit(3);
  }
  final manifestFile = File('${poolRoot.path}/dataset-manifest.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln('pool manifest missing');
    exit(3);
  }
  outDir.createSync(recursive: true);
  Directory('${outDir.path}/scenes').createSync(recursive: true);
  Directory('${outDir.path}/pngs').createSync(recursive: true);

  final manifest = jsonDecode(manifestFile.readAsStringSync(encoding: utf8))
      as Map<String, Object?>;
  final samples = (manifest['samples'] as List).cast<Map<String, Object?>>();

  final results = <Map<String, Object?>>[];
  final stopwatch = Stopwatch()..start();
  var failed = 0;
  for (final sample in samples) {
    final sampleId = sample['sample_id'] as String;
    final content = sample['content'] as Map<String, Object?>;
    final sceneFile = File('${poolRoot.path}/${content['path']}');
    Map<String, Object?>? inputScene;
    String? error;
    try {
      inputScene = jsonDecode(sceneFile.readAsStringSync(encoding: utf8)) as Map<String, Object?>;
    } catch (e) {
      error = 'scene_load_failed: $e';
    }
    if (inputScene == null) {
      failed++;
      results.add({
        'sample_id': sampleId,
        'status': 'failed',
        'error': error,
      });
      continue;
    }
    try {
      final output = SmartLayoutBaselineRunner.applyPolicy(policy, inputScene);
      final evaluation = SmartLayoutBaselineRunner.evaluate(inputScene, output);
      final sceneBytes =
          utf8.encode('${const JsonEncoder.withIndent('  ').convert(output)}\n');
      final pngBytes = SmartLayoutBaselineRunner.rasterizePng(output);
      File('${outDir.path}/scenes/$sampleId.scene.json').writeAsBytesSync(sceneBytes);
      File('${outDir.path}/pngs/$sampleId.png').writeAsBytesSync(pngBytes);
      results.add({
        'sample_id': sampleId,
        'status': 'ok',
        'input_scene_sha256': SmartLayoutBaselineRunner.canonicalSceneSha256(inputScene),
        'output_scene_sha256':
            SmartLayoutBaselineRunner.sha256Of(sceneBytes),
        'output_png_sha256': SmartLayoutBaselineRunner.sha256Of(pngBytes),
        'metrics': evaluation.toJson(),
      });
    } catch (e) {
      // 策略执行崩溃：记 failed，不抛出、不中断其余样本。
      failed++;
      results.add({
        'sample_id': sampleId,
        'status': 'failed',
        'error': 'policy_crashed: $e',
      });
    }
  }
  final elapsedUs = stopwatch.elapsedMicroseconds;
  final peakRssKb = ProcessInfo.currentRss ~/ 1024;

  final runHash = SmartLayoutBaselineRunner.sha256Of(utf8.encode(
      const JsonEncoder().convert({
        'policy': policy,
        'samples': [
          for (final r in results)
            if (r['status'] == 'ok')
              {
                'sample_id': r['sample_id'],
                'output_scene_sha256': r['output_scene_sha256'],
                'output_png_sha256': r['output_png_sha256'],
                'metrics': r['metrics'],
              }
        ],
      })));

  final run = {
    'schema_version': '1.0.0',
    'artifact': 'smart-layout-v3-baseline-run',
    'task': 'V3-003A',
    'policy': policy,
    'policy_note': policy == 'no_op'
        ? '输出=输入（参照端点）'
        : 'v2 代表策略：单列自上而下重排内容元素（确定性 dev 线近似，非生产 v2 输出复刻）',
    'pool': {
      'name': (manifest['dataset'] as Map<String, Object?>)['name'],
      'sample_count': samples.length,
    },
    'status': failed == 0 ? 'ok' : 'failed',
    'ok_samples': results.where((r) => r['status'] == 'ok').length,
    'failed_samples': failed,
    'samples': results,
    'run_hash': runHash,
    'resource': {
      'total_elapsed_us': elapsedUs,
      'peak_rss_kb': peakRssKb,
      'note': '资源数据不进入 run_hash（确定性产物只含 Scene/PNG/指标）。',
    },
  };
  final runBytes = utf8.encode('${const JsonEncoder.withIndent('  ').convert(run)}\n');
  File('${outDir.path}/baseline-run.json').writeAsBytesSync(runBytes);
  stdout.writeln('baseline $policy: status=${run['status']} ok=${run['ok_samples']} '
      'failed=$failed run_hash=$runHash');
  exit(failed == 0 ? 0 : 2);
}
