import 'dart:ui' show Size;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';

import '../metrics/scene_metrics_contract.dart';
import '../patch/smart_layout_patch_validator.dart';
import '../reducer/smart_layout_scene_reducer.dart';
import '../rendering/draft_scene_renderer.dart';
import '../snapshot/source_coverage_ledger.dart';
import 'reduced_scene_metrics_extractor.dart';

/// 硬约束类型（全部 fail closed：任何一条违规即整体失败，软分不可
/// 抵消——与 V3-404A 硬软隔离一致）。
enum HardConstraintKind {
  /// 证据链断链：metrics 的 revision/digest 与真实产物不符。
  provenance,

  /// ledger 源丢失（未消费也未保留/不在场）。
  coverageLost,

  /// ledger 状态非 consumed/preserved（pending）或账本守恒破坏。
  ledgerConservation,

  /// 语义关系（caption/keep）未满足。
  relation,

  /// 阅读序相邻对错序。
  readingOrder,

  /// 文本真实墨迹超出元素盒（裁字）。
  textClipping,

  /// 图片显示比例偏离内在比例（crop 感知）。
  aspectRatio,

  /// 非写入元素的 groupIds/frameId/boundElements 被悄悄改动。
  relationIntegrityTampered,

  /// 渲染层存在悬空关系引用（frameId/containerId/boundElements）。
  relationIntegrityDangling,

  /// 层真实几何超出页内容区。
  pageBounds,

  /// 渲染层与 metrics 页界计数不一致（自报不实）。
  metricUnderreport,
}

class HardConstraintViolation {
  const HardConstraintViolation({
    required this.kind,
    required this.subjectIds,
    required this.detail,
  });

  final HardConstraintKind kind;
  final List<String> subjectIds;
  final String detail;

  @override
  String toString() =>
      '${kind.name}(${subjectIds.take(4).join(',')}${subjectIds.length > 4 ? '…' : ''}) $detail';
}

class HardConstraintReport {
  const HardConstraintReport({required this.violations});

  final List<HardConstraintViolation> violations;

  bool get passed => violations.isEmpty;
}

