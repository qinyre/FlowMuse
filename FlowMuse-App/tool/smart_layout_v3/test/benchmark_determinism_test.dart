import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import '../src/benchmark_spec.dart';
import '../src/canonical_artifacts.dart';
import '../src/determinism_harness.dart';
import '../src/deterministic_execution_environment.dart';
import '../src/fixture_manifest.dart';

/// V3-001B 确定性与 benchmark 环境测试。
void main() {
  group('CanonicalArtifacts.canonicalJson', () {
    test('键序无关、易变键剥离、数字规范化', () {
      final a = {
        'b': {'y': 1, 'x': 2},
        'a': [3, 1.0, 2.5, true, null, '中'],
        'generated_at_utc': '2026-08-31T00:00:00Z',
      };
      final b = {
        'a': [3, 1, 2.5, true, null, '中'],
        'b': {'x': 2, 'y': 1},
        'updated_at_utc': '2099-01-01T00:00:00Z',
      };
      expect(CanonicalArtifacts.canonicalJsonSha256(a), CanonicalArtifacts.canonicalJsonSha256(b));
      final volatileKept = CanonicalArtifacts.canonicalJsonSha256(a, stripVolatile: false);
      expect(volatileKept, isNot(CanonicalArtifacts.canonicalJsonSha256(a)));
      expect(CanonicalArtifacts.canonicalJson(a), contains('[3,1,2.5,'));
      expect(CanonicalArtifacts.canonicalJson(a), isNot(contains('1.0')));
    });

    test('内容变化必然改变哈希', () {
      final a = {'x': 1};
      final b = {'x': 2};
      expect(CanonicalArtifacts.canonicalJsonSha256(a), isNot(CanonicalArtifacts.canonicalJsonSha256(b)));
    });
  });

  group('CanonicalArtifacts.canonicalPng', () {
    List<int> chunk(String type, List<int> data) {
      final out = <int>[];
      void u32(int v) => out..add((v >> 24) & 0xff)..add((v >> 16) & 0xff)..add((v >> 8) & 0xff)..add(v & 0xff);
      u32(data.length);
      out.addAll(type.codeUnits);
      out.addAll(data);
      int crc = 0xffffffff;
      final table = List<int>.generate(256, (n) {
        var c = n;
        for (var k = 0; k < 8; k++) {
          c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
        }
        return c;
      });
      for (final byte in [...type.codeUnits, ...data]) {
        crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8);
      }
      u32((crc ^ 0xffffffff) & 0xffffffff);
      return out;
    }

    List<int> png({required int pixel, bool withAncillary = false}) {
      List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
      final ihdr = [...u32(1), ...u32(1), 8, 0, 0, 0, 0];
      return [
        ...CanonicalArtifactsPngSignature.bytes,
        ...chunk('IHDR', ihdr),
        if (withAncillary) ...chunk('tEXt', utf8.encode('Comment\x00made-by')),
        if (withAncillary) ...chunk('tIME', [7, 230, 8, 31, 12, 0, 0]),
        ...chunk('IDAT', [pixel, pixel, pixel]),
        ...chunk('IEND', const []),
      ];
    }

    test('辅助 chunk 与像素字节不影响/影响哈希的边界', () {
      final plain = png(pixel: 1);
      final withMeta = png(pixel: 1, withAncillary: true);
      // 元数据 chunk 被剥离：两种编码同哈希。
      expect(CanonicalArtifacts.canonicalPngSha256(plain),
          CanonicalArtifacts.canonicalPngSha256(withMeta));
      // 像素不同则哈希不同。
      expect(CanonicalArtifacts.canonicalPngSha256(plain),
          isNot(CanonicalArtifacts.canonicalPngSha256(png(pixel: 2))));
    });

    test('非 PNG / 截断 PNG 抛 FormatException', () {
      expect(() => CanonicalArtifacts.canonicalPng([1, 2, 3]), throwsFormatException);
      expect(() => CanonicalArtifacts.canonicalPng([...CanonicalArtifactsPngSignature.bytes, 0, 0, 0, 5]),
          throwsFormatException);
    });
  });

  group('固定时钟与种子随机源', () {
    test('同环境同时钟推进状态一致；tick 计数与超时判定不依赖墙钟', () {
      final env = _testEnvironment(seed: 42);
      final clockA = DeterministicClock(environment: env);
      final clockB = DeterministicClock(environment: env);
      for (var i = 0; i < 5; i++) {
        clockA.tick();
        clockB.tick();
      }
      expect(clockA.ticks, clockB.ticks);
      expect(clockA.fixedAtUtc, env.fixedClockUtc);
      expect(clockA.timedOut(4), isTrue);
      expect(clockB.timedOut(10), isFalse);
    });

    test('同种子序列指纹一致；异种子不同', () {
      final a = SeededRandom(seed: 7).sequenceFingerprint();
      final b = SeededRandom(seed: 7).sequenceFingerprint();
      final c = SeededRandom(seed: 8).sequenceFingerprint();
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('BenchmarkSpec', () {
    test('仓库冻结 spec 解析且内容哈希与文件声明一致', () {
      final path =
          'tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
      expect(BenchmarkSpec.verifyFileHash(path), isEmpty,
          reason: 'benchmark-spec.json 必须携带与内容一致的 content_sha256');
      final spec = BenchmarkSpec.load(jsonDecode(File(path).readAsStringSync())).spec!;
      expect(spec.syntheticOnly, isTrue, reason: 'V3-002A 前 data_policy 必须是 synthetic_only');
      expect(spec.repetitions, greaterThanOrEqualTo(3));
      expect(spec.concurrency, 1);
      expect(spec.percentileMethod, 'nearest_rank');
      expect(spec.peakMemoryMetric, 'process_peak_rss');
    });

    test('字段篡改后内容哈希变化；非法字段被拒绝', () async {
      final dir = await Directory.systemTemp.createTemp('smart_layout_v3_spec_');
      final path = '${dir.path}${Platform.pathSeparator}spec.json';
      final original = jsonDecode(File(
              'tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json')
          .readAsStringSync()) as Map<String, Object?>;
      File(path).writeAsStringSync(jsonEncode(original));
      expect(BenchmarkSpec.verifyFileHash(path), isEmpty);

      final tampered = Map<String, Object?>.from(original)..['timeout_seconds'] = 1;
      File(path).writeAsStringSync(jsonEncode(tampered));
      expect(BenchmarkSpec.verifyFileHash(path), isNotEmpty, reason: '任何字段变化都必须改 hash');

      final invalid = Map<String, Object?>.from(original)..['concurrency'] = 4;
      expect(BenchmarkSpec.load(invalid).errors, isNotEmpty);
      final badPolicy = Map<String, Object?>.from(original)..['data_policy'] = 'anything_goes';
      expect(BenchmarkSpec.load(badPolicy).errors, isNotEmpty);
      dir.deleteSync(recursive: true);
    });
  });

  group('DeterminismHarness', () {
    late Directory tempRoot;
    late Map<String, Object?> manifestJson;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('smart_layout_v3_001b_');
      manifestJson = _buildAdmissibleManifest(tempRoot);
    });

    tearDown(() {
      tempRoot.deleteSync(recursive: true);
    });

    test('字体哈希核对：缺失/不匹配即冻结失败；一致则环境身份哈希稳定', () {
      final manifest = _parseOrFail(manifestJson);
      final harness = DeterminismHarness(repoRoot: tempRoot.path);
      final fixture = manifest.fixtures.single;

      final okFreeze = harness.freezeEnvironment(fixture);
      expect(okFreeze.ok, isTrue, reason: okFreeze.errors.join('; '));
      final again = harness.freezeEnvironment(fixture);
      expect(again.identityHash, okFreeze.identityHash);

      // 篡改字体文件 → 哈希不匹配。
      _writeFile(tempRoot, 'fonts/Roboto.ttf', utf8.encode('tampered'));
      final bad = harness.freezeEnvironment(fixture);
      expect(bad.ok, isFalse);
      expect(bad.errors.join(), contains('字体哈希不匹配'));
    });

    test('合成数据政策：synthetic_only 下真实录制被拒', () {
      final spec = _repoSpec();
      final harness = DeterminismHarness(repoRoot: tempRoot.path);
      final manifest = _parseOrFail(manifestJson);
      expect(harness.checkDataPolicy(manifest, spec), isEmpty);

      // 001A 层已拦 synthetic manifest 携带真实录制；政策的独立拦截面是
      // 边界完整、可解析的 authorized_real manifest（V3-002A 前仍只许合成）。
      final authorized = _authorizedRealManifest(tempRoot);
      final authorizedManifest = _parseOrFail(authorized);
      expect(harness.checkDataPolicy(authorizedManifest, spec), isNotEmpty,
          reason: 'synthetic_only 政策必须拒绝 authorized_real 录制');
      expect(harness.checkDataPolicy(authorizedManifest, spec).join(), contains('synthetic_only'));

      final governed = _repoSpecWithPolicy('governed_real');
      expect(harness.checkDataPolicy(authorizedManifest, governed), isEmpty);
    });

    test('runOnce 报告跨调用一致（进程内两次）', () {
      final spec = _repoSpec();
      final manifest = _parseOrFail(manifestJson);
      final harness = DeterminismHarness(repoRoot: tempRoot.path);
      final r1 = harness.runOnce(manifest.fixtures.single, spec);
      final r2 = harness.runOnce(manifest.fixtures.single, spec);
      expect(r1.ok, isTrue, reason: r1.errors.join('; '));
      expect(r1.consistencyHash, r2.consistencyHash);
    });
  });

  group('隔离子进程三次运行一致（V3-001B 验收）', () {
    test('determinism CLI 三次隔离子进程一致性哈希相等且 exit 0', () {
      final tempRoot = Directory.systemTemp.createTempSync('smart_layout_v3_001b_iso_');
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final manifestJson = _buildAdmissibleManifest(tempRoot);
      final manifestPath = '${tempRoot.path}${Platform.pathSeparator}manifest.json';
      File(manifestPath).writeAsStringSync(jsonEncode(manifestJson));

      final dart = _findDart();
      final appRoot = Directory.current.path;
      final result = Process.runSync(dart, [
        'run',
        'tool/smart_layout_v3/main.dart',
        'determinism',
        '--manifest', manifestPath,
        '--repo-root', tempRoot.path,
        '--runs', '3',
      ], workingDirectory: appRoot);
      final stdoutText = (result.stdout as String).trim();
      final jsonStart = stdoutText.indexOf('{');
      expect(jsonStart, greaterThanOrEqualTo(0), reason: result.stderr.toString());
      final payload = jsonDecode(stdoutText.substring(jsonStart)) as Map<String, Object?>;
      expect(payload['ok'], isTrue, reason: payload.toString());
      expect(payload['isolated_processes'], isTrue);
      expect(payload['consistent'], isTrue);
      expect((payload['consistency_by_run'] as List).length, 3);
    }, timeout: const Timeout(Duration(minutes: 4)));
  });
}

String _findDart() {
  final suffix = Platform.isWindows ? '.exe' : '';
  final resolved = Platform.resolvedExecutable;
  if (resolved.toLowerCase().endsWith('dart$suffix')) return resolved;
  final env = Platform.environment['SMART_LAYOUT_V3_DART'];
  if (env != null && env.isNotEmpty) return env;
  // flutter_test 环境下 resolvedExecutable 是 flutter_tester（位于
  // <flutter>/bin/cache/artifacts/...）；沿祖先目录找 dart-sdk 的 dart.exe。
  Directory? dir = File(resolved).parent;
  for (var i = 0; i < 8 && dir != null; i++) {
    final candidate = File(
        '${dir.path}${Platform.pathSeparator}bin${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin${Platform.pathSeparator}dart$suffix');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  const candidates = ['dart', 'dart.exe'];
  for (final candidate in candidates) {
    try {
      if (Process.runSync(candidate, ['--version']).exitCode == 0) return candidate;
    } on ProcessException {
      // 尝试下一候选。
    }
  }
  throw StateError('找不到 dart VM：请设置 SMART_LAYOUT_V3_DART 或把 dart 加入 PATH');
}

BenchmarkSpec _repoSpec() {
  final path =
      'tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
  return BenchmarkSpec.load(jsonDecode(File(path).readAsStringSync())).spec!;
}

BenchmarkSpec _repoSpecWithPolicy(String policy) {
  final path =
      'tool${Platform.pathSeparator}smart_layout_v3${Platform.pathSeparator}benchmark${Platform.pathSeparator}benchmark-spec.json';
  final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
  return BenchmarkSpec.load({...raw, 'data_policy': policy}).spec!;
}

Map<String, Object?> _authorizedRealManifest(Directory root) {
  final base = _buildAdmissibleManifest(root);
  final boundary = base['data_boundary'] as Map<String, Object?>;
  boundary['origin'] = 'authorized_real';
  boundary['consent'] = <String, Object?>{
    'status': 'granted',
    'granted_at_utc': '2026-08-30T00:00:00Z',
    'scope': '评测',
    'reference': 'ticket-1',
  };
  boundary['anonymization'] = <String, Object?>{'status': 'applied', 'method': 'x'};
  boundary['deletion'] = <String, Object?>{
    'policy_id': 'p1',
    'retention_until_utc': null,
    'verified_at_utc': '2026-08-30T00:00:00Z',
    'reference': 'log-1',
  };
  boundary['user_isolation_key_hash'] = 'd' * 64;
  final groups = (boundary['source_groups'] as List<Object?>).cast<Map<String, Object?>>();
  groups[0]['origin'] = 'authorized_real';
  groups[0]['user_isolation_key_hash'] = 'd' * 64;
  final fixture = (base['fixtures'] as List<Object?>).cast<Map<String, Object?>>()[0];
  (fixture['recorded_responses'] as List<Object?>).cast<Map<String, Object?>>()[0]['content_origin'] =
      'authorized_real';
  return base;
}

void _writeFile(Directory root, String relativePath, List<int> bytes) {
  final file = File('${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

Map<String, Object?> _buildAdmissibleManifest(Directory root) {
  final sceneBytes = utf8.encode('{"z":1,"a":{"b":[1,2.0]}}');
  final sceneSha = crypto.sha256.convert(sceneBytes).toString();
  final goldenBytes = _minimalPng();
  final goldenSha = crypto.sha256.convert(goldenBytes).toString();
  final fontBytes = utf8.encode('fake-regular');
  final fontSha = crypto.sha256.convert(fontBytes).toString();
  _writeFile(root, 'artifacts/scene.json', sceneBytes);
  _writeFile(root, 'artifacts/golden.png', goldenBytes);
  _writeFile(root, 'fonts/Roboto.ttf', fontBytes);
  _writeFile(root, 'replay/vlm_overview.json', utf8.encode('{"synthetic":true}'));
  return <String, Object?>{
    'schema_version': '1.0.0',
    'manifest_kind': 'smart-layout-v3-fixture-manifest',
    'manifest': <String, Object?>{
      'name': 'determinism-check',
      'version': '1.0.0',
      'generated_at_utc': '2026-08-31T00:00:00Z',
      'generator': 'test',
      'split': 'synthetic',
    },
    'data_boundary': <String, Object?>{
      'origin': 'synthetic',
      'source_groups': <Object?>[
        <String, Object?>{
          'id': 'g1',
          'origin': 'synthetic',
          'user_isolation_key_hash': null,
          'sample_count': 1,
        }
      ],
      'forbidden_uses': <Object?>['禁止回流训练'],
    },
    'fixtures': <Object?>[
      <String, Object?>{
        'id': 'f-det',
        'source_group_id': 'g1',
        'features': <String, Object?>{'content_kind': 'mixed', 'stroke_count': 3},
        'scene': <String, Object?>{'path': 'artifacts/scene.json', 'sha256': sceneSha},
        'environment': <String, Object?>{
          'dpr': 2.0,
          'locale': 'zh-CN',
          'timezone': 'Asia/Shanghai',
          'clock': <String, Object?>{'mode': 'fixed', 'fixed_at_utc': '2026-08-31T00:00:00Z'},
          'random_seed': 20260831,
          'fonts': <Object?>[
            <String, Object?>{'family': 'Roboto', 'file': 'fonts/Roboto.ttf', 'sha256': fontSha}
          ],
          'platform': 'windows',
          'network_mode': 'offline_replay',
        },
        'element_integrity': <String, Object?>{
          'element_ids_sha256': 'b' * 64,
          'version_nonce_seed': 5,
        },
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

FixtureManifest _parseOrFail(Map<String, Object?> json) {
  final outcome = FixtureManifest.parse(json);
  if (!outcome.isOk) {
    fail('manifest 解析失败：${outcome.errors.join('; ')}');
  }
  return outcome.manifest!;
}

DeterministicExecutionEnvironment _testEnvironment({required int seed}) {
  return DeterministicExecutionEnvironment.fromJson(<String, Object?>{
    'dpr': 2.0,
    'locale': 'zh-CN',
    'timezone': 'Asia/Shanghai',
    'clock': <String, Object?>{'mode': 'fixed', 'fixed_at_utc': '2026-08-31T00:00:00Z'},
    'random_seed': seed,
    'fonts': <Object?>[
      <String, Object?>{'family': 'Roboto', 'file': 'fonts/Roboto.ttf', 'sha256': 'a' * 64}
    ],
    'platform': 'windows',
    'network_mode': 'offline_replay',
  });
}

List<int> _minimalPng() {
  List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
  List<int> chunk(String type, List<int> data) {
    int crc = 0xffffffff;
    final table = List<int>.generate(256, (n) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      return c;
    });
    for (final byte in [...type.codeUnits, ...data]) {
      crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8);
    }
    return [...u32(data.length), ...type.codeUnits, ...data, ...u32((crc ^ 0xffffffff) & 0xffffffff)];
  }

  final ihdr = [...u32(1), ...u32(1), 8, 0, 0, 0, 0];
  return [
    ...CanonicalArtifactsPngSignature.bytes,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', [9, 9, 9]),
    ...chunk('IEND', const []),
  ];
}

class CanonicalArtifactsPngSignature {
  static const List<int> bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
}

