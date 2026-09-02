import 'dart:io';
import 'dart:math' as math;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-304A：helper 迁移前快照与最小适配边界（合并原 V3-304A~B）。
///
/// Phase 3~5 会继续触及 editor_core 既有几何/边界 helper。本 fixture
/// 在适配之前冻结两件事：
/// 1. 实际触及 helper 的**行为快照**（数值级），防止上游顺手改动悄悄
///    改变智能排版的几何语义；
/// 2. 这些 helper 在 editor_core 内的**调用者计数快照**——新增/删除
///    调用者必须先更新 [ConditionalAdapterAllowlist] 与 compatibility
///    report，不允许静默扩张。
class GeometryCompatibilityFixture {
  const GeometryCompatibilityFixture();

  // ---- 行为快照（数值级冻结）----

  /// 荧光笔可视半宽：renderSize(=sw×4.2)×0.5 + 抗锯齿余量 2.0
  ///（恒宽 thinning=0；BrushRenderProfile.visualHalfWidth 冻结公式）。
  double highlighterHalfWidth(double strokeWidth) =>
      strokeWidth * 4.2 * 0.5 + 2.0;

  /// 旋转外扩快照：angle≠0 时可视边界 = 旋转四角 AABB，
  /// 宽 = (w+h)·|cos(rad)|（conservativeVisualBounds 冻结语义）。
  double rotatedAabbExtent(double w, double h, double rad) =>
      (w + h) * math.cos(rad).abs();

  // ---- 调用者计数快照（口径：带括号的真实调用，排除定义文件）----

  static const String editorCoreRoot =
      'lib/features/whiteboard/editor_core/src';

  static const String trackedHelper = 'elementVisualBounds';

  /// 冻结快照（2026-09-01，V3-304A 适配前）。路径相对 editor_core/src。
  static const Map<String, int> frozenHelperCallers = {
    'core/scene/scene.dart': 2,
    'rendering/export/export_bounds.dart': 1,
    'rendering/viewport_culling.dart': 1,
  };

  /// 扫描当前真实调用计数（同口径：`elementVisualBounds(`，排除定义行）。
  Map<String, int> scanCurrentCallers() {
    final counts = <String, int>{};
    final root = Directory(editorCoreRoot);
    final files =
        root.listSync(recursive: true).whereType<File>().where(
          (f) => f.path.endsWith('.dart'),
        );
    for (final file in files) {
      final normalized = file.path.replaceAll('\\', '/').substring(
        file.path.replaceAll('\\', '/').indexOf(editorCoreRoot) +
            editorCoreRoot.length +
            1,
      );
      var count = 0;
      for (final line in file.readAsStringSync().split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (trimmed.startsWith('Bounds elementVisualBounds(')) continue;
        if (trimmed.contains('$trackedHelper(')) count++;
      }
      if (count > 0) counts[normalized] = count;
    }
    return counts;
  }

  /// editor_core 反向依赖 v3 feature 的文件（必须为空：v3 不导出
  /// 通用 kernel，editor_core 不得 import features/whiteboard/smart_layout）。
  List<String> scanReverseDependencies() {
    const v3Marker = 'whiteboard/smart_layout/';
    final offenders = <String>[];
    final root = Directory(editorCoreRoot);
    for (final file
        in root.listSync(recursive: true).whereType<File>().where(
              (f) => f.path.endsWith('.dart'),
            )) {
      for (final line in file.readAsStringSync().split('\n')) {
        final trimmed = line.trim();
        if ((trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
            trimmed.contains(v3Marker)) {
          offenders.add(file.path);
          break;
        }
      }
    }
    return offenders;
  }
}

/// V3-304A：条件适配 allowlist（最小适配边界）。
///
/// 原则：现有 editor_core 接口足够时**零适配**（V3-301A/302A 直接复用
/// SnapshotBounds / conservativeVisualBounds / elementVisualBounds 已
/// 证明）；只有"现有接口确实不足"才允许登记一条 feature-private 薄
/// adapter。禁止公共 wrapper 链、所有权迁移、调用者搬迁。
class ConditionalAdapterAllowlist {
  const ConditionalAdapterAllowlist();

  /// 登记条件（全部满足才允许出现在 [registeredAdapters]）。
  static const List<String> conditions = [
    '现有 editor_core 公开接口确实不足（缺失，而非不便）',
    'adapter 是 feature-private（位于 smart_layout 内，不进 editor_core）',
    '薄适配：单一职责直连，禁止 wrapper 链',
    '不迁移既有调用者，不改变公共 API 行为',
    '在 compatibility report 同步登记理由与冻结日期',
  ];

  /// 当前登记的 adapter 快照（2026-09-01，V3-304A）。
  /// 唯一一条：真实文本测量复用 renderer 字体解析（V3-300A 交付，
  /// barrel 未导出 font_resolver，测量与渲染必须同路径）。
  static const List<Map<String, String>> registeredAdapters = [
    {
      'consumer': 'smart_layout/design/text_measure_adapter.dart',
      'target': 'editor_core/src/rendering/font_resolver.dart',
      'reason': '真实文本测量必须与 renderer 同字体解析路径；公共 barrel 未导出',
      'frozen_at': '2026-08-31',
    },
  ];

