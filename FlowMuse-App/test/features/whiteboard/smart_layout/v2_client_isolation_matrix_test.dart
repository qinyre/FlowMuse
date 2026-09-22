/// V3-703A：客户端 v2 隔离矩阵（v2 移除后修订版）。
///
/// 静态扫描证明智能排版公开入口只到达 v3 Session：
/// 1. 公开入口面（gateways/rollout/session/analysis/views——页面层到
///    传输层的全部路径）零 v2 路由符号（reflow/fallbackToV2/routeToV2/
///    legacyV2/prepareSmartLayoutTemplates 等）；
/// 2. 全 smart_layout v3 库零 v2 私有实现 import
///    （editor_core/src/core/smart_layout/** 不可达）；
/// 3. V3 recognize/v3 生产端点与 analyze/v3 实验端点共存，零旧端点
///    串 /block /compose /vision /transcribe。
///
/// 2026-09-21：v2 私有实现（模板引擎/聚类/视觉匹配/草稿态）已整体删除，
/// 原检查 4"v2 私有代码原位保留"随之退役；历史证据文件
/// v3-703a-client-isolation.json 记录删除前状态，不再作为比对基准。
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

/// 客户端 v2 隔离矩阵：公开入口零 v2 可达。
class V2ClientIsolationMatrix {
  static final v2RoutingSymbolPattern = RegExp(
    r'(v2_?[Rr]eflow|fallbackToV2|routeToV2|legacyV2|'
    r'\.(prepareSmartLayoutTemplates|cancelSmartLayoutPreparation|onVisionSmartLayout)\b)',
  );

  /// 公开入口面：页面层→会话→传输的全部目录（v2 在此出现即违规）。
  static const publicSurfaceDirs = <String>[
    'lib/features/whiteboard/smart_layout/gateways',
    'lib/features/whiteboard/smart_layout/rollout',
    'lib/features/whiteboard/smart_layout/session',
    'lib/features/whiteboard/smart_layout/analysis',
    'lib/features/whiteboard/smart_layout/recognition',
    'lib/features/whiteboard/smart_layout/views',
  ];

  /// 旧端点路径片段（v3 库出现即违规）。
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
        final matches = v2RoutingSymbolPattern.allMatches(
          file.readAsStringSync(),
        );
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
            target.contains('smart_layout_ink_clusterer') ||
            target.endsWith('/ink_recognition_repository.dart')) {
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

  /// 检查 3：生产识别与实验分析端点均存在，零旧端点串。
  Map<String, Object?> endpointStringScan() {
    final legacy = <String>[];
    var v3EndpointFiles = 0;
    var recognitionEndpointFiles = 0;
    for (final file in _dartFiles('lib/features/whiteboard/smart_layout')) {
      final source = file.readAsStringSync();
      if (source.contains('api/ink/smart-layout/analyze/v3')) {
        v3EndpointFiles++;
      }
      if (source.contains('api/ink/smart-layout/recognize/v3')) {
        recognitionEndpointFiles++;
      }
      for (final fragment in legacyEndpointFragments) {
        if (source.contains(fragment)) {
          legacy.add('${_rel(file)} 含 $fragment');
        }
      }
    }
    return {
      'id': 'single-v3-endpoint-string',
      'passed':
          legacy.isEmpty && v3EndpointFiles > 0 && recognitionEndpointFiles > 0,
      'v3_endpoint_files': v3EndpointFiles,
      'recognition_endpoint_files': recognitionEndpointFiles,
      'legacy_endpoint_offenders': legacy,
    };
  }

  List<Map<String, Object?>> all() => [
    publicSurfaceScan(),
    crossImportScan(),
    endpointStringScan(),
  ];

  String _rel(io.File file) =>
      file.path.replaceAll('\\', '/').substring(appRoot.length + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appRoot = io.Directory.current.path;
  final matrix = V2ClientIsolationMatrix(appRoot: appRoot);

  test('R8 静态隔离同时拦截直接调用、tear-off 与旧视觉回调访问', () {
    for (final source in [
      'controller.prepareSmartLayoutTemplates(pageId: id)',
      'final prepare = controller.prepareSmartLayoutTemplates;',
      'onCancel: controller.cancelSmartLayoutPreparation,',
      'final vision = controller.onVisionSmartLayout;',
    ]) {
      expect(
        V2ClientIsolationMatrix.v2RoutingSymbolPattern.hasMatch(source),
        isTrue,
      );
    }
  });

  test('V2ClientIsolationMatrix：公开入口零 v2 可达', () {
    final checks = matrix.all();
    final byId = {for (final c in checks) c['id'] as String: c};
    expect(byId.keys, {
      'public-surface-zero-v2-symbols',
      'v3-lib-zero-v2-imports',
      'single-v3-endpoint-string',
    });

    final surface = byId['public-surface-zero-v2-symbols']!;
    expect(
      surface['passed'],
      isTrue,
      reason: '入口面 v2 符号：${surface['offenders']}',
    );
    expect(surface['scanned_files'], greaterThan(10));

    final imports = byId['v3-lib-zero-v2-imports']!;
    expect(
      imports['passed'],
      isTrue,
      reason: 'v3 库 v2 import：${imports['offenders']}',
    );

    final endpoints = byId['single-v3-endpoint-string']!;
    expect(endpoints['passed'], isTrue);
    expect(endpoints['v3_endpoint_files'], greaterThanOrEqualTo(1));
    expect(endpoints['recognition_endpoint_files'], greaterThanOrEqualTo(1));
  });
}
