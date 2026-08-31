import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import '../src/deterministic_execution_environment.dart';
import '../src/fixture_manifest.dart';
import '../src/smart_layout_fixture_runner.dart';

/// V3-001A 契约测试：positive/negative manifest 解析与 runner 准入。
///
/// 静态 fixture（test/fixtures/*.json）覆盖纯契约解析；
/// 动态构造的 manifest 覆盖数据边界拒绝与产物哈希校验（临时目录，不触网）。
void main() {
  final fixturesDir = Directory('tool/smart_layout_v3/test/fixtures');

  Map<String, Object?> loadStatic(String name) =>
      jsonDecode(File('${fixturesDir.path}${Platform.pathSeparator}$name').readAsStringSync())
          as Map<String, Object?>;

  Map<String, Object?> deepCopy(Map<String, Object?> source) =>
      jsonDecode(jsonEncode(source)) as Map<String, Object?>;

  group('positive manifest 解析', () {
    test('合成 manifest 全字段解析通过', () {
      final outcome = FixtureManifest.parse(loadStatic('positive_synthetic.json'));
      expect(outcome.isOk, isTrue, reason: outcome.errors.map((e) => e.toString()).join('\n'));
      final manifest = outcome.manifest!;
      expect(manifest.schemaVersion, '1.0.0');
      expect(manifest.split, 'synthetic');
      expect(manifest.dataBoundary.origin, 'synthetic');
      expect(manifest.fixtures, hasLength(1));
      final fixture = manifest.fixtures.single;
      expect(fixture.id, 'synthetic-mixed-page');
      expect(fixture.features?.contentKind, 'mixed');
      expect(fixture.environment.platform, 'windows');
      expect(fixture.environment.networkMode, 'offline_replay');
      expect(fixture.expected.relations.single.type, 'caption_of');
      expect(fixture.recordedResponses.single.contentOrigin, 'synthetic');
    });

    test('授权真实样本 manifest（授权/脱敏/删除/隔离键齐全）解析通过', () {
      final outcome = FixtureManifest.parse(loadStatic('positive_authorized_real.json'));
      expect(outcome.isOk, isTrue, reason: outcome.errors.map((e) => e.toString()).join('\n'));
      final manifest = outcome.manifest!;
      expect(manifest.dataBoundary.origin, 'authorized_real');
      expect(manifest.dataBoundary.consent?.status, 'granted');
      expect(manifest.dataBoundary.anonymization?.status, 'applied');
      expect(manifest.dataBoundary.deletion?.policyId, 'policy-2026-08');
      expect(manifest.fixtures.single.expected.failureCodes, ['M-LAYOUT-OVERLAP']);
    });
  });

  group('negative manifest 拒绝（契约层）', () {
    test('schema_version 不匹配', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      json['schema_version'] = '0.9.9';
      final outcome = FixtureManifest.parse(json);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.map((e) => e.code), contains('schema_version_mismatch'));
    });

    test('未知期望关系类型被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      (fixture[0] as Map<String, Object?>)['expected'] = {
        ...(fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>,
        'relations': [
          {'type': 'above_below', 'from': ['a'], 'to': ['b'], 'confidence': 0.5}
        ],
      };
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('unknown_relation_type'));
    });

    test('sha256 格式非法被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      (fixture[0] as Map<String, Object?>)['scene'] = {
        'path': 'artifacts/scene.json',
        'sha256': 'not-a-hash',
      };
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('invalid_sha256'));
    });

    test('时钟未固定被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      final env = (fixture[0] as Map<String, Object?>)['environment'] as Map<String, Object?>;
      env['clock'] = {'mode': 'wall', 'fixed_at_utc': '2026-08-31T00:00:00Z'};
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('clock_not_fixed'));
    });

    test('字体集合为空被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      ((fixture[0] as Map<String, Object?>)['environment'] as Map<String, Object?>)['fonts'] = <Object?>[];
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('fonts_empty'));
    });

    test('fixture id 重复被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixtures = json['fixtures'] as List<Object?>;
      fixtures.add(deepCopy(fixtures[0] as Map<String, Object?>));
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('duplicate_fixture_id'));
    });

    test('引用不存在的来源组被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      (fixture[0] as Map<String, Object?>)['source_group_id'] = 'ghost-group';
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('unknown_source_group'));
    });

    test('content_origin 枚举强校验：大小写伪装/缺失均被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      final responses = ((fixture[0] as Map<String, Object?>)['recorded_responses'] as List<Object?>)
          .cast<Map<String, Object?>>();
      responses[0]['content_origin'] = 'AUTHORIZED_REAL';
      var outcome = FixtureManifest.parse(json);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.map((e) => e.code), contains('field_invalid_value'));

      final json2 = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture2 = json2['fixtures'] as List<Object?>;
      final responses2 = ((fixture2[0] as Map<String, Object?>)['recorded_responses'] as List<Object?>)
          .cast<Map<String, Object?>>();
      responses2[0].remove('content_origin');
      outcome = FixtureManifest.parse(json2);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.map((e) => e.pointer), contains('#/fixtures/0/recorded_responses/0/content_origin'));
    });

    test('taxonomy 路径锁定：自造路径被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final meta = json['manifest'] as Map<String, Object?>;
      meta['failure_taxonomy_reference'] = {'path': 'specs/my-own-taxonomy.json', 'sha256': 'a' * 64};
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('taxonomy_path_invalid'));
    });

    test('畸形 relations 产生机器错误而非崩溃', () {
      for (final mutation in [
        {'type': 'caption_of', 'from': 'text-1', 'to': ['image-1'], 'confidence': 0.9},
        {'type': 'caption_of', 'from': [123], 'to': ['image-1'], 'confidence': 0.9},
        {'type': 'caption_of', 'from': [], 'to': ['image-1'], 'confidence': 0.9},
      ]) {
        final json = deepCopy(loadStatic('positive_synthetic.json'));
        final fixture = json['fixtures'] as List<Object?>;
        (fixture[0] as Map<String, Object?>)['expected'] = {
          ...(fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>,
          'relations': [mutation],
        };
        final outcome = FixtureManifest.parse(json);
        expect(outcome.isOk, isFalse, reason: '应拒绝畸形关系 $mutation');
        expect(outcome.errors.map((e) => e.code), contains('invalid_string_list'));
      }
    });

    test('数值界与枚举：dpr=0/负种子/非法平台/越界 confidence/空 reading_order/非法 anonymization 均拒绝', () {
      Map<String, Object?> withEnvironment(void Function(Map<String, Object?> env) mutate) {
        final json = deepCopy(loadStatic('positive_synthetic.json'));
        final fixture = json['fixtures'] as List<Object?>;
        final env = (fixture[0] as Map<String, Object?>)['environment'] as Map<String, Object?>;
        mutate(env);
        return json;
      }

      expect(FixtureManifest.parse(withEnvironment((env) => env['dpr'] = 0)).errors.map((e) => e.code),
          contains('invalid_dpr'));
      expect(FixtureManifest.parse(withEnvironment((env) => env['random_seed'] = -1)).errors.map((e) => e.code),
          contains('invalid_random_seed'));
      expect(FixtureManifest.parse(withEnvironment((env) => env['platform'] = 'linux')).errors.map((e) => e.code),
          contains('field_invalid_value'));
      expect(FixtureManifest.parse(withEnvironment((env) => env['dpr'] = 2)).isOk, isTrue,
          reason: '整数 dpr 是合法 number');

      final badConfidence = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = badConfidence['fixtures'] as List<Object?>;
      ((fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>)['relations'] = [
        {'type': 'caption_of', 'from': ['a'], 'to': ['b'], 'confidence': 7}
      ];
      expect(FixtureManifest.parse(badConfidence).errors.map((e) => e.code), contains('invalid_confidence'));

      final badOrder = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture2 = badOrder['fixtures'] as List<Object?>;
      ((fixture2[0] as Map<String, Object?>)['expected'] as Map<String, Object?>)['reading_order'] = <Object?>[];
      expect(FixtureManifest.parse(badOrder).errors.map((e) => e.code), contains('invalid_reading_order'));

      final badAnon = deepCopy(loadStatic('positive_authorized_real.json'));
      (((badAnon['data_boundary'] as Map<String, Object?>)['anonymization'] as Map<String, Object?>))['status'] =
          'maybe';
      expect(FixtureManifest.parse(badAnon).errors.map((e) => e.code), contains('field_invalid_value'));
    });

    test('model_reference 可选字段解析往返', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final meta = json['manifest'] as Map<String, Object?>;
      meta['model_reference'] = {'name': 'test-model', 'version': '0.1.0', 'hash': 'b' * 64};
      final outcome = FixtureManifest.parse(json);
      expect(outcome.isOk, isTrue);
      expect(outcome.manifest!.modelReference?.name, 'test-model');
      expect(outcome.manifest!.modelReference?.hash, 'b' * 64);
    });

    test('数组字段给出但非数组被拒绝（field_not_array）', () {
      void check(void Function(Map<String, Object?> json) mutate) {
        final json = deepCopy(loadStatic('positive_synthetic.json'));
        mutate(json);
        final outcome = FixtureManifest.parse(json);
        expect(outcome.isOk, isFalse, reason: '非数组字段必须被拒绝');
        expect(outcome.errors.map((e) => e.code), contains('field_not_array'));
      }

      check((json) {
        final fixture = json['fixtures'] as List<Object?>;
        ((fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>)['relations'] = 'not-a-list';
      });
      check((json) {
        final fixture = json['fixtures'] as List<Object?>;
        ((fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>)['reading_order'] = 'a,b';
      });
      check((json) {
        final fixture = json['fixtures'] as List<Object?>;
        (fixture[0] as Map<String, Object?>)['recorded_responses'] = 'not-a-list';
      });
      check((json) {
        final fixture = json['fixtures'] as List<Object?>;
        ((fixture[0] as Map<String, Object?>)['expected'] as Map<String, Object?>)['failure_codes'] =
            'M-LAYOUT-OVERLAP';
      });
    });

    test('来源组缺少 user_isolation_key_hash 字段（即使 synthetic）被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final groups =
          ((json['data_boundary'] as Map<String, Object?>)['source_groups'] as List<Object?>).cast<Map<String, Object?>>();
      groups[0].remove('user_isolation_key_hash');
      final outcome = FixtureManifest.parse(json);
      expect(outcome.isOk, isFalse);
      expect(outcome.errors.map((e) => e.code), contains('field_missing'));
      expect(outcome.errors.map((e) => e.pointer),
          contains('#/data_boundary/source_groups/0/user_isolation_key_hash'));
    });

    test('未知字段被拒绝（additionalProperties 对齐）', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      (json['manifest'] as Map<String, Object?>)['extra_field'] = 'x';
      var outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('unknown_field'));

      final json2 = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json2['fixtures'] as List<Object?>;
      (fixture[0] as Map<String, Object?>)['surprise'] = 1;
      outcome = FixtureManifest.parse(json2);
      expect(outcome.errors.map((e) => e.code), contains('unknown_field'));
    });

    test('合成 manifest 携带真实录制被拒绝', () {
      final json = deepCopy(loadStatic('positive_synthetic.json'));
      final fixture = json['fixtures'] as List<Object?>;
      final responses = ((fixture[0] as Map<String, Object?>)['recorded_responses'] as List<Object?>)
          .cast<Map<String, Object?>>();
      responses[0]['content_origin'] = 'authorized_real';
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('real_recording_requires_authorized_origin'));
    });
  });

  group('数据边界：缺少元数据的真实样本无法进入 runner', () {
    Map<String, Object?> authorizedBase() => deepCopy(loadStatic('positive_authorized_real.json'));

    test('缺少授权（consent）元数据被拒绝', () {
      final json = authorizedBase();
      (json['data_boundary'] as Map<String, Object?>).remove('consent');
      final outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.code), contains('data_boundary_missing_consent'));
      expect(const SmartLayoutFixtureRunner().admitJson(json).admitted, isFalse);
    });

    test('缺少脱敏（anonymization）元数据被拒绝', () {
      final json = authorizedBase();
      (json['data_boundary'] as Map<String, Object?>).remove('anonymization');
      expect(FixtureManifest.parse(json).errors.map((e) => e.code),
          contains('data_boundary_missing_anonymization'));
    });

    test('缺少删除（deletion）策略被拒绝', () {
      final json = authorizedBase();
      (json['data_boundary'] as Map<String, Object?>).remove('deletion');
      expect(
          FixtureManifest.parse(json).errors.map((e) => e.code), contains('data_boundary_missing_deletion'));
    });

    test('缺少用户隔离键被拒绝（manifest 级与来源组级）', () {
      final json = authorizedBase();
      (json['data_boundary'] as Map<String, Object?>).remove('user_isolation_key_hash');
      var outcome = FixtureManifest.parse(json);
      expect(outcome.errors.map((e) => e.pointer), contains('#/data_boundary/user_isolation_key_hash'));
      final json2 = authorizedBase();
      final groups = ((json2['data_boundary'] as Map<String, Object?>)['source_groups'] as List<Object?>)
          .cast<Map<String, Object?>>();
      groups[0]['user_isolation_key_hash'] = null;
      outcome = FixtureManifest.parse(json2);
      expect(outcome.errors.map((e) => e.code), contains('source_group_missing_isolation_key'));
    });

    test('consent.status=not_required 的真实样本被拒绝', () {
      final json = authorizedBase();
      final boundary = json['data_boundary'] as Map<String, Object?>;
      (boundary['consent'] as Map<String, Object?>)['status'] = 'not_required';
      expect(FixtureManifest.parse(json).errors.map((e) => e.code), contains('consent_not_granted'));
    });
  });

  group('runner 准入（产物与 taxonomy 校验）', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('smart_layout_v3_001a_');
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    String writeArtifact(String relativePath, List<int> bytes) {
      final file = File('${tempRoot.path}${Platform.pathSeparator}'
          '${relativePath.replaceAll('/', Platform.pathSeparator)}');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return crypto.sha256.convert(bytes).toString();
    }

    Map<String, Object?> buildAdmissibleManifest() {
      final sceneSha = writeArtifact('artifacts/scene.json', utf8.encode('{"elements":[]}'));
      final goldenSha = writeArtifact('artifacts/golden.png', [1, 2, 3, 4]);
      writeArtifact('replay/vlm_overview.json', utf8.encode('{"synthetic":true}'));
      return <String, Object?>{
        'schema_version': '1.0.0',
        'manifest_kind': 'smart-layout-v3-fixture-manifest',
        'manifest': <String, Object?>{
          'name': 'tmp',
          'version': '1.0.0',
          'generated_at_utc': '2026-08-31T00:00:00Z',
          'generator': 'test',
          'split': 'synthetic',
        },
        'data_boundary': <String, Object?>{
          'origin': 'synthetic',
          'source_groups': <Object?>[
            <String, Object?>{'id': 'g1', 'origin': 'synthetic', 'user_isolation_key_hash': null, 'sample_count': 1}
          ],
          'forbidden_uses': <Object?>['禁止回流训练'],
        },
        'fixtures': <Object?>[
          <String, Object?>{
            'id': 'f1',
            'source_group_id': 'g1',
            'features': {'content_kind': 'mixed', 'stroke_count': 5},
            'scene': {'path': 'artifacts/scene.json', 'sha256': sceneSha},
            'environment': <String, Object?>{
              'dpr': 2.0,
              'locale': 'zh-CN',
              'timezone': 'Asia/Shanghai',
              'clock': <String, Object?>{'mode': 'fixed', 'fixed_at_utc': '2026-08-31T00:00:00Z'},
              'random_seed': 1,
              'fonts': <Object?>[
                <String, Object?>{'family': 'Roboto', 'file': 'fonts/Roboto.ttf', 'sha256': 'a' * 64}
              ],
              'platform': 'windows',
              'network_mode': 'offline_replay',
            },
            'element_integrity': <String, Object?>{'element_ids_sha256': 'b' * 64, 'version_nonce_seed': 3},
            'recorded_responses': <Object?>[
              <String, Object?>{
                'name': 'vlm-overview',
                'kind': 'vlm_overview',
                'content_origin': 'synthetic',
                'path': 'replay/vlm_overview.json',
                'sha256': 'c' * 64,
              }
            ],
            'expected': <String, Object?>{
              'coverage': <String, Object?>{'min_source_recall': 1.0},
              'renderer_golden': <String, Object?>{'path': 'artifacts/golden.png', 'sha256': goldenSha},
              'failure_codes': <Object?>[],
            },
          }
        ],
      };
    }

    test('产物存在且哈希一致时准入', () {
      final runner = SmartLayoutFixtureRunner(repoRoot: tempRoot.path);
      final admission = runner.admitJson(buildAdmissibleManifest());
      expect(admission.admitted, isTrue, reason: admission.errors.map((e) => e.toString()).join('\n'));
    });

    test('产物哈希不匹配拒绝进入 runner', () {
      final json = buildAdmissibleManifest();
      writeArtifact('artifacts/scene.json', utf8.encode('{"elements":["tampered"]}'));
      final admission = SmartLayoutFixtureRunner(repoRoot: tempRoot.path).admitJson(json);
      expect(admission.admitted, isFalse);
      expect(admission.errors.map((e) => e.code), contains('artifact_hash_mismatch'));
    });

    test('产物文件缺失拒绝进入 runner', () {
      final json = buildAdmissibleManifest();
      final admission = SmartLayoutFixtureRunner(repoRoot: tempRoot.path).admitJson(json);
      expect(admission.admitted, isTrue);
      File('${tempRoot.path}${Platform.pathSeparator}artifacts${Platform.pathSeparator}golden.png')
          .deleteSync();
      final second = SmartLayoutFixtureRunner(repoRoot: tempRoot.path).admitJson(json);
      expect(second.admitted, isFalse);
      expect(second.errors.map((e) => e.code), contains('artifact_file_missing'));
    });

    test('失败码不在 taxonomy 中拒绝；taxonomy 哈希不符拒绝', () {
      final taxonomyBytes = utf8.encode(jsonEncode({
        'failure_codes': {'M-LAYOUT-OVERLAP': {'severity': 'major'}}
      }));
      final taxonomySha = writeArtifact('docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json', taxonomyBytes);

      Map<String, Object?> manifestWithCode(String code) {
        final json = buildAdmissibleManifest();
        final meta = json['manifest'] as Map<String, Object?>;
        meta['failure_taxonomy_reference'] = {
          'path': 'docs/研发记录/specs/smart-layout-v3/failure-taxonomy.json',
          'sha256': taxonomySha,
        };
        final fixture = (json['fixtures'] as List<Object?>).cast<Map<String, Object?>>()[0];
        (fixture['expected'] as Map<String, Object?>)['failure_codes'] = [code];
        return json;
      }

      final runner = SmartLayoutFixtureRunner(repoRoot: tempRoot.path);
      expect(runner.admitJson(manifestWithCode('M-LAYOUT-OVERLAP')).admitted, isTrue);
      final unknown = runner.admitJson(manifestWithCode('M-NOT-A-CODE'));
      expect(unknown.admitted, isFalse);
      expect(unknown.errors.map((e) => e.code), contains('unknown_failure_code'));

      final staleHash = manifestWithCode('M-LAYOUT-OVERLAP');
      final meta = staleHash['manifest'] as Map<String, Object?>;
      (meta['failure_taxonomy_reference'] as Map<String, Object?>)['sha256'] = 'd' * 64;
      final stale = runner.admitJson(staleHash);
      expect(stale.admitted, isFalse);
      expect(stale.errors.map((e) => e.code), contains('taxonomy_hash_mismatch'));
    });

    test('缺少数据边界元数据的真实样本在有产物校验时仍被拒绝', () {
      final json = buildAdmissibleManifest();
      final boundary = json['data_boundary'] as Map<String, Object?>;
      boundary['origin'] = 'authorized_real';
      // 产物齐全，但真实样本没有 consent/anonymization/deletion/隔离键。
      final admission = SmartLayoutFixtureRunner(repoRoot: tempRoot.path).admitJson(json);
      expect(admission.admitted, isFalse);
      expect(admission.errors.map((e) => e.code), containsAll(
          ['data_boundary_missing_consent', 'data_boundary_missing_anonymization', 'data_boundary_missing_deletion']));
    });
  });

  group('DeterministicExecutionEnvironment', () {
    test('fromJson/toJson 往返一致，equality 按规范化字段', () {
      final json = {
        'dpr': 2.0,
        'locale': 'zh-CN',
        'timezone': 'Asia/Shanghai',
        'clock': {'mode': 'fixed', 'fixed_at_utc': '2026-08-31T00:00:00Z'},
        'random_seed': 20260831,
        'fonts': [
          {'family': 'Roboto', 'file': 'fonts/Roboto-Regular.ttf', 'sha256': '2' * 64}
        ],
        'platform': 'windows',
        'network_mode': 'offline_replay',
      };
      final env = DeterministicExecutionEnvironment.fromJson(json);
      expect(DeterministicExecutionEnvironment.fromJson(env.toJson()), env);
      expect(env.identityFields, hasLength(8));
      expect(env.fixedClockUtc, '2026-08-31T00:00:00Z');
    });
  });
}
