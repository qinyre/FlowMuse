import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 智能排版 v3 feature 的架构/import 边界契约（计划书 §4.1）：
/// - editor 控制器与 HTTP 传输只能经 gateways/ 触达；
/// - gateways/ 是最底层，不得依赖其他 smart_layout 子包，也不进 UI 层；
/// - 全 feature 禁止引入第二套 HTTP client。
void main() {
  final smartLayoutDir = Directory('lib/features/whiteboard/smart_layout');
  test('smart_layout feature 目录存在', () {
    expect(
      smartLayoutDir.existsSync(),
      isTrue,
      reason: 'V3-100A 必须已建立 feature 骨架',
    );
  });

  final files =
      smartLayoutDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  /// 解析每个文件的 import/export 指令（含 show/hide 修饰前的目标 URI）。
  Map<String, List<String>> directiveTargets(File file) {
    final targets = <String>[];
    for (final line in file.readAsStringSync().split('\n')) {
      final match = RegExp(
        r"^\s*(?:import|export)\s+'([^']+)'",
      ).firstMatch(line);
      if (match != null) targets.add(match.group(1)!);
    }
    return {file.path: targets};
  }

  test('gateways/ 之外不得直接 import 编辑器控制器或 HTTP client', () {
    expect(files, isNotEmpty);
    final offenders = <String>[];
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/');
      final isGateway = normalized.contains('/smart_layout/gateways/');
      if (isGateway) continue;
      for (final target in directiveTargets(file).values.expand((v) => v)) {
        if (target.contains('markdraw_controller.dart') ||
            target.contains('native_http_client.dart')) {
          offenders.add('$normalized -> $target');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '控制器与 HTTP 传输只能经 gateways/ 触达：$offenders',
    );
  });

  test('全 feature 禁止 package:http 与其他 HTTP 栈', () {
    final offenders = <String>[];
    for (final file in files) {
      for (final target in directiveTargets(file).values.expand((v) => v)) {
        if (target.startsWith('package:http/') ||
            target.startsWith('package:dio/') ||
            target.startsWith('dart:io')) {
          offenders.add('${file.path} -> $target');
        }
      }
    }
    expect(offenders, isEmpty, reason: '不引入第二套 client：$offenders');
  });

  test('gateways/ 不得 import UI 层或其他 smart_layout 子包（保持最底层）', () {
    final offenders = <String>[];
    final gatewayInternal = RegExp(
      r'(/|^)smart_layout/gateways/[a-z_]+\.dart$',
    );
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/');
      if (!normalized.contains('/smart_layout/gateways/')) continue;
      for (final target in directiveTargets(file).values.expand((v) => v)) {
        final isFlutterUi =
            target.startsWith('package:flutter/') &&
            (target.contains('widgets.dart') ||
                target.contains('material.dart') ||
                target.contains('rendering.dart'));
        final isUpwardDep =
            target.contains('smart_layout/') &&
            !gatewayInternal.hasMatch(target);
        if (isFlutterUi ||
            isUpwardDep ||
            target.contains('views/whiteboard_page.dart')) {
          offenders.add('$normalized -> $target');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'gateways 必须保持最底层、不进 UI 层：$offenders');
  });

  test('gateways/ 内仅 editor gateway 与 public entry 可引用 MarkdrawController', () {
    final offenders = <String>[];
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/');
      if (!normalized.contains('/smart_layout/gateways/')) continue;
      final basename = normalized.split('/').last;
      if (basename == 'smart_layout_editor_gateway.dart' ||
          basename == 'smart_layout_public_entry.dart') {
        continue;
      }
      if (file.readAsStringSync().contains('MarkdrawController')) {
        offenders.add(normalized);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '控制器句柄只属于 editor gateway 与 public entry：$offenders',
    );
  });

  test('目标边界符号存在：三个 gateway 类型可被引用', () {
    expect(
      files.map((f) => f.path.replaceAll('\\', '/')),
      containsAll(<String>[
        'lib/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart',
        'lib/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart',
        'lib/features/whiteboard/smart_layout/gateways/smart_layout_public_entry.dart',
      ]),
    );
  });
}
