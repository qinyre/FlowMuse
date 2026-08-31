import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// V3-001B/C 测试共享助手：临时 fixture 构造、篡改与 dart VM 定位。
Map<String, Object?> buildAdmissibleManifest(Directory root) {
  final sceneBytes = utf8.encode('{"z":1,"a":{"b":[1,2.0]}}');
  final sceneSha = crypto.sha256.convert(sceneBytes).toString();
  final goldenBytes = minimalPng();
  final goldenSha = crypto.sha256.convert(goldenBytes).toString();
  final fontBytes = utf8.encode('fake-regular');
  final fontSha = crypto.sha256.convert(fontBytes).toString();
  final replayBytes = utf8.encode('{"synthetic":true}');
  final replaySha = crypto.sha256.convert(replayBytes).toString();
  writeFile(root, 'artifacts/scene.json', sceneBytes);
  writeFile(root, 'artifacts/golden.png', goldenBytes);
  writeFile(root, 'fonts/Roboto.ttf', fontBytes);
  writeFile(root, 'replay/vlm_overview.json', replayBytes);
  return <String, Object?>{
    'schema_version': '1.0.0',
    'manifest_kind': 'smart-layout-v3-fixture-manifest',
    'manifest': <String, Object?>{
      'name': 'runner-check',
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
            'sha256': replaySha,
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

/// 边界完整（授权/脱敏/删除/隔离键齐全）且携带 authorized_real 录制的 manifest：
/// V3-001A 层可解析，V3-001C 政策层应拒。
Map<String, Object?> authorizedRealManifest(Directory root) {
  final base = buildAdmissibleManifest(root);
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

void writeFile(Directory root, String relativePath, List<int> bytes) {
  final file =
      File('${root.path}${Platform.pathSeparator}${relativePath.replaceAll('/', Platform.pathSeparator)}');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

/// 篡改产物：绕过哈希重算，制造真实的完整性违规。
void tamperFile(Directory root, String relativePath, List<int> bytes) =>
    writeFile(root, relativePath, bytes);

String findDart() {
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

List<int> minimalPng() {
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
    ...pngSignature,
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', [9, 9, 9]),
    ...chunk('IEND', const []),
  ];
}

const List<int> pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