  /// smart_layout 内允许深路径 import editor_core 的文件白名单
  ///（与 [registeredAdapters] 一一对应；其余 smart_layout 文件只允许
  /// barrel 导入，由架构守卫测试另行约束）。
  static const Set<String> deepImportAllowlist = {
    'lib/features/whiteboard/smart_layout/design/text_measure_adapter.dart',
  };

  /// 扫描 smart_layout 深路径 import editor_core 的文件。
  Map<String, List<String>> scanDeepImports() {
    const root = 'lib/features/whiteboard/smart_layout';
    const barrel = 'editor_core/flow_muse_whiteboard_editor.dart';
    final result = <String, List<String>>{};
    for (final file
        in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final normalized = file.path.replaceAll('\\', '/');
      for (final line in file.readAsStringSync().split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('import ')) continue;
        if (!trimmed.contains('editor_core')) continue;
        if (trimmed.contains(barrel)) continue;
        result.putIfAbsent(normalized, () => []).add(trimmed);
      }
    }
    return result;
  }
}

void main() {
  const fixture = GeometryCompatibilityFixture();
  const allowlist = ConditionalAdapterAllowlist();

  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeometryCompatibilityFixture 行为快照（适配前冻结）', () {
    test('荧光笔可视边界含包络外扩（renderer 同路径）', () {
      final stroke = FreedrawElement(
        id: const ElementId('compat-highlighter'),
        x: 0,
        y: 0,
        width: 200,
        height: 20,
        points: const [Point(0, 0), Point(200, 20)],
        pressures: const [0.5, 0.5],
        strokeWidth: 30,
        seed: 1,
        versionNonce: 1,
        updated: 1,
        customData: const {
          'flowMuse': {'pageId': 'p1', 'brushType': 'highlighter'},
        },
      );
      final visual = elementVisualBounds(stroke);
      final half = fixture.highlighterHalfWidth(30);
      expect(visual.left, closeTo(0 - half, 1e-9));
      expect(visual.right - visual.left, closeTo(200 + half * 2, 1e-9));
    });

    test('旋转外扩快照：conservativeVisualBounds 四角 AABB 数值级一致', () {
      final element = RectangleElement(
        id: const ElementId('compat-rot'),
        x: 0,
        y: 0,
        width: 40,
        height: 30,
        angle: 0.7853981633974483,
        seed: 2,
        versionNonce: 2,
        updated: 1,
      );
      final visual = conservativeVisualBounds(element);
      final expected = fixture.rotatedAabbExtent(40, 30, 0.7853981633974483);
      expect(visual.width, closeTo(expected, 1e-9));
      expect(visual.height, closeTo(expected, 1e-9));
      // angle=0 恒等：不旋转直接返回可视边界。
      final flat = RectangleElement(
        id: const ElementId('compat-flat'),
        x: 5,
        y: 6,
        width: 40,
        height: 30,
        seed: 3,
        versionNonce: 3,
        updated: 1,
      );
      expect(conservativeVisualBounds(flat).left, 5);
      expect(conservativeVisualBounds(flat).width, 40);
    });
  });

  group('调用者计数快照（helper 迁移警戒线）', () {
    test('elementVisualBounds 调用者与冻结快照一致', () {
      final current = fixture.scanCurrentCallers();
      expect(
        current,
        GeometryCompatibilityFixture.frozenHelperCallers,
        reason: '调用者变动必须先更新 ConditionalAdapterAllowlist 与 '
            'compatibility report：当前 $current，冻结 '
            '${GeometryCompatibilityFixture.frozenHelperCallers}',
      );
    });

    test('editor_core 零反向依赖 v3 feature', () {
      expect(
        fixture.scanReverseDependencies(),
        isEmpty,
        reason: 'v3 不导出通用 kernel；editor_core 不得 import smart_layout',
      );
    });
  });

  group('ConditionalAdapterAllowlist 最小适配边界', () {
    test('登记条件完备（五条硬条件）', () {
      expect(ConditionalAdapterAllowlist.conditions.length, 5);
      expect(ConditionalAdapterAllowlist.conditions, everyElement(contains('')));
    });

    test('深路径 import 与登记一一对应，无未登记适配', () {
      final deep = allowlist.scanDeepImports();
      final files = deep.keys.toSet();
      final expected = {
        for (final adapter in ConditionalAdapterAllowlist.registeredAdapters)
          'lib/features/whiteboard/${adapter['consumer']!}',
      };
      expect(
        files,
        expected,
        reason: 'allowlist 外出现深路径 import：$deep；必须先登记'
            ' ConditionalAdapterAllowlist 再适配',
      );
    });
  });
}
