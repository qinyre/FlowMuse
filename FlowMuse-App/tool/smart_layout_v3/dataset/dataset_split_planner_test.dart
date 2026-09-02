import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'dataset_admission_validator.dart';
import 'dataset_split_planner.dart';

/// V3-002B 契约测试：分层抽样与集合隔离。
///
/// 覆盖：隔离组件（派生链 + 相同生成器身份）不跨集合；样本唯一归属且全覆盖；
/// 配额不满足/配置非法返回机器错误；种子化确定性；已落地切分产物可再通过准入闸门。
void main() {
  Map<String, Object?> sample(
    String id, {
    String family = 'meeting-notes',
    String contentKind = 'handwritten_only',
    int strokeCount = 10,
    String platform = 'desktop',
    List<String> chain = const [],
    int seed = 1,
    String? paramsSha,
  }) =>
      {
        'sample_id': id,
        'kind': 'synthetic',
        'scene_family': family,
        'platform_profile': platform,
        'origin': {
          'generator': {
            'name': 'stratified-scene-composer',
            'version': '1.0.0',
            'seed': seed,
            'params_sha256': paramsSha ?? ('$id-params-${'a' * 32}').padRight(64, '0'),
            'deterministic': true,
          },
          'generated_at_utc': '2026-08-31T00:00:00Z',
          'derivation_chain': chain,
        },
        'rights': {
          'kind': 'synthetic',
          'license': null,
          'forbidden_uses': ['production_release_claims'],
          'deletion': {
            'policy_id': 'regenerable-synthetic-v1',
            'method': 'regenerable_no_retention',
            'reference': 'test',
          },
        },
        'content': {'path': 'samples/$id.json', 'sha256': '0' * 64},
        'features': {
          'content_kind': contentKind,
          'stroke_count': strokeCount,
          'has_images': false, 'has_formula': false, 'has_shapes': false,
          'has_groups': false, 'has_frames': false, 'has_bindings': false,
          'has_locked_objects': false, 'has_decorative_lines': false,
          'has_list': false, 'long_form': false, 'vertical_text_preserved': false,
          'tidy_page': false, 'scattered_page': false, 'pressure_stress': false,
          'known_failure_page': false,
        },
      };

  Map<String, Object?> pool(List<Map<String, Object?>> samples) => {
        'schema_version': '1.0.0',
        'dataset_kind': 'smart-layout-v3-dataset-manifest',
        'dataset': {
          'name': 'test-pool',
          'version': '1.0.0',
          'generated_at_utc': '2026-08-31T00:00:00Z',
          'lane': 'ai_synthetic_development',
          'split': 'pooled',
          'admission_policy': {
            'admitted_kinds': ['synthetic', 'licensed'],
            'rejected_kinds': ['real_user_content'],
            'rejection_directive': 'real_user_content 保持隔离并推迟到 V3-700A 授权包',
          },
        },
        'samples': samples,
      };

  Map<String, Object?> config({Map<String, Object?> quotas = const {}}) => {
        'config_kind': 'smart-layout-v3-split-config',
        'seed': 7,
        'weights': {'development': 0.6, 'validation': 0.2, 'frozen_holdout': 0.2},
        'min_quotas': {
          'development': {'per_scene_family': 1, 'per_content_kind': 1, 'per_platform_profile': 1},
          'validation': {'per_scene_family': 1},
          'frozen_holdout': {'per_scene_family': 1},
          ...quotas,
        },
        'isolation': {
          'rules': ['derivation_chain', 'same_generator_identity'],
        },
      };

  List<Map<String, Object?>> diversePool() => [
        for (final family in ['meeting-notes', 'brainstorm-board', 'annotated-diagram', 'typed-report'])
          for (final platform in ['desktop', 'mobile', 'web'])
            sample('s-${family.substring(0, 4)}-$platform',
                family: family,
                contentKind: family == 'typed-report' ? 'typed_only' : 'mixed',
                strokeCount: family == 'typed-report' ? 0 : 20,
                platform: platform,
                seed: family.hashCode + platform.hashCode),
      ];

  group('DatasetSplitPlanner 正例', () {
    test('四族三平台池切分：配额满足、隔离成立、并集恰为池', () {
      final outcome = DatasetSplitPlanner.plan(poolManifest: pool(diversePool()), splitConfig: config());
      expect(outcome.isOk, isTrue, reason: outcome.errors.join('\n'));
      final plan = outcome.plan!;
      final all = <String>{
        for (final ids in plan.splits.values) ...ids,
      };
      expect(all, hasLength(12));
      for (final split in DatasetSplitPlanner.splitOrder) {
        expect(plan.splits[split]!, isNotEmpty);
      }
      for (final check in plan.quotaChecks) {
        expect(check['pass'], isTrue, reason: '$check');
      }
    });

    test('派生链与相同生成器身份归并为同一组件且不跨集合', () {
      final samples = diversePool()
        ..addAll([
          // base 与两个派生变体：链式连接。
          sample('s-meet-variant-a', contentKind: 'mixed', strokeCount: 20, chain: const ['s-meet-desktop']),
          sample('s-meet-variant-b', contentKind: 'mixed', strokeCount: 20, chain: const ['s-meet-variant-a']),
          // 相同生成器身份（name+seed+params 全等）但无显式链：也必须同组件。
          sample('s-meet-twin', seed: 123, paramsSha: 'f' * 64),
          sample('s-meet-twin-2', seed: 123, paramsSha: 'f' * 64),
        ]);
      final outcome = DatasetSplitPlanner.plan(poolManifest: pool(samples), splitConfig: config());
      expect(outcome.isOk, isTrue, reason: outcome.errors.join('\n'));
      final plan = outcome.plan!;
      String splitOf(String id) => plan.components.entries
          .firstWhere((e) => (e.value['members'] as List).contains(id))
          .value['split'] as String;
      expect(splitOf('s-meet-desktop'), splitOf('s-meet-variant-a'));
      expect(splitOf('s-meet-desktop'), splitOf('s-meet-variant-b'));
      expect(splitOf('s-meet-twin'), splitOf('s-meet-twin-2'));
      // 多成员组件计数：meat 派生链 1 个 + twin 1 个。
      final multi = plan.components.values.where((c) => (c['members'] as List).length > 1);
      expect(multi, hasLength(2));
    });

    test('同池同配置同种子产出完全相同的切分', () {
      final manifest = pool(diversePool());
      final a = DatasetSplitPlanner.plan(poolManifest: manifest, splitConfig: config());
      final b = DatasetSplitPlanner.plan(poolManifest: manifest, splitConfig: config());
      expect(a.plan!.splits, equals(b.plan!.splits));
      expect(a.plan!.components.keys, equals(b.plan!.components.keys));
    });
  });

  group('DatasetSplitPlanner 拒绝路径', () {
    test('配额不可满足时报 quota_not_met', () {
      final cfg = config(quotas: {
        'frozen_holdout': {'per_scene_family': 2, 'per_platform_profile': 3},
      });
      final outcome = DatasetSplitPlanner.plan(poolManifest: pool(diversePool()), splitConfig: cfg);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.where((e) => e.startsWith('quota_not_met')).length, greaterThan(0));
    });

    test('配置非法：权重未归一/未知轴/未知隔离规则', () {
      final manifest = pool(diversePool());
      final badWeights = config();
      (badWeights['weights'] as Map<String, Object?>)['development'] = 0.9;
      expect(DatasetSplitPlanner.plan(poolManifest: manifest, splitConfig: badWeights).errors,
          anyElement(startsWith('weights_not_normalized')));

      final badAxis = config();
      ((badAxis['min_quotas'] as Map<String, Object?>)['development'] as Map<String, Object?>)['per_color'] = 1;
      expect(DatasetSplitPlanner.plan(poolManifest: manifest, splitConfig: badAxis).errors,
          anyElement(startsWith('unknown_quota_axis:per_color')));

      final badRule = config();
      ((badRule['isolation'] as Map<String, Object?>)['rules'] as List).add('trust_me');
      expect(DatasetSplitPlanner.plan(poolManifest: manifest, splitConfig: badRule).errors,
          contains('unknown_isolation_rule:trust_me'));
    });

    test('组件跨分层轴时报 component_stratum_mixed', () {
      final samples = diversePool()
        ..add(sample('s-cross-variant', family: 'typed-report', chain: const ['s-meet-desktop']));
      final outcome = DatasetSplitPlanner.plan(poolManifest: pool(samples), splitConfig: config());
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.any((e) => e.startsWith('component_stratum_mixed')), isTrue);
    });
  });

  group('已落地切分产物复验（datasets/splits/**）', () {
    test('三个集合 manifest 均通过准入闸门且与池内容 hash 一致', () {
      final repoRoot = Directory.current.path;
      final poolRoot = '$repoRoot/../docs/研发记录/evidence/smart-layout-v3/datasets/synthetic-pool-v2';
      final splitsRoot =
          '$repoRoot/../docs/研发记录/evidence/smart-layout-v3/datasets/splits';
      DatasetFileResolver resolver(String base) => (path) {
            final file = File('$base/$path');
            return file.existsSync() ? file.readAsBytesSync() : null;
          };
      final poolOutcome = DatasetAdmissionValidator.validate(
        jsonDecode(File('$poolRoot/dataset-manifest.json').readAsStringSync(encoding: utf8))
            as Map<String, Object?>,
        resolveFile: resolver(poolRoot),
      );
      expect(poolOutcome.isOk, isTrue, reason: poolOutcome.errors.map((e) => '$e').join('\n'));

      final splitIds = <String>{};
      for (final split in DatasetSplitPlanner.splitOrder) {
        final manifest = jsonDecode(
          File('$splitsRoot/$split/manifest.json').readAsStringSync(encoding: utf8),
        ) as Map<String, Object?>;
        final outcome = DatasetAdmissionValidator.validate(manifest, resolveFile: resolver(poolRoot));
        expect(outcome.isOk, isTrue,
            reason: '$split: ${outcome.errors.map((e) => '$e').join('\n')}');
        expect((manifest['dataset'] as Map)['split'], split);
        for (final raw in manifest['samples'] as List) {
          final id = (raw as Map<String, Object?>)['sample_id'] as String;
          expect(splitIds.add(id), isTrue, reason: '样本跨集合重复：$id');
        }
      }
      expect(splitIds, hasLength(poolOutcome.samples.length));
    });
  });
}
