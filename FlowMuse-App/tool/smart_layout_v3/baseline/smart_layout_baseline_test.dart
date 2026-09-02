import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../src/canonical_artifacts.dart';
import 'smart_layout_baseline_runner.dart';

/// V3-003A 契约测试：两条基线策略、评测谓词、PNG 编码与可重复性。
void main() {
  Map<String, Object?> scene(List<Map<String, Object?>> elements,
          {int width = 1240, int height = 1754}) =>
      {'page': {'width': width, 'height': height}, 'elements': elements};

  Map<String, Object?> el(String id, String type, List<num> bbox, {String? chars}) => {
        'id': id,
        'type': type,
        'bbox': bbox,
        'x': ?chars,
      };

  test('no_op：输出与输入逐元素一致，评测零失败', () {
    final input = scene([
      el('e1', 'text', [100, 100, 200, 40], chars: '段落1段落1'),
      el('e2', 'stroke', [10, 200, 50, 30]),
      el('e3', 'image', [300, 60, 120, 90]),
    ]);
    final output = SmartLayoutBaselineRunner.applyPolicy('no_op', input);
    expect(jsonEncode(output), jsonEncode(input));
    final evaluation = SmartLayoutBaselineRunner.evaluate(input, output);
    expect(evaluation.sourceRecall, 1.0);
    expect(evaluation.codes, isEmpty);
  });

  test('v2_naive_reflow：内容元素单列重排、笔迹保持原位、无重叠无丢失', () {
    final input = scene([
      el('e1', 'text', [800, 500, 200, 40], chars: 'A'),
      el('e2', 'text', [60, 900, 200, 60], chars: 'B'),
      el('e3', 'image', [400, 100, 120, 90]),
      el('s1', 'stroke', [10, 200, 50, 30]),
    ]);
    final output = SmartLayoutBaselineRunner.applyPolicy('v2_naive_reflow', input);
    final byId = {
      for (final e in (output['elements'] as List).cast<Map<String, Object?>>())
        e['id'] as String: e,
    };
    expect(byId.keys, containsAll(['e1', 'e2', 'e3', 's1']));
    // 笔迹原位。
    expect((byId['s1']!['bbox'] as List).cast<num>(), [10, 200, 50, 30]);
    // 内容元素按阅读序排入单列（x=24）。
    expect((byId['e3']!['bbox'] as List).cast<num>()[0], 24);
    expect((byId['e3']!['bbox'] as List).cast<num>()[1], 24);
    final y1 = (byId['e1']!['bbox'] as List).cast<num>()[1];
    final y2 = (byId['e2']!['bbox'] as List).cast<num>()[1];
    expect(y1, lessThan(y2)); // e3(row 1) < e1 < e2 按原行带序。
    final evaluation = SmartLayoutBaselineRunner.evaluate(input, output);
    expect(evaluation.sourceRecall, 1.0);
    expect(evaluation.codes, isEmpty, reason: evaluation.codes.join(','));
  });

  test('评测谓词：源丢失/字符流截断/OOB/重叠各自计码', () {
    final input = scene([
      el('t1', 'text', [10, 10, 100, 30], chars: 'abcdef'),
      el('t2', 'text', [10, 60, 100, 30], chars: 'ghijk'),
      el('b1', 'shape', [10, 110, 100, 30]),
    ]);
    // t2 丢失；t1 chars 截断；b1 与 t1 重叠；b2 越界。
    final output = scene([
      el('t1', 'text', [0, 0, 100, 30], chars: 'abcde'),
      el('b1', 'shape', [90, 10, 200, 50]),
      el('b2', 'shape', [1200, 1700, 300, 300]),
    ], width: 1240, height: 1754);
    final evaluation = SmartLayoutBaselineRunner.evaluate(input, output);
    expect(evaluation.codes, containsAll([
      'C-SNAPSHOT-LOST-SOURCE',
      'C-SNAPSHOT-TYPED-TEXT-LOST',
      'M-LAYOUT-OOB',
      'M-LAYOUT-OVERLAP',
    ]));
    expect(evaluation.criticalCount, 2);
    expect(evaluation.majorCount, 2);
  });

  test('PNG 编码器：合法签名可被 CanonicalArtifacts 规范化且确定性', () {
    final input = scene([el('e1', 'text', [0, 0, 800, 100])]);
    final png1 = SmartLayoutBaselineRunner.rasterizePng(input);
    final png2 = SmartLayoutBaselineRunner.rasterizePng(input);
    expect(png1, png2);
    expect(png1.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // 规范化（CRC 重算 + chunk 白名单）后仍是合法 PNG 且 hash 一致。
    final canonical = CanonicalArtifacts.canonicalPng(png1);
    expect(canonical.sublist(0, 8), png1.sublist(0, 8));
    expect(CanonicalArtifacts.canonicalPngSha256(png1),
        SmartLayoutBaselineRunner.sha256Of(canonical));
  });

  test('可重复性：CLI 双跑 run_hash 一致；failed 样本使 exit 非零', () {
    final temp = Directory.systemTemp.createTempSync('v3-003a-cli-');
    try {
      final sep = Platform.pathSeparator;
      // 构造小池：1 个好样本 + 1 个损坏样本。
      final goodScene = '{"page":{"width":400,"height":600},"elements":[]}';
      final pool = Directory('${temp.path}${sep}pool')..createSync();
      Directory('${pool.path}${sep}samples').createSync();
      File('${pool.path}${sep}samples${sep}good.scene.json')
          .writeAsStringSync(goodScene, encoding: utf8);
      File('${pool.path}${sep}samples${sep}bad.scene.json')
          .writeAsStringSync('{ 坏 JSON', encoding: utf8);
      File('${pool.path}${sep}dataset-manifest.json').writeAsStringSync(
        jsonEncode({
          'dataset': {'name': 't'},
          'samples': [
            {
              'sample_id': 'good',
              'content': {'path': 'samples/good.scene.json'},
            },
            {
              'sample_id': 'bad',
              'content': {'path': 'samples/bad.scene.json'},
            },
          ],
        }),
        encoding: utf8,
      );
      final dart = _findDart();
      (int, String) runOnce(String outName) {
        final out = Directory(temp.path + sep + outName);
        final result = Process.runSync(dart, [
          'run', 'tool/smart_layout_v3/baseline/baseline_cli.dart',
          pool.path, 'no_op', out.path,
        ], workingDirectory: Directory.current.path);
        return (
          result.exitCode,
          (jsonDecode(
                  File('${out.path}${sep}baseline-run.json').readAsStringSync(encoding: utf8))
              as Map<String, Object?>)['run_hash'] as String,
        );
      }

      final (exit1, hash1) = runOnce('out1');
      final (exit2, hash2) = runOnce('out2');
      // 损坏样本 → failed → exit 非零；好样本确定性产物 hash 双跑一致。
      expect(exit1, 2);
      expect(exit2, 2);
      expect(hash1, hash2);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}

/// 定位 dart VM（与 dataset 测试同法）。
String _findDart() {
  final exe = Platform.resolvedExecutable;
  var dir = File(exe).parent;
  for (var i = 0; i < 6; i++) {
    for (final rel in const [
      'bin/cache/dart-sdk/bin/dart.exe',
      'cache/dart-sdk/bin/dart.exe',
    ]) {
      final candidate = File(
          '${dir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
      if (candidate.existsSync()) return candidate.path;
    }
    dir = dir.parent;
  }
  return 'dart';
}
