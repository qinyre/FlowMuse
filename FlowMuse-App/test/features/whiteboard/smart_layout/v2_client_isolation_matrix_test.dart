/// V3-703A：客户端 v2 隔离与保留说明——目标符号
/// [V2ClientIsolationMatrix]。
///
/// 静态扫描 + 自动测试证明智能排版公开入口只到达 v3 Session：
/// 1. 公开入口面（gateways/rollout/session/analysis/views——页面层到
///    传输层的全部路径）零 v2 路由符号（reflow/fallbackToV2/routeToV2/
///    legacyV2）；
/// 2. 全 smart_layout v3 库零 v2 私有实现 import
///    （editor_core/src/core/smart_layout/** 不可达）；
/// 3. v3 库唯一分析端点串 = /api/ink/smart-layout/analyze/v3（零旧端点
///    串 /block /compose /vision /transcribe）；
/// 4. v2 私有代码原位保留：editor_core/src/core/smart_layout/** 与
///    test/features/whiteboard/editor_core/smart_layout* 测试清单入报告
///    （不做普查、迁移或删除，不新增兼容 wrapper）。
///
/// 证据生成：FLOWMUSE_GENERATE_V3_703A_EVIDENCE=1 一次性写入
/// docs/研发记录/evidence/smart-layout-v3/competition/
/// v3-703a-client-isolation.json；常规 flutter test 只读校验不重写。
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

/// 客户端 v2 隔离矩阵（V3-703A，比赛交付口径：隔离验证而非删除）。
class V2ClientIsolationMatrix {
  static final v2RoutingSymbolPattern = RegExp(
    r'(v2_?[Rr]eflow|fallbackToV2|routeToV2|legacyV2)',
  );

  /// 公开入口面：页面层→会话→传输的全部目录（v2 在此出现即违规）。
  static const publicSurfaceDirs = <String>[
    'lib/features/whiteboard/smart_layout/gateways',
    'lib/features/whiteboard/smart_layout/rollout',
    'lib/features/whiteboard/smart_layout/session',
    'lib/features/whiteboard/smart_layout/analysis',
    'lib/features/whiteboard/smart_layout/views',
  ];

  /// 旧端点路径片段（v3 库出现即违规；v3 唯一端点为 analyze/v3）。
  static const legacyEndpointFragments = <String>[
    "api/ink/smart-layout'",
    '"api/ink/smart-layout"',
    'api/ink/smart-layout/block',
    'api/ink/smart-layout/compose',
    'api/ink/smart-layout/vision',
    'api/ink/smart-layout/transcribe',
    'api/ink/recognize',
  ];

  final String appRoot;

  V2ClientIsolationMatrix({required this.appRoot});

  List<io.File> _dartFiles(String dir) => io.Directory('$appRoot/$dir')
      .listSync(recursive: true)
      .whereType<io.File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  /// 检查 1：公开入口面零 v2 路由符号。
  Map<String, Object?> publicSurfaceScan() {
    final offenders = <String>[];
    var scanned = 0;
    for (final dir in publicSurfaceDirs) {
      for (final file in _dartFiles(dir)) {
        scanned++;
        final matches =
            v2RoutingSymbolPattern.allMatches(file.readAsStringSync());
        if (matches.isNotEmpty) {
          offenders.add('${_rel(file)}: ${matches.length} 处');
        }
      }
    }
    return {
      'id': 'public-surface-zero-v2-symbols',
      'passed': offenders.isEmpty,
      'scanned_files': scanned,
      'offenders': offenders,
    };
  }

  /// 检查 2：全 smart_layout v3 库零 v2 私有实现 import。
  Map<String, Object?> crossImportScan() {
    final offenders = <String>[];
    var scanned = 0;
    for (final file in _dartFiles('lib/features/whiteboard/smart_layout')) {
      scanned++;
      for (final line in file.readAsStringSync().split('\n')) {
        final m = RegExp(r"^\s*(?:import|export)\s+'([^']+)'").firstMatch(line);
        if (m == null) continue;
        final target = m.group(1)!;
        if (target.contains('core/smart_layout/') ||
            target.contains('smart_layout_template_engine') ||
            target.contains('smart_layout_ink_clusterer')) {
          offenders.add('${_rel(file)} -> $target');
        }
      }
    }
    return {
      'id': 'v3-lib-zero-v2-imports',
      'passed': offenders.isEmpty,
      'scanned_files': scanned,
      'offenders': offenders,
    };
  }

