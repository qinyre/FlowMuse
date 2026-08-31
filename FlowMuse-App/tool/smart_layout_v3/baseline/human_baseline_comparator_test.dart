import 'package:flutter_test/flutter_test.dart';

import 'human_baseline_comparator.dart';

/// V3-003B 契约测试：三基线并表（HumanBaselineComparator）。
void main() {
  Map<String, Object?> poolSample(String id, String family, int strokes) => {
        'sample_id': id,
        'scene_family': family,
        'features': {'stroke_count': strokes},
      };
  final poolManifest = {
    'samples': [
      poolSample('s1', 'meeting-notes', 8), // low
      poolSample('s2', 'lecture-notes', 50), // high
      poolSample('s3', 'brainstorm-board', 0), // none
    ],
  };
  Map<String, Object?> scene(List<Map<String, Object?>> elements) => {
        'page': {'width': 720, 'height': 1280},
        'elements': elements,
      };
  Map<String, Object?> el(String id, String type, List<num> bbox) =>
      {'id': id, 'type': type, 'bbox': bbox};
  final inputS1 = scene([el('a', 'text', [10, 10, 100, 40]), el('s', 'stroke', [1, 2, 3, 4])]);

  Map<String, Object?> run(String policy, List<Map<String, Object?>> samples) =>
      {'policy': policy, 'samples': samples};
  final autoRuns = {
    'no_op': run('no_op', [
      {'sample_id': 's1', 'status': 'ok', 'metrics': {'oob_count': 1, 'failure_codes': ['M-LAYOUT-OOB']}},
      {'sample_id': 's2', 'status': 'ok', 'metrics': {'oob_count': 2, 'failure_codes': []}},
      {'sample_id': 'sX', 'status': 'ok', 'metrics': {'oob_count': 99}}, // 不在池中→忽略
    ]),
    'v2_naive_reflow': run('v2_naive_reflow', [
      {'sample_id': 's1', 'status': 'ok', 'metrics': {'oob_count': 0, 'failure_codes': []}},
      {'sample_id': 's2', 'status': 'failed'}, // failed 绝不计入
    ]),
  };

  test('并表：per-sample 三策略行 + ai_surrogate 指标经 evaluate 实算', () {
    final report = HumanBaselineComparator.compare(
      poolManifest: poolManifest,
      splitLookup: {'s1': 'development', 's2': 'validation'}, // s3 缺失 → unknown
      autoRuns: autoRuns,
      inputScenes: {'s1': inputS1},
      aiBaseline: {
        's1': {
          'scene': inputS1, // 与输入一致 → evaluate 零违规
          'modification_count': 3,
          'steps': const [
            {'element_id': 'a'},
          ],
        },
      },
      replayCheck: {'status': 'passed'},
    );
    final rows = (report['layers'] as Map<String, Object?>)['overall'] as Map<String, Object?>;
    expect(rows['samples'], 3);

    final noOp = rows['no_op'] as Map<String, Object?>;
    expect(noOp['samples_with_metrics'], 2); // s1,s2 有 ok 记录；sX 不在池中被忽略
    expect(noOp['oob_total'], 3.0); // 1+2
    expect(noOp['samples_with_failure_codes'], 1); // 仅 s1 违规

    final v2 = rows['v2_naive_reflow'] as Map<String, Object?>;
    expect(v2['samples_with_metrics'], 1); // s2 failed 绝不计成功
    expect(v2['oob_total'], 0.0);

    final ai = rows['ai_surrogate'] as Map<String, Object?>;
    expect(ai['samples_with_metrics'], 1); // 只有 s1 有 aiBaseline+inputScene
    expect(ai['oob_total'], 0.0);
    expect(ai['modification_count_total'], 3);

    // 分层：s3 无 split → unknown 组；复杂度带 none/low/high 各成组。
    final bySplit = (report['layers'] as Map<String, Object?>)['by_split'] as Map<String, Object?>;
    expect(bySplit.keys, containsAll(['development', 'validation', 'unknown']));
    final byBand =
        (report['layers'] as Map<String, Object?>)['by_complexity_band'] as Map<String, Object?>;
    expect(byBand.keys, containsAll(['none', 'low', 'high']));
    // replayCheck 原样嵌入。
    expect((report['replay_check'] as Map<String, Object?>)['status'], 'passed');
  });

  test('披露：AI surrogate 三要素逐字出现，不声称人工验证', () {
    final report = HumanBaselineComparator.compare(
      poolManifest: poolManifest,
      splitLookup: const {},
      autoRuns: const {},
      inputScenes: const {},
      aiBaseline: const {},
      replayCheck: const {},
    );
    final d = report['panel_disclosure'] as Map<String, Object?>;
    expect(d['panel_type'], 'ai_surrogate');
    expect(d['human_validation_performed'], false);
    expect(d['disclosure'], 'HUMAN_VALIDATION_NOT_PERFORMED');
    expect(d['statement'] as String, contains('不代表真人整理效率'));
  });
}
