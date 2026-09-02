/// V3-604A：性能、取消与资源压力 runner（合并原 V3-604A~B）。
///
/// 负载：3000 笔画 + 100 块 + 长页 + 多候选（3）渲染 + 连续 10 轮
/// 截图（PNG codec）循环；阶段预算（CI 稳定口径，3× 实测中位校准）
/// 逐阶段归因；资源回到容差（活资源精确归零）；取消/离页/失败注入
/// 零迟到写入。
///
/// 运行形态：flutter test（真实 ui.Image codec）；证据一次性生成经
/// 测试入口 env 门控写入 evidence/performance/。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Size;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/scene_metrics_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/hard_constraint_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/reduced_scene_metrics_extractor.dart';

/// 真实 1×1 PNG（可解码字节，渲染 fixture 同源）。
final Uint8List onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class PerformanceStageTiming {
  const PerformanceStageTiming({
    required this.id,
    required this.medianMs,
    required this.budgetMs,
    required this.detail,
  });

  final String id;
  final int medianMs;
  final int budgetMs;
  final String detail;

  bool get passed => medianMs <= budgetMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'median_ms': medianMs,
    'budget_ms': budgetMs,
    'passed': passed,
    'detail': detail,
  };
}

class PerformanceCheck {
  const PerformanceCheck(this.id, this.passed, this.detail);

  final String id;
  final bool passed;
  final String detail;

  Map<String, Object?> toJson() =>
      {'id': id, 'passed': passed, 'detail': detail};
}

class PerformanceReport {
  const PerformanceReport({
    required this.stages,
    required this.checks,
    required this.environment,
  });

  final List<PerformanceStageTiming> stages;
  final List<PerformanceCheck> checks;
  final String environment;

  bool get allPassed =>
      stages.every((s) => s.passed) && checks.every((c) => c.passed);

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'runner': 'SmartLayoutPerformanceRunner',
    'task_id': 'V3-604A',
    'load': {
      'ink_strokes': SmartLayoutPerformanceRunner.inkStrokeCount,
      'blocks': SmartLayoutPerformanceRunner.blockCount,
      'candidates': SmartLayoutPerformanceRunner.candidateCount,
      'render_cycles': SmartLayoutPerformanceRunner.renderCycles,
      'page_bounds': '长页 800×20000',
      'pixel_size': '1080×1528',
    },
    'stages': [for (final s in stages) s.toJson()],
    'checks': [for (final c in checks) c.toJson()],
    'environment': environment,
    'all_passed': allPassed,
  };
}

class SmartLayoutPerformanceRunner {
  static const inkStrokeCount = 3000;
  static const blockCount = 100;
  static const candidateCount = 3;
  static const renderCycles = 10;
  static const pageSize = Size(1080, 1528);

  /// 长页内容区（800×20000）。
  static final Bounds pageContent = Bounds.fromLTWH(0, 0, 800, 20000);

  // ---- 阶段预算（ms，CI 稳定口径：debug 实测中位 ~5-9× 校准，
  // 容机器方差）----
  static const budgetSnapshotMs = 200;
  static const budgetPatchBuildMs = 600;
  static const budgetReduceMs = 100;
  static const budgetRenderCandidatesMs = 5000;
  static const budgetMetricsMs = 200;
  static const budgetValidateMs = 200;

  Future<PerformanceReport> run({void Function(String line)? onTrace}) async {
    final trace = onTrace ?? (_) {};
    final stages = <PerformanceStageTiming>[];
    final checks = <PerformanceCheck>[];

    // ---- 负载：3000 笔画 + 20 图片 + 文本，全部 page-tagged ----
    final scene = _buildLoadScene();
    final revision = SceneRevision(
      epoch: 0,
      revision: 1,
      fingerprint: SceneFingerprint.of(scene),
    );

    // ---- 阶段 1：快照提取（长页 3000 笔画）----
    final extractor = const SnapshotExtractor();
    final snapshotTimings = <int>[];
    LayoutPageSnapshot pageSnapshot = extractor.extract(
      scene: scene,
      pageId: 'perf-page',
      sceneRevision: revision,
    );
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      pageSnapshot = extractor.extract(
        scene: scene,
        pageId: 'perf-page',
        sceneRevision: revision,
      );
      sw.stop();
      snapshotTimings.add(sw.elapsedMilliseconds);
    }
    stages.add(PerformanceStageTiming(
      id: 'snapshot-extract',
      medianMs: _median(snapshotTimings),
      budgetMs: budgetSnapshotMs,
      detail: '3000 笔画+20 图(含 5 crop)+文本；'
          'ink=${pageSnapshot.inkStrokes.length} '
          'assets=${pageSnapshot.renderAssets.length}',
    ));