/// 硬约束验证器（V3-504A）：对 **reducer + renderer 的真实产物**做
/// 全量硬门禁——coverage/relation/order/裁字/比例/group/frame/binding/
/// 页界/ledger 守恒，全部基于真实归约 Scene 与渲染层几何；不读取
/// placement 层自报（源码门禁：零 placement 引用）。
///
/// fail closed 语义：证据链断链、状态含糊、计数不一致一律失败。
abstract final class HardConstraintValidator {
  /// [imageIntrinsicSizes]：fileId → 内在像素尺寸（快照资产的既成事实，
  /// 由调用方从 base 快照提供；缺项按未知跳过比例检查并如实留档）。
  static HardConstraintReport validate({
    required Scene baseScene,
    required ReducedScene reduced,
    required DraftRenderSnapshot snapshot,
    required SceneMetricsSnapshot metrics,
    required SourceCoverageLedger ledger,
    required Bounds pageContentBounds,
    Map<String, Size> imageIntrinsicSizes = const {},
    double aspectTolerance = 0.02,
    double clipTolerance = 0.5,
  }) {
    final violations = <HardConstraintViolation>[];
    final patch = reduced.patch;

    // ---- 1. 证据链：revision/digest 与真实产物一致（hash 断链即失败）----
    if (metrics.sceneRevision != patch.baseRevision.revision) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.provenance,
          subjectIds: const [],
          detail:
              'metrics revision ${metrics.sceneRevision} != patch '
              'baseRevision ${patch.baseRevision.revision}',
        ),
      );
    }
    final actualDigest = reducedSceneDigestOf(snapshot);
    if (metrics.renderedSceneDigest != actualDigest) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.provenance,
          subjectIds: const [],
          detail: 'renderedSceneDigest 断链：metrics 自报与渲染层重算不符',
        ),
      );
    }

    // ---- 2. coverage 丢失与 ledger 守恒 ----
    if (metrics.coverage.missingSourceIds.isNotEmpty) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.coverageLost,
          subjectIds: metrics.coverage.missingSourceIds,
          detail: '源丢失：未消费未保留或不在场',
        ),
      );
    }
    final ledgerViolations =
        SmartLayoutScenePatchValidator.checkLedgerConservation(patch: patch);
    if (ledgerViolations.isNotEmpty) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.ledgerConservation,
          subjectIds: [for (final v in ledgerViolations) v.subjectId],
          detail:
              '账本守恒破坏：${ledgerViolations.map((v) => v.kind.name).join(',')}',
        ),
      );
    }

    // ---- 3. 关系与阅读序（真实渲染几何判定的满足表；compliance/accuracy
    //      由提取器从真实几何计算，比率 < 1 即存在违规）----
    if (metrics.relationCompliance < 1.0) {
      violations.add(
        const HardConstraintViolation(
          kind: HardConstraintKind.relation,
          subjectIds: [],
          detail: '存在未满足的语义关系（compliance<1.0）',
        ),
      );
    }
    if (metrics.orderPairAccuracy < 1.0) {
      violations.add(
        const HardConstraintViolation(
          kind: HardConstraintKind.readingOrder,
          subjectIds: [],
          detail: '阅读序相邻对存在错序（accuracy<1.0）',
        ),
      );
    }

    // ---- 4. 裁字：文本真实墨迹盒 ⊆ 元素盒（容差内）----
    final elementById = {
      for (final element in reduced.scene.activeElements)
        element.id.value: element,
    };
    final layerById = {
      for (final layer in snapshot.layers) layer.elementId: layer,
    };
    for (final entry in elementById.entries) {
      if (entry.value is! TextElement) continue;
      final layer = layerById[entry.key];
      if (layer == null) continue;
      final element = entry.value;
      final inkW = layer.bounds.size.width;
      final inkH = layer.bounds.size.height;
      if (inkW > element.width + clipTolerance ||
          inkH > element.height + clipTolerance) {
        violations.add(
          HardConstraintViolation(
            kind: HardConstraintKind.textClipping,
            subjectIds: [entry.key],
            detail:
                '墨迹 ${inkW.toStringAsFixed(1)}x'
                '${inkH.toStringAsFixed(1)} 超出元素盒 '
                '${element.width.toStringAsFixed(1)}x'
                '${element.height.toStringAsFixed(1)}',
          ),
        );
      }
    }

    // ---- 5. 比例：图片显示比例 vs 内在比例（crop 感知）----
    for (final entry in elementById.entries) {
      final element = entry.value;
      if (element is! ImageElement) continue;
      final intrinsic = imageIntrinsicSizes[element.fileId];
      if (intrinsic == null) continue;
      var expectedW = intrinsic.width.toDouble();
      var expectedH = intrinsic.height.toDouble();
      final crop = element.crop;
      if (crop != null) {
        expectedW *= crop.width;
        expectedH *= crop.height;
      }
      if (expectedW <= 0 || expectedH <= 0) continue;
      final expected = expectedW / expectedH;
      final displayed = element.width / element.height;
      if ((displayed - expected).abs() > aspectTolerance * expected) {
        violations.add(
          HardConstraintViolation(
            kind: HardConstraintKind.aspectRatio,
            subjectIds: [entry.key],
            detail:
                '显示比例 $displayed 偏离内在比例 '
                '${expected.toStringAsFixed(3)}（fileId=${element.fileId}）',
          ),
        );
      }
    }

    // ---- 6. 关系完整性：非写入元素零静默改动 + 无悬空引用 ----
    final writeIds = patch.writeSet.elementIds.toSet();
    final baseById = {
      for (final element in baseScene.elements) element.id.value: element,
    };
    final tampered = <String>[];
    for (final element in reduced.scene.activeElements) {
      if (writeIds.contains(element.id.value)) continue;
      final before = baseById[element.id.value];
      if (before == null) continue;
      final sameGroup = _sameList(before.groupIds, element.groupIds);
      final sameFrame = before.frameId == element.frameId;
      final sameBound = _sameBoundElements(before, element);
      if (!sameGroup || !sameFrame || !sameBound) {
        tampered.add(element.id.value);
      }
    }
    if (tampered.isNotEmpty) {
      tampered.sort();
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.relationIntegrityTampered,
          subjectIds: List.unmodifiable(tampered),
          detail: '非写入元素的 group/frame/binding 被静默改动',
        ),
      );
    }

    final dangling = <String>[];
    for (final element in reduced.scene.activeElements) {
      final frameId = element.frameId;
      if (frameId != null && !elementById.containsKey(frameId)) {
        dangling.add(element.id.value);
      }
      if (element is TextElement) {
        final containerId = element.containerId;
        if (containerId != null && !elementById.containsKey(containerId)) {
          dangling.add(element.id.value);
        }
      }
      for (final bound in element.boundElements) {
        if (!elementById.containsKey(bound.id)) {
          dangling.add(element.id.value);
        }
      }
    }
    if (dangling.isNotEmpty) {
      final unique = dangling.toSet().toList()..sort();
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.relationIntegrityDangling,
          subjectIds: List.unmodifiable(unique),
          detail: '渲染后存在悬空关系引用',
        ),
      );
    }

    // ---- 7. 页界：层真实几何全部 ⊆ 页内容区 + 计数与自报一致 ----
    final outside = <String>[];
    for (final layer in snapshot.layers) {
      final b = layer.bounds;
      final inside =
          b.left >= pageContentBounds.left - 1e-9 &&
          b.top >= pageContentBounds.top - 1e-9 &&
          b.right <= pageContentBounds.right + 1e-9 &&
          b.bottom <= pageContentBounds.bottom + 1e-9;
      if (!inside) outside.add(layer.elementId);
    }
    if (outside.isNotEmpty) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.pageBounds,
          subjectIds: List.unmodifiable(outside),
          detail: '层几何超出页内容区',
        ),
      );
    }
    if (metrics.visualBoundsViolations != outside.length) {
      violations.add(
        HardConstraintViolation(
          kind: HardConstraintKind.metricUnderreport,
          subjectIds: const [],
          detail:
              '页界违规自报 ${metrics.visualBoundsViolations} != '
              '实测 ${outside.length}',
        ),
      );
    }

    return HardConstraintReport(violations: List.unmodifiable(violations));
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameBoundElements(Element a, Element b) {
    if (a.boundElements.length != b.boundElements.length) return false;
    for (var i = 0; i < a.boundElements.length; i++) {
      final x = a.boundElements[i];
      final y = b.boundElements[i];
      if (x.id != y.id || x.type != y.type) return false;
    }
    return true;
  }
}
