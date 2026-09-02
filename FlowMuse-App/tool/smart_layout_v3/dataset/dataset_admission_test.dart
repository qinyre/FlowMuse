import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'annotation_agreement_calculator.dart';
import 'dataset_admission_validator.dart';

/// V3-002A 契约测试：数据集准入边界与标注一致性计算。
///
/// 覆盖：合成/许可样本准入正例；真实用户内容拒绝；非确定性合成拒绝；
/// 许可/内容 hash 实测失败拒绝；派生链闭合与无环；禁止用途/删除流程缺失拒绝；
/// 一致性统计与 DG3/DG4 仲裁合并语义。
void main() {
  String shaOf(String text) => crypto.sha256.convert(utf8.encode(text)).toString();

  Map<String, Object?> syntheticSample({
    String id = 'syn-seed-0001',
    List<String> derivationChain = const [],
    bool deterministic = true,
    Object? license,
    String? contentSha,
    Map<String, Object?>? features,
  }) =>
      {
        'sample_id': id,
        'kind': 'synthetic',
        'origin': {
          'generator': {
            'name': 'seed-scene-composer',
            'version': '1.0.0',
            'seed': 12345,
            'params_sha256': 'a' * 64,
            'deterministic': deterministic,
          },
          'generated_at_utc': '2026-08-31T00:00:00Z',
          'derivation_chain': derivationChain,
        },
        'rights': {
          'kind': 'synthetic',
          'license': license,
          'forbidden_uses': ['production_release_claims', 'human_validation_claims'],
          'deletion': {
            'policy_id': 'regenerable-synthetic-v1',
            'method': 'regenerable_no_retention',
            'reference': 'datasets/synthetic-seed-v1/tools/generate.py',
          },
        },
        'content': {
          'path': 'samples/$id.scene.json',
          'sha256': contentSha ?? 'b' * 64,
        },
        'features': features ??
            {
              'content_kind': 'handwritten_only',
              'stroke_count': 12,
              'has_images': false,
              'has_formula': false,
              'has_shapes': false,
              'has_groups': false,
              'has_frames': false,
              'has_bindings': false,
              'has_locked_objects': false,
              'has_decorative_lines': false,
              'has_list': false,
              'long_form': false,
              'vertical_text_preserved': false,
              'tidy_page': true,
              'scattered_page': false,
              'pressure_stress': false,
              'known_failure_page': false,
            },
      };

  Map<String, Object?> licensedSample({required String documentSha}) => {
        'sample_id': 'lic-0001',
        'kind': 'licensed',
        'origin': {
          'source': {'supplier_id': 'fixture-supplier', 'reference': 'fixtures/licenses/lic-0001'},
          'acquired_at_utc': '2026-08-31T00:00:00Z',
          'derivation_chain': const [],
        },
        'rights': {
          'kind': 'licensed',
          'license': {
            'license_id': 'FIXTURE-LIC-0001',
            'document_path': 'licenses/lic-0001.txt',
            'document_sha256': documentSha,
            'scope': 'development_evaluation_only',
          },
          'forbidden_uses': ['production_release_claims'],
          'deletion': {
            'policy_id': 'fixture-deletion',
            'method': 'on_request',
            'reference': 'fixtures/deletion-policy.txt',
          },
        },
        'content': {'path': 'samples/lic-0001.scene.json', 'sha256': 'c' * 64},
        'features': syntheticSample()['features'] as Map<String, Object?>,
      };

  Map<String, Object?> manifestWith(List<Map<String, Object?>> samples) => {
        'schema_version': '1.0.0',
        'dataset_kind': 'smart-layout-v3-dataset-manifest',
        'dataset': {
          'name': 'synthetic-seed-v1',
          'version': '1.0.0',
          'generated_at_utc': '2026-08-31T00:00:00Z',
          'lane': 'ai_synthetic_development',
          'admission_policy': {
            'admitted_kinds': ['synthetic', 'licensed'],
            'rejected_kinds': ['real_user_content'],
            'rejection_directive': 'real_user_content 保持隔离并推迟到 V3-700A 授权包',
          },
        },
        'samples': samples,
      };

  (Map<String, Object?>, DatasetFileResolver) buildSyntheticManifest() {
    final content = '{"page":{"elements":[]}}';
    final files = <String, List<int>>{
      'samples/syn-seed-0001.scene.json': utf8.encode(content),
    };
    final manifest = manifestWith([syntheticSample(contentSha: shaOf(content))]);
    return (manifest, (path) => files[path]);
  }

  group('DatasetAdmissionValidator 准入正例', () {
    test('确定性合成样本（内容 hash 实测通过）准入', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.isOk, isTrue, reason: outcome.errors.map((e) => e.toString()).join('\n'));
      expect(outcome.samples, hasLength(1));
      expect(outcome.samples.single.kind, 'synthetic');
    });

    test('机器可验证许可样本准入（许可文档 hash 实测通过）', () {
      const licenseText = 'FIXTURE LICENSE TEXT (test fixture, not a real license)';
      const content = '{"page":{"elements":[]}}';
      final files = {
        'licenses/lic-0001.txt': utf8.encode(licenseText),
        'samples/lic-0001.scene.json': utf8.encode(content),
      };
      final sample = licensedSample(documentSha: shaOf(licenseText));
      (sample['content'] as Map)['sha256'] = shaOf(content);
      final outcome = DatasetAdmissionValidator.validate(
        manifestWith([sample]),
        resolveFile: (path) => files[path],
      );
      expect(outcome.isOk, isTrue, reason: outcome.errors.map((e) => e.toString()).join('\n'));
      expect(outcome.samples.single.kind, 'licensed');
    });
  });

  group('DatasetAdmissionValidator 拒绝路径', () {
    test('真实用户内容拒绝并指向 V3-700A', () {
      final (manifest, resolve) = buildSyntheticManifest();
      (manifest['samples'] as List).add({
        'sample_id': 'real-0001',
        'kind': 'real_user_content',
        'origin': {},
        'rights': {},
        'content': {},
        'features': {},
      });
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.map((e) => e.code), contains('real_user_content_not_admissible'));
      expect(
        outcome.errors.firstWhere((e) => e.code == 'real_user_content_not_admissible').message,
        contains('V3-700A'),
      );
    });

    test('非确定性合成样本拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      ((sample['origin'] as Map)['generator'] as Map)['deterministic'] = false;
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('synthetic_not_deterministic'));
    });

    test('合成样本冒充许可来源拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      (sample['rights'] as Map)['license'] = {
        'license_id': 'FAKE',
        'document_path': 'licenses/fake.txt',
        'document_sha256': '0' * 64,
        'scope': 'x',
      };
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('synthetic_license_forbidden'));
    });

    test('许可文档不可解析拒绝（来源或许可不可机器验证）', () {
      final (manifest, resolve) = buildSyntheticManifest();
      (manifest['samples'] as List).add(licensedSample(documentSha: 'd' * 64));
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('file_unresolvable'));
    });

    test('许可文档 hash 不匹配拒绝', () {
      const licenseText = 'FIXTURE LICENSE TEXT';
      final sample = licensedSample(documentSha: 'e' * 64);
      final outcome = DatasetAdmissionValidator.validate(
        manifestWith([sample]),
        resolveFile: (path) => path == 'licenses/lic-0001.txt' ? utf8.encode(licenseText) : null,
      );
      expect(outcome.errors.map((e) => e.code), contains('hash_mismatch'));
    });

    test('内容 hash 不匹配拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      (sample['content'] as Map)['sha256'] = 'f' * 64;
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('hash_mismatch'));
    });

    test('未知派生父拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      (manifest['samples'] as List)
          .add(syntheticSample(id: 'syn-seed-0002', derivationChain: const ['syn-seed-9999']));
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('unknown_derivation_parent'));
    });

    test('派生链成环拒绝', () {
      final outcome = DatasetAdmissionValidator.validate(
        manifestWith([
          syntheticSample(id: 'syn-seed-a', derivationChain: const ['syn-seed-b']),
          syntheticSample(id: 'syn-seed-b', derivationChain: const ['syn-seed-a']),
        ]),
        resolveFile: _memoryResolver(),
      );
      expect(outcome.errors.map((e) => e.code), contains('derivation_cycle'));
    });

    test('禁止用途与删除流程缺失拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      (sample['rights'] as Map).remove('forbidden_uses');
      (sample['rights'] as Map).remove('deletion');
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      final missing = outcome.errors
          .where((e) => e.code == 'field_missing' && e.pointer.contains('/rights'))
          .map((e) => e.pointer)
          .toList();
      expect(missing, contains('#/samples/0/rights/forbidden_uses'));
      expect(missing, contains('#/samples/0/rights/deletion'));
    });

    test('未知字段拒绝（additionalProperties 语义）', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      sample['extra_field'] = 1;
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('unknown_field'));
    });

    test('admission_policy 未拒绝真实用户内容时 manifest 整体拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final policy = (manifest['dataset'] as Map)['admission_policy'] as Map<String, Object?>;
      policy['rejected_kinds'] = <String>['synthetic'];
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('real_user_content_not_rejected'));
    });

    test('非开发线 lane 拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      (manifest['dataset'] as Map)['lane'] = 'production_release';
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('lane_not_development'));
    });

    test('features 非法值拒绝', () {
      final (manifest, resolve) = buildSyntheticManifest();
      final sample = (manifest['samples'] as List).first as Map<String, Object?>;
      final features = sample['features'] as Map<String, Object?>;
      features['stroke_count'] = -1;
      features['tidy_page'] = 'yes';
      final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolve);
      expect(outcome.errors.map((e) => e.code), contains('invalid_stroke_count'));
      expect(outcome.errors.map((e) => e.code), contains('invalid_feature_flag'));
    });

    test('样本 id 重复拒绝', () {
      final outcome = DatasetAdmissionValidator.validate(
        manifestWith([
          syntheticSample(id: 'syn-seed-dup'),
          syntheticSample(id: 'syn-seed-dup'),
        ]),
        resolveFile: _memoryResolver(),
      );
      expect(outcome.errors.map((e) => e.code), contains('duplicate_sample_id'));
    });
  });

  group('AnnotationAgreementCalculator', () {
    AnnotationSet rater(String id, List<AnnotationRating> ratings) =>
        AnnotationSet(raterId: id, ratings: ratings);

    test('exact/Δ1/Δ≥2/insufficient 翻转/code 分歧全统计', () {
      final a = rater('A', const [
        AnnotationRating(
          sampleId: 's1',
          scores: {'D1': 5, 'D5': 3},
          codes: ['M-LAYOUT-OVERLAP'],
        ),
        AnnotationRating(sampleId: 's2', scores: {'D1': 4}),
        AnnotationRating(sampleId: 's3', scores: {'D5': 1, 'D6': 2}, codes: ['C-TX-CAS-DIRTY-WRITE']),
        AnnotationRating(sampleId: 's4', scores: {'D1': 5}, codes: ['M-SNAPSHOT-PROTECTED-DAMAGE']),
      ]);
      final b = rater('B', const [
        AnnotationRating(
          sampleId: 's1',
          scores: {'D1': 5, 'D5': 4},
          codes: ['M-LAYOUT-OVERLAP'],
        ),
        AnnotationRating(sampleId: 's2', scores: {'D1': null}),
        AnnotationRating(sampleId: 's3', scores: {'D5': 3, 'D6': 2}),
        AnnotationRating(sampleId: 's4', scores: {'D1': 5}, codes: ['M-LAYOUT-FONT-FLOOR']),
      ]);
      final report = AnnotationAgreementCalculator.calculate(a, b);
      expect(report.hasErrors, isFalse);
      expect(report.slots, 6);
      expect(report.exact, 3, reason: 's1.D1、s3.D6、s4.D1 完全一致');
      expect(report.within1, 4, reason: '再含 s1.D5（3 vs 4）');
      expect(report.perDimension['D5']!.deltaGe2, 1, reason: 's3.D5（1 vs 3）');
      expect(report.perDimension['D1']!.insufficientFlips, 1, reason: 's2.D1（4 vs null）');
      final kinds = report.disagreements.map((d) => d.kind).toSet();
      expect(kinds, containsAll(['delta_ge2', 'insufficient_flip', 'code_set_difference']));
      final json = report.toJson();
      // 4 个仲裁项：s2.D1 insufficient 翻转、s3.D5 Δ≥2、s3 与 s4 的 code 集分歧（A 有码 B 无码亦算分歧）。
      expect(json['arbitration_eligible'], 4);
      expect(json['code_set_differences'], 2);
      expect(json['exact_rate'], closeTo(0.5, 1e-9));
    });

    test('样本集合不一致报机器错误', () {
      final a = rater('A', const [AnnotationRating(sampleId: 's1', scores: {'D1': 5})]);
      final b = rater('B', const [AnnotationRating(sampleId: 's9', scores: {'D1': 5})]);
      final report = AnnotationAgreementCalculator.calculate(a, b);
      expect(report.hasErrors, isTrue);
      expect(report.errors.first, startsWith('annotation_set_mismatch'));
    });

    test('仲裁合并：Δ≥2 必须有裁决，Δ=1 保守取低，overall 取最小', () {
      final a = rater('A', const [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5, 'D5': 3, 'D6': 2}),
      ]);
      final b = rater('B', const [
        AnnotationRating(sampleId: 's1', scores: {'D1': 4, 'D5': 5, 'D6': 2}),
      ]);
      final adjudicated = AnnotationAgreementCalculator.applyArbitration(
        raterA: a,
        raterB: b,
        rulings: const [
          ArbitrationRuling(sampleId: 's1', dimension: 'D5', kind: 'delta_ge2', finalScore: 4),
        ],
      );
      expect(adjudicated.hasErrors, isFalse);
      final rating = adjudicated.ratings.single;
      expect(rating.scores, {'D1': 4, 'D5': 4, 'D6': 2});
      expect(rating.overall, 2);
      expect(adjudicated.conservativeApplied, 1);
      expect(adjudicated.toJson()['conservative_delta1_applied'], 1);
    });

    test('Δ≥2 缺裁决报 arbitration_missing 并降 insufficient', () {
      final a = rater('A', const [AnnotationRating(sampleId: 's1', scores: {'D5': 1})]);
      final b = rater('B', const [AnnotationRating(sampleId: 's1', scores: {'D5': 5})]);
      final adjudicated = AnnotationAgreementCalculator.applyArbitration(
        raterA: a,
        raterB: b,
        rulings: const [],
      );
      expect(adjudicated.hasErrors, isTrue);
      expect(adjudicated.errors.single, startsWith('arbitration_missing'));
      final rating = adjudicated.ratings.single;
      expect(rating.insufficientDimensions, ['D5']);
      expect(rating.overallInsufficient, isTrue);
    });

    test('code 集分歧由仲裁给出最终 codes', () {
      final a = rater('A', const [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}, codes: ['C-SNAPSHOT-LOST-SOURCE']),
      ]);
      final b = rater('B', const [
        AnnotationRating(sampleId: 's1', scores: {'D1': 5}, codes: ['M-SNAPSHOT-PROTECTED-DAMAGE']),
      ]);
      final adjudicated = AnnotationAgreementCalculator.applyArbitration(
        raterA: a,
        raterB: b,
        rulings: const [
          ArbitrationRuling(
            sampleId: 's1',
            kind: 'code_set_difference',
            finalCodes: ['C-SNAPSHOT-LOST-SOURCE', 'M-SNAPSHOT-PROTECTED-DAMAGE'],
          ),
        ],
      );
      expect(adjudicated.hasErrors, isFalse);
      expect(adjudicated.ratings.single.codes,
          ['C-SNAPSHOT-LOST-SOURCE', 'M-SNAPSHOT-PROTECTED-DAMAGE']);
    });
  });
}

/// 惰性内容 resolver：路径首次出现时生成并缓存确定性内容。
DatasetFileResolver _memoryResolver() {
  final cache = <String, List<int>>{};
  return (path) => cache.putIfAbsent(path, () => utf8.encode('content-of:$path'));
}