  /// 检查 3：v3 库唯一分析端点串（零旧端点串，唯一 v3 端点真实存在）。
  Map<String, Object?> endpointStringScan() {
    final legacy = <String>[];
    var v3EndpointFiles = 0;
    for (final file in _dartFiles('lib/features/whiteboard/smart_layout')) {
      final source = file.readAsStringSync();
      if (source.contains('api/ink/smart-layout/analyze/v3')) {
        v3EndpointFiles++;
      }
      for (final fragment in legacyEndpointFragments) {
        if (source.contains(fragment)) {
          legacy.add('${_rel(file)} 含 $fragment');
        }
      }
    }
    return {
      'id': 'single-v3-endpoint-string',
      'passed': legacy.isEmpty && v3EndpointFiles > 0,
      'v3_endpoint_files': v3EndpointFiles,
      'legacy_endpoint_offenders': legacy,
    };
  }

  /// 检查 4：v2 私有代码原位保留（清单入报告，不删除不迁移）。
  Map<String, Object?> v2Inventory() {
    final libFiles = _dartFiles(
      'lib/features/whiteboard/editor_core/src/core/smart_layout',
    ).map(_rel).toList()..sort();
    final testFiles = io.Directory(
      '$appRoot/test/features/whiteboard/editor_core',
    )
        .listSync()
        .whereType<io.File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              _rel(f).split('/').last.startsWith('smart_layout_'),
        )
        .map(_rel)
        .toList()..sort();
    return {
      'id': 'v2-private-in-place',
      'passed': libFiles.isNotEmpty && testFiles.isNotEmpty,
      'lib_files': libFiles,
      'lib_file_count': libFiles.length,
      'test_files': testFiles,
      'test_file_count': testFiles.length,
      'note': '比赛版本兼容保留：原位不删除、不迁移、不新增兼容 wrapper',
    };
  }

  List<Map<String, Object?>> all() => [
    publicSurfaceScan(),
    crossImportScan(),
    endpointStringScan(),
    v2Inventory(),
  ];

  Map<String, Object?> toJson() => {
    'task': 'V3-703A',
    'kind': 'client_isolation_matrix',
    'all_passed': all().every((c) => c['passed'] as bool),
    'checks': all(),
    'retention_note':
        'v2 私有实现（editor_core/src/core/smart_layout/**，9 个 lib 文件）'
        '与 8 个既有测试原位保留；公开入口仅到达 v3 Session；'
        '不新增兼容 wrapper。',
  };

  String _rel(io.File file) =>
      file.path.replaceAll('\\', '/').substring(appRoot.length + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appRoot = io.Directory.current.path;
  final matrix = V2ClientIsolationMatrix(appRoot: appRoot);

  test('V2ClientIsolationMatrix：公开入口零 v2 可达 + 私有实现原位保留',
      () {
    final checks = matrix.all();
    final byId = {
      for (final c in checks) c['id'] as String: c,
    };
    expect(byId.keys, {
      'public-surface-zero-v2-symbols',
      'v3-lib-zero-v2-imports',
      'single-v3-endpoint-string',
      'v2-private-in-place',
    });

    final surface = byId['public-surface-zero-v2-symbols']!;
    expect(surface['passed'], isTrue, reason: '入口面 v2 符号：${surface['offenders']}');
    expect(surface['scanned_files'], greaterThan(10));

    final imports = byId['v3-lib-zero-v2-imports']!;
    expect(imports['passed'], isTrue, reason: 'v3 库 v2 import：${imports['offenders']}');

    final endpoints = byId['single-v3-endpoint-string']!;
    expect(endpoints['passed'], isTrue);
    expect(endpoints['v3_endpoint_files'], greaterThanOrEqualTo(1));

    final inventory = byId['v2-private-in-place']!;
    expect(inventory['passed'], isTrue);
    expect(inventory['lib_file_count'], greaterThanOrEqualTo(9));
    expect(inventory['test_file_count'], greaterThanOrEqualTo(8));

    final json = matrix.toJson();
    expect(json['all_passed'], isTrue);

    final target = io.File(
      '$appRoot/../docs/研发记录/evidence/smart-layout-v3/competition/'
      'v3-703a-client-isolation.json',
    );
    final generate =
        io.Platform.environment['FLOWMUSE_GENERATE_V3_703A_EVIDENCE'] == '1';
    if (generate) {
      target.createSync(recursive: true);
      target.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
    }
    if (target.existsSync()) {
      final persisted =
          jsonDecode(target.readAsStringSync()) as Map<String, Object?>;
      expect(persisted['all_passed'], isTrue);
      expect((persisted['checks']! as List).length, 4);
    }
  });
}