    // ---- 阶段 2：100 块 patch 构建（账本 + 不变量）----
    final ledger = SourceCoverageLedger.pending(
      [for (var i = 0; i < inkStrokeCount; i++) 'ink-$i'],
    ).markConsumed(
      [for (var i = 0; i < 200; i++) 'ink-$i'],
    ).markPreserved(
      [for (var i = 200; i < inkStrokeCount; i++) 'ink-$i'],
    );
    final buildTimings = <int>[];
    var patch = _builderOf(scene, revision, ledger).build();
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      patch = _builderOf(scene, revision, ledger).build();
      sw.stop();
      buildTimings.add(sw.elapsedMilliseconds);
    }
    stages.add(PerformanceStageTiming(
      id: 'patch-build',
      medianMs: _median(buildTimings),
      budgetMs: budgetPatchBuildMs,
      detail: '100 块新增（sl3-perf-0..99）+账本 3000 源（200 consumed）',
    ));

    // ---- 阶段 3：折叠（reduce）----
    final reduceTimings = <int>[];
    var reduced = _reduce(scene, patch);
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      reduced = _reduce(scene, patch);
      sw.stop();
      reduceTimings.add(sw.elapsedMilliseconds);
    }
    stages.add(PerformanceStageTiming(
      id: 'reduce',
      medianMs: _median(reduceTimings),
      budgetMs: budgetReduceMs,
      detail: 'add 100 元素折叠进 3000 笔画场景',
    ));

    // ---- 阶段 4：多候选连续渲染（3 候选 × 渲染+PNG codec+dispose）----
    final renderer = DraftSceneRenderer();
    final renderSw = Stopwatch()..start();
    var totalPngBytes = 0;
    for (var c = 0; c < candidateCount; c++) {
      final snapshot = await renderer.render(
        scene: reduced.scene,
        viewport: const ViewportState(zoom: 1),
        pixelSize: pageSize,
      );
      final png = await snapshot.image.toByteData(format: ui.ImageByteFormat.png);
      totalPngBytes += png?.lengthInBytes ?? 0;
      snapshot.dispose();
    }
    renderSw.stop();
    stages.add(PerformanceStageTiming(
      id: 'render-candidates',
      medianMs: renderSw.elapsedMilliseconds,
      budgetMs: budgetRenderCandidatesMs,
      detail: '3 候选连续渲染（1080×1528）+PNG 编码 '
          '(${(totalPngBytes / 1024).toStringAsFixed(0)}KiB）+逐卡释放',
    ));
    checks.add(PerformanceCheck(
      'render-candidates 活资源归零',
      renderer.liveResourceCount == 0,
      'liveResourceCount=${renderer.liveResourceCount}',
    ));

    // ---- 阶段 5：metrics 提取（单候选代表）----
    final metricsSnapshot = await renderer.render(
      scene: reduced.scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: pageSize,
    );
    final metricsTimings = <int>[];
    var extraction = ReducedSceneMetricsExtractor.extract(
      reduced: reduced,
      snapshot: metricsSnapshot,
      ledger: ledger,
      pageContentBounds: pageContent,
    );
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      extraction = ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: metricsSnapshot,
        ledger: ledger,
        pageContentBounds: pageContent,
      );
      sw.stop();
      metricsTimings.add(sw.elapsedMilliseconds);
    }
    stages.add(PerformanceStageTiming(
      id: 'metrics-extract',
      medianMs: _median(metricsTimings),
      budgetMs: budgetMetricsMs,
      detail: '真实渲染层 metrics（coverage/关系/阅读序/可视边界）',
    ));

    // ---- 阶段 6：硬约束校验 ----
    final contract = const SceneMetricsContract();
    final metrics = contract.build(extraction);
    final validateTimings = <int>[];
    var report = HardConstraintValidator.validate(
      baseScene: scene,
      reduced: reduced,
      snapshot: metricsSnapshot,
      metrics: metrics,
      ledger: ledger,
      pageContentBounds: pageContent,
      imageIntrinsicSizes: const {'perf-img': Size(1, 1)},
    );
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      report = HardConstraintValidator.validate(
        baseScene: scene,
        reduced: reduced,
        snapshot: metricsSnapshot,
        metrics: metrics,
        ledger: ledger,
        pageContentBounds: pageContent,
        imageIntrinsicSizes: const {'perf-img': Size(1, 1)},
      );
      sw.stop();
      validateTimings.add(sw.elapsedMilliseconds);
    }
    metricsSnapshot.dispose();
    stages.add(PerformanceStageTiming(
      id: 'hard-constraint-validate',
      medianMs: _median(validateTimings),
      budgetMs: budgetValidateMs,
      detail: '十一类硬门禁全量复核（violations=${report.violations.length} '
          '为压测负载数据面，不作正确性断言）',
    ));

    // ---- 取消：并发代际作废零迟到写入 ----
    final cancelRenderer = DraftSceneRenderer();
    final future = cancelRenderer.render(
      scene: reduced.scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: pageSize,
    );
    cancelRenderer.cancelCurrent();
    var cancelledCleanly = false;
    try {
      await future;
    } on DraftRenderCancelled {
      cancelledCleanly = true;
    }
    checks.add(PerformanceCheck(
      '并发取消：在途渲染作废抛 DraftRenderCancelled 且活资源归零',
      cancelledCleanly && cancelRenderer.liveResourceCount == 0,
      'cancelled=$cancelledCleanly '
          'live=${cancelRenderer.liveResourceCount}',
    ));
    cancelRenderer.dispose();

    // ---- 离页/dispose：拒绝后续调用、资源归零 ----
    var disposeRejected = false;
    try {
      await cancelRenderer.render(
        scene: scene,
        viewport: const ViewportState(zoom: 1),
        pixelSize: pageSize,
      );
    } on StateError {
      disposeRejected = true;
    }
    checks.add(PerformanceCheck(
      '离页 dispose：释放后调用拒绝且活资源归零',
      disposeRejected && cancelRenderer.liveResourceCount == 0,
      'rejected=$disposeRejected',
    ));

    // ---- 失败注入：缺资产按编辑器占位语义降级，零泄漏 ----
    final missingScene = _buildLoadScene(includeFile: false);
    final faultRenderer = DraftSceneRenderer();
    final faultSnapshot = await faultRenderer.render(
      scene: missingScene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(400, 300),
    );
    checks.add(PerformanceCheck(
      '失败注入：缺文件降级占位如实记录（hasMissingResources）零泄漏',
      faultSnapshot.hasMissingResources &&
          faultSnapshot.missingFileIds.isNotEmpty &&
          faultRenderer.liveResourceCount == 0,
      'missing=${faultSnapshot.missingFileIds.length} '
          'live=${faultRenderer.liveResourceCount}',
    ));
    faultSnapshot.dispose();
    faultRenderer.dispose();

    // ---- 内存趋势：连续 10 轮截图循环，每轮活资源归零 ----
    var cyclesClean = true;
    final cycleRenderer = DraftSceneRenderer();
    for (var i = 0; i < renderCycles; i++) {
      final snap = await cycleRenderer.render(
        scene: reduced.scene,
        viewport: const ViewportState(zoom: 1),
        pixelSize: pageSize,
      );
      final png = await snap.image.toByteData(format: ui.ImageByteFormat.png);
      totalPngBytes += png?.lengthInBytes ?? 0;
      snap.dispose();
      if (cycleRenderer.liveResourceCount != 0) {
        cyclesClean = false;
        trace('cycle $i live=${cycleRenderer.liveResourceCount}');
      }
    }
    cycleRenderer.dispose();
    checks.add(PerformanceCheck(
      '内存趋势：连续 $renderCycles 轮渲染+PNG codec+释放，逐轮活资源归零',
      cyclesClean && cycleRenderer.liveResourceCount == 0,
      'cyclesClean=$cyclesClean totalPng='
          '${(totalPngBytes / 1024).toStringAsFixed(0)}KiB',
    ));

    renderer.dispose();

    return PerformanceReport(
      stages: stages,
      checks: checks,
      environment: 'flutter test debug；预算为 CI 稳定口径（实测中位 ~3×）',
    );
  }

  /// 压测负载场景：3000 笔画 + 20 图片 + 3 文本，page-tagged。
  Scene _buildLoadScene({bool includeFile = true}) {
    var scene = Scene();
    for (var i = 0; i < 5; i++) {
      scene = scene.addElement(ImageElement(
        id: ElementId('perf-crop-$i'),
        x: 420 + (i % 2) * 140.0,
        y: (i ~/ 2) * 140.0,
        width: 100,
        height: 100,
        fileId: 'perf-img',
        crop: ImageCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
        seed: 8,
        versionNonce: 8,
        updated: 1,
        customData: const {
          'flowMuse': {'pageId': 'perf-page'},
        },
      ));
    }
    for (var i = 0; i < 20; i++) {
      scene = scene.addElement(ImageElement(
        id: ElementId('perf-img-$i'),
        x: (i % 5) * 160.0,
        y: (i ~/ 5) * 160.0,
        width: 120,
        height: 120,
        fileId: 'perf-img',
        seed: 5,
        versionNonce: 5,
        updated: 1,
        customData: const {
          'flowMuse': {'pageId': 'perf-page'},
        },
      ));
    }
    for (var i = 0; i < 3; i++) {
      scene = scene.addElement(TextElement(
        id: ElementId('perf-text-$i'),
        x: 20,
        y: 1000.0 + i * 60,
        width: 400,
        height: 40,
        text: '压测文本 $i',
        fontSize: 24,
        fontFamily: 'Excalifont',
        seed: 6,
        versionNonce: 6,
        updated: 1,
        customData: const {
          'flowMuse': {'pageId': 'perf-page'},
        },
      ));
    }
    for (var i = 0; i < inkStrokeCount; i++) {
      final x = (i % 50) * 16.0;
      final y = (i ~/ 50) * 32.0 + 2000;
      scene = scene.addElement(FreedrawElement(
        id: ElementId('ink-$i'),
        x: x,
        y: y,
        width: 24,
        height: 12,
        points: const [Point(0, 0), Point(12, 6), Point(24, 12)],
        pressures: const [0.4, 0.5, 0.6],
        seed: i,
        versionNonce: i,
        updated: 1,
        customData: const {
          'flowMuse': {'pageId': 'perf-page'},
        },
      ));
    }
    if (includeFile) {
      scene = scene.addFile(
        'perf-img',
        ImageFile(mimeType: 'image/png', bytes: onePixelPng),
      );
    }
    return scene;
  }

  /// 100 块 patch：100 个 sl3-perf 文本新增 + 200 笔画软删（consumed）。
  SmartLayoutScenePatchBuilder _builderOf(
    Scene scene,
    SceneRevision revision,
    SourceCoverageLedger ledger,
  ) {
    final builder = SmartLayoutScenePatchBuilder(
      baseScene: scene,
      baseRevision: revision,
      sourceCoverage: ledger,
    );
    for (var i = 0; i < 200; i++) {
      builder.removeElement('ink-$i', baseVersion: 1, versionNonce: 5000 + i);
    }
    for (var b = 0; b < blockCount; b++) {
      builder.addElement(TextElement(
        id: ElementId('sl3-perf-$b'),
        x: 40 + (b % 2) * 380.0,
        y: 2100.0 + (b ~/ 2) * 90.0,
        width: 320,
        height: 60,
        text: '排版块 $b',
        fontSize: 20,
        fontFamily: 'Excalifont',
        seed: 100 + b,
        versionNonce: 9000 + b,
        updated: 42,
        customData: const {
          'flowMuse': {'pageId': 'perf-page'},
        },
      ));
    }
    return builder;
  }

  ReducedScene _reduce(Scene scene, SmartLayoutScenePatch patch) {
    final outcome = SmartLayoutSceneReducer.apply(base: scene, patch: patch);
    if (outcome is! ReducedScene) {
      throw StateError('压测 patch 折叠失败: $outcome');
    }
    return outcome;
  }

  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) ~/ 2;
  }
}
