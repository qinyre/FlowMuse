import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/reducer/smart_layout_scene_reducer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/scene_metrics_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/hard_constraint_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/validation/reduced_scene_metrics_extractor.dart';

/// 1×1 红色 PNG（真实可解码字节）。
final onePixelPng = ImageFile(
  mimeType: 'image/png',
  bytes: Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
      'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(
    String id, {
    double x = 10,
    List<String> groups = const [],
    int version = 1,
  }) => RectangleElement(
    id: ElementId(id),
    x: x,
    y: 10,
    width: 40,
    height: 40,
    groupIds: groups,
    version: version,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  TextElement text(
    String id, {
    double x = 5,
    double w = 200,
    String body = '正文',
    String? container,
  }) {
    return TextElement(
      id: ElementId(id),
      x: x,
      y: 5,
      width: w,
      height: 28,
      text: body,
      fontSize: 20,
      fontFamily: 'Excalifont',
      containerId: container,
      seed: 7,
      versionNonce: 11,
      updated: 1000,
    );
  }

  FreedrawElement ink(String id) => FreedrawElement(
    id: ElementId(id),
    x: 300,
    y: 300,
    width: 160,
    height: 60,
    points: const [Point(0, 0), Point(160, 60)],
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  ImageElement image(
    String id,
    String fileId, {
    double w = 40,
    double h = 40,
    int version = 1,
  }) => ImageElement(
    id: ElementId(id),
    x: 60,
    y: 60,
    width: w,
    height: h,
    fileId: fileId,
    version: version,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
  );

  /// 标准基线：s1(消费改写) + i1/i2(消费移除) + img1(消费改写) +
  /// p1(preserved 不动)。全部落在页内容区内。
  Scene baseScene() => Scene()
      .addElement(rect('s1'))
      .addElement(ink('i1'))
      .addElement(ink('i2'))
      .addElement(image('img1', 'file-1'))
      .addElement(rect('p1'))
      .addFile('file-1', onePixelPng);

  SourceCoverageLedger standardLedger() => SourceCoverageLedger.pending(const [
    's1',
    'i1',
    'i2',
    'img1',
    'p1',
  ]).markConsumed(const ['s1', 'i1', 'i2', 'img1']).markPreserved(const ['p1']);

  SmartLayoutScenePatchBuilder builderFor(
    Scene scene, {
    SourceCoverageLedger? ledger,
  }) => SmartLayoutScenePatchBuilder(
    baseScene: scene,
    baseRevision: SceneRevision(
      epoch: 0,
      revision: 5,
      fingerprint: SceneFingerprint.of(scene),
    ),
    sourceCoverage: ledger ?? standardLedger(),
  );

  /// 标准候选 patch：i1/i2 移除、s1 移动、img1 保持比例缩放、新文本。
  SmartLayoutScenePatch standardPatch(
    Scene scene, {
    SourceCoverageLedger? ledger,
    double newTextWidth = 200,
  }) {
    return (builderFor(scene, ledger: ledger)
          ..removeElement('i1', baseVersion: 1, versionNonce: 21)
          ..removeElement('i2', baseVersion: 1, versionNonce: 22)
          ..updateElement(rect('s1', x: 20, version: 2), baseVersion: 1)
          ..updateElement(image('img1', 'file-1', w: 80, h: 80, version: 2), baseVersion: 1)
          ..addElement(text('sl3-t', x: 20, w: newTextWidth, body: '转写正文')))
        .build();
  }

  final page = Bounds.fromLTWH(0, 0, 800, 600);
  final intrinsic = {'file-1': const Size(1, 1)};

  /// 完整真实管线：patch → reducer → renderer → extractor。
  Future<(ReducedScene, DraftRenderSnapshot)> pipeline(
    SmartLayoutScenePatch patch,
  ) async {
    final reduced =
        SmartLayoutSceneReducer.apply(base: baseScene(), patch: patch)
            as ReducedScene;
    final renderer = DraftSceneRenderer();
    final snapshot = await renderer.render(
      scene: reduced.scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(800, 600),
    );
    renderer.dispose();
    return (reduced, snapshot);
  }

  test('真实管线全绿：coverage/关系/序/页界/账本守恒全过', () async {
    final patch = standardPatch(baseScene());
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(report.violations, isEmpty, reason: '${report.violations}');
    expect(report.passed, isTrue);
  });

  test('adversarial：coverage 丢失（账本源无在场证据）fail closed', () async {
    final ghostLedger =
        SourceCoverageLedger.pending(
          const ['s1', 'i1', 'i2', 'img1', 'p1', 'ghost'],
        ).markConsumed(const ['s1', 'i1', 'i2', 'img1', 'ghost']).markPreserved(
          const ['p1'],
        );
    final patch = standardPatch(baseScene(), ledger: ghostLedger);
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: ghostLedger,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: ghostLedger,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.coverageLost),
      reason: 'ghost 无在场证据必须失败',
    );
  });

  test('adversarial：ledger 守恒破坏（preserved 源被 patch 写）', () async {
    final badLedger =
        SourceCoverageLedger.pending(const ['s1', 'i1', 'i2', 'img1', 'p1'])
            .markConsumed(const ['i1', 'i2', 'img1'])
            .markPreserved(const ['s1', 'p1']);
    final patch = standardPatch(baseScene(), ledger: badLedger);
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: badLedger,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: badLedger,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      containsAll([
        HardConstraintKind.ledgerConservation,
        HardConstraintKind.coverageLost,
      ]),
      reason: 's1 被写却标 preserved：守恒破坏且在场判定降级',
    );
  });

  test('adversarial：语义关系破坏（caption 远离 figure）与阅读序逆转', () async {
    final patch = standardPatch(baseScene());
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
        relations: const [
          SemanticRelationExpectation(
            relationId: 'r-cap',
            kind: SemanticRelationExpectationKind.captionOf,
            anchorId: 'img1',
            followerId: 'sl3-t',
          ),
        ],
        readingOrder: const ReadingOrderExpectation(
          // 期望 s1 在 sl3-t 前，但渲染几何 sl3-t(y=5) 高于 s1(y=10)
          // → 相邻对错序。
          orderedElementIds: ['s1', 'sl3-t'],
        ),
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    // sl3-t(墨迹在 y=5) 高于 img1(y=60)：caption 无水平重叠且在其上；
    // 阅读序期望 s1 在 sl3-t 前，实际相反 → 错序。
    expect(
      report.violations.map((v) => v.kind),
      containsAll([
        HardConstraintKind.relation,
        HardConstraintKind.readingOrder,
      ]),
    );
  });

  test('adversarial：裁字（真实墨迹宽于元素盒）', () async {
    // 新文本元素盒仅 30 宽，真实墨迹远宽于盒 → 裁字。
    final patch = standardPatch(baseScene(), newTextWidth: 30);
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.textClipping),
      reason: '墨迹实测宽于 30px 元素盒',
    );
  });

  test('adversarial：图片比例失真（内在 1:1 显示 80:40）', () async {
    final scene = baseScene();
    final patch =
        (builderFor(scene)
              ..removeElement('i1', baseVersion: 1, versionNonce: 21)
              ..updateElement(
                image('img1', 'file-1', w: 80, h: 40, version: 2),
                baseVersion: 1,
              ))
            .build();
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: scene,
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.aspectRatio),
    );
  });

  test('adversarial：非写入元素关系被静默篡改（groupIds 变化）', () async {
    final scene = baseScene();
    final patch = standardPatch(scene);
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    // 篡改基线：p1 在"声称的 base"里有组，而产物中无组——篡改证据。
    final tamperedBase = Scene()
        .addElement(rect('s1'))
        .addElement(ink('i1'))
        .addElement(ink('i2'))
        .addElement(image('img1', 'file-1'))
        .addElement(rect('p1', groups: const ['g9']))
        .addFile('file-1', onePixelPng);
    final report = HardConstraintValidator.validate(
      baseScene: tamperedBase,
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.relationIntegrityTampered),
    );
  });

  test('adversarial：渲染后悬空引用（基线遗留软删 frame 的成员）', () async {
    final scene = baseScene()
        .addElement(
          rect('dead-frame', groups: const []).copyWith(isDeleted: true),
        )
        .addElement(
          RectangleElement(
            id: ElementId('orphan-m'),
            x: 700,
            y: 500,
            width: 20,
            height: 20,
            frameId: 'dead-frame',
            seed: 7,
            versionNonce: 11,
            updated: 1000,
          ),
        );
    final patch =
        (builderFor(scene)
              ..removeElement('i1', baseVersion: 1, versionNonce: 21)
              ..updateElement(rect('s1', x: 20, version: 2), baseVersion: 1))
            .build();
    final reduced =
        SmartLayoutSceneReducer.apply(base: scene, patch: patch)
            as ReducedScene;
    final renderer = DraftSceneRenderer();
    final snapshot = await renderer.render(
      scene: reduced.scene,
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(800, 600),
    );
    renderer.dispose();
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: scene,
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.relationIntegrityDangling),
      reason: 'orphan-m 引用软删 frame，fail closed 即使是基线遗留',
    );
  });

  test('adversarial：页界越出 + metrics 自报不实', () async {
    final scene = baseScene();
    // s1 被移出页内容区。
    final patch =
        (builderFor(scene)
              ..removeElement('i1', baseVersion: 1, versionNonce: 21)
              ..updateElement(rect('s1', x: 5000, version: 2), baseVersion: 1))
            .build();
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    // 提取时不给页界（自报 0），验证时给真页界 → 计数不一致同时暴露。
    final metrics = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: snapshot,
        ledger: reduced.patch.sourceCoverage,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: scene,
      reduced: reduced,
      snapshot: snapshot,
      metrics: metrics,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      containsAll([
        HardConstraintKind.pageBounds,
        HardConstraintKind.metricUnderreport,
      ]),
    );
  });

  test('adversarial：证据链断链（digest 与 revision 不符）', () async {
    final patch = standardPatch(baseScene());
    final (reduced, snapshot) = await pipeline(patch);
    addTearDown(snapshot.dispose);
    // 用另一份渲染（不同场景 → 层几何不同 → digest 不同）冒充。
    final renderer = DraftSceneRenderer();
    final otherSnapshot = await renderer.render(
      scene: baseScene(),
      viewport: const ViewportState(zoom: 1),
      pixelSize: const Size(800, 600),
    );
    renderer.dispose();
    addTearDown(otherSnapshot.dispose);
    final forged = SceneMetricsContract().build(
      ReducedSceneMetricsExtractor.extract(
        reduced: reduced,
        snapshot: otherSnapshot,
        ledger: reduced.patch.sourceCoverage,
        pageContentBounds: page,
      ),
    );
    final report = HardConstraintValidator.validate(
      baseScene: baseScene(),
      reduced: reduced,
      snapshot: snapshot,
      metrics: forged,
      ledger: reduced.patch.sourceCoverage,
      pageContentBounds: page,
      imageIntrinsicSizes: intrinsic,
    );
    expect(
      report.violations.map((v) => v.kind),
      contains(HardConstraintKind.provenance),
      reason: '他份渲染的 digest 冒充必须断链失败',
    );
  });

  test('源码门禁：validation 层零 placement 引用（不读自报）', () {
    final dir = io.Directory('lib/features/whiteboard/smart_layout/validation');
    for (final entity in dir.listSync()) {
      if (entity is! io.File || !entity.path.endsWith('.dart')) continue;
      final source = io.File(entity.path).readAsStringSync();
      expect(
        source.contains('placement/'),
        isFalse,
        reason: '${entity.path} 不得引用 placement 层',
      );
      expect(
        source.contains('flow_placer') ||
            source.contains('balanced_flow_placer') ||
            source.contains('PlacedBlock'),
        isFalse,
        reason: '${entity.path} 不得消费 placement 自报类型',
      );
    }
  });
}
