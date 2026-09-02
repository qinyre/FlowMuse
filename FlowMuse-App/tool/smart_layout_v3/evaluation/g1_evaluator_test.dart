import 'package:flutter_test/flutter_test.dart';

import 'g1_inputs.dart';
import 'recognition_latency_evaluator.dart';
import 'recognition_quality_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('期望分组构造', () {
    test('非空阅读序：同 role 连续段', () {
      final annotation = G1Annotation.fromJson({
        'sample_id': 's',
        'reading_order': ['e1', 'e2', 'e3', 'e4'],
        'roles': {
          'e1': 'title',
          'e2': 'paragraph',
          'e3': 'paragraph',
          'e4': 'title',
        },
      });
      final groups = annotation.expectedGroups();
      expect(groups.map((g) => g.length).toList(), [1, 2, 1]);
      expect(groups[0], ['e1']);
      expect(groups[1], ['e2', 'e3']);
    });

    test('空阅读序兜底：按 role 全集聚类', () {
      final annotation = G1Annotation.fromJson({
        'sample_id': 's',
        'reading_order': [],
        'roles': {'e2': 'paragraph', 'e1': 'title'},
      });
      final groups = annotation.expectedGroups();
      expect(groups, [
        ['e2'],
        ['e1'],
      ]);
    });
  });

  group('RecognitionQualityEvaluator', () {
    G1SceneSample sampleOf(String id, List<List<double>> boxes) =>
        G1SceneSample(
          sampleId: id,
          elementTypeById: {
            for (var i = 0; i < boxes.length; i++) '$id-s$i': 'stroke',
          },
          strokes: [
            for (var i = 0; i < boxes.length; i++)
              {
                'id': '$id-s$i',
                'type': 'stroke',
                'bbox': boxes[i],
                'points': [
                  [boxes[i][0], boxes[i][1]],
                ],
              },
          ],
        );

    test('完全正确分组 → P/R/F1=1，零 merge/split', () {
      // 两簇远距笔画 → 两个预测组；期望也两组。
      final sample = sampleOf('q1', [
        [10, 10, 30, 8],
        [40, 11, 30, 8],
        [10, 100, 30, 8],
        [40, 101, 30, 8],
      ]);
      final report = RecognitionQualityEvaluator(minSamples: 1).evaluate(
        splitName: 'development',
        sampleIds: ['q1'],
        samplesById: {'q1': sample},
        labelsBySample: {
          'q1': G1Annotation.fromJson({
            'sample_id': 'q1',
            'reading_order': ['e0', 'e1', 'e2', 'e3'],
            'roles': {
              'e0': 'handwriting',
              'e1': 'handwriting',
              'e2': 'paragraph',
              'e3': 'paragraph',
            },
          }),
        },
        idMappingBySample: {
          'q1': {'e0': 'q1-s0', 'e1': 'q1-s1', 'e2': 'q1-s2', 'e3': 'q1-s3'},
        },
      );
      expect(report.pairPrecision, 1.0);
      expect(report.pairRecall, 1.0);
      expect(report.mergeErrors, 0);
      expect(report.splitErrors, 0);
      expect(report.verdicts['stroke_conservation'], 'pass');
    });

    test('低样本 → insufficient 明确', () {
      final sample = sampleOf('q2', [
        [10, 10, 30, 8],
        [40, 11, 30, 8],
      ]);
      final report = RecognitionQualityEvaluator(minSamples: 5).evaluate(
        splitName: 'development',
        sampleIds: ['q2'],
        samplesById: {'q2': sample},
        labelsBySample: {
          'q2': G1Annotation.fromJson({
            'sample_id': 'q2',
            'reading_order': ['e0', 'e1'],
            'roles': {'e0': 'title', 'e1': 'title'},
          }),
        },
        idMappingBySample: {
          'q2': {'e0': 'q2-s0', 'e1': 'q2-s1'},
        },
      );
      expect(report.verdicts['quality'], 'insufficient');
      expect(report.verdicts['low_sample'], 'insufficient(1<5)');
    });
  });

  group('RecognitionLatencyEvaluator', () {
    test('nearest_rank 百分位与预算判定', () {
      final evaluator = RecognitionLatencyEvaluator(minSamples: 1);
      final sample = G1SceneSample(
        sampleId: 'l1',
        elementTypeById: const {'l1-s0': 'stroke'},
        strokes: [
          {
            'id': 'l1-s0',
            'type': 'stroke',
            'bbox': [10.0, 10.0, 30.0, 8.0],
            'points': [
              [10.0, 10.0],
            ],
          },
        ],
      );
      final report = evaluator.measure(
        sampleIds: ['l1'],
        samplesById: {'l1': sample},
      );
      expect(report.verdicts['latency'], 'pass', reason: '单样本远低于 300s 预算');
      expect(report.p50Ms, greaterThan(0));
      expect(report.p50Ms, lessThan(report.maxMs + 0.001));
    });

    test('nearest_rank 数学（偶数列取上位）', () {
      final values = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      // nearest_rank: ceil(0.5*10)=5 → 第 5 小=5；ceil(0.95*10)=10 → 10。
      expect(RecognitionLatencyEvaluator.nearestRank(values, 0.50), 5);
      expect(RecognitionLatencyEvaluator.nearestRank(values, 0.95), 10);
    });
  });
}
