import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/scene_patch_debug_codec.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_patch_equality.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_patch_validator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RectangleElement rect(String id, {double x = 10, int version = 1}) =>
      RectangleElement(
        id: ElementId(id),
        x: x,
        y: 10,
        width: 40,
        height: 40,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: version,
      );

  ImageFile png(List<int> bytes) =>
      ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList(bytes));

  Scene baseScene() => Scene().addElement(rect('s1')).addElement(rect('s2'));

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(scene),
  );

  SourceCoverageLedger finalizedLedger() => SourceCoverageLedger.pending(const [
    's1',
    's2',
  ]).markConsumed(const ['s1']).markPreserved(const ['s2']);

  SmartLayoutScenePatchBuilder builder({SourceCoverageLedger? ledger}) =>
      SmartLayoutScenePatchBuilder(
        baseScene: baseScene(),
        baseRevision: revisionOf(baseScene()),
        sourceCoverage: ledger ?? finalizedLedger(),
      );

  test('validator：合法 patch 复核通过；账本守恒通过', () {
    final scene = baseScene();
    final patch =
        (builder()
              ..updateElement(rect('s1', x: 99, version: 2), baseVersion: 1))
            .build();
    expect(
      SmartLayoutScenePatchValidator.validate(patch: patch, baseScene: scene),
      isEmpty,
    );
    expect(
      SmartLayoutScenePatchValidator.checkLedgerConservation(patch: patch),
      isEmpty,
    );
  });

  test('validator：base 变化后复核失败（悬空/指纹错配）', () {
    final patch =
        (builder()
              ..updateElement(rect('s1', x: 99, version: 2), baseVersion: 1))
            .build();
    final changedScene = baseScene().addElement(rect('s9'));
    expect(
      SmartLayoutScenePatchValidator.validate(
        patch: patch,
        baseScene: changedScene,
      ),
      isNotEmpty,
      reason: '指纹错配必须被复核捕获',
    );
  });

  test('validator：账本守恒违反——触碰 preserved 源与账本外元素', () {
    // s2 是 preserved 源却被 update 触碰。
    final touchedPreserved =
        (builder()
              ..updateElement(rect('s2', x: 99, version: 2), baseVersion: 1))
            .build();
    expect(
      SmartLayoutScenePatchValidator.checkLedgerConservation(
        patch: touchedPreserved,
      ).map((v) => v.kind),
      [PatchLedgerViolationKind.touchedPreservedSource],
    );

    // 账本外元素（窄账本只含 s1）。
    final narrowLedger = SourceCoverageLedger.pending(const [
      's1',
    ]).markConsumed(const ['s1']);
    final outside = (SmartLayoutScenePatchBuilder(
      baseScene: baseScene(),
      baseRevision: revisionOf(baseScene()),
      sourceCoverage: narrowLedger,
    )..updateElement(rect('s2', x: 99, version: 2), baseVersion: 1)).build();
    expect(
      SmartLayoutScenePatchValidator.checkLedgerConservation(
        patch: outside,
      ).map((v) => v.kind),
      [PatchLedgerViolationKind.touchedOutsideLedger],
    );

    // 未终结账本（pending 源存在时 builder 拒绝，构造层面验证账本本身）。
    final pendingLedger = SourceCoverageLedger.pending(const ['s1']);
    expect(pendingLedger.isFinalized, isFalse);
  });

  test('deep equality：单字段差异逐项可辨，相同输入深度等价', () {
    SmartLayoutScenePatch base() =>
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [1, 2, 3]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 1,
                  blocks: const [],
                  generatedAt: 1000,
                ),
              )
              ..setSelectionIntent(const ['n1']))
            .build();

    final a = base();
    final b = base();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, b), isTrue);

    // 元素负载差异（同 id 不同 x）——Element 按身份 == 相等，负载差异
    // 必须由深度等价捕获。
    final movedAdd =
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 6, version: 1))
              ..addFile('f1', png(const [1, 2, 3]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 1,
                  blocks: const [],
                  generatedAt: 1000,
                ),
              )
              ..setSelectionIntent(const ['n1']))
            .build();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, movedAdd), isFalse);

    // nonce 差异。
    final otherNonce =
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 999)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [1, 2, 3]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 1,
                  blocks: const [],
                  generatedAt: 1000,
                ),
              )
              ..setSelectionIntent(const ['n1']))
            .build();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, otherNonce), isFalse);

    // 文件内容差异。
    final otherFile =
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [1, 2, 4]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 1,
                  blocks: const [],
                  generatedAt: 1000,
                ),
              )
              ..setSelectionIntent(const ['n1']))
            .build();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, otherFile), isFalse);

    // document 差异（replace vs 不触碰）。
    final noDoc =
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [1, 2, 3]))
              ..setSelectionIntent(const ['n1']))
            .build();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, noDoc), isFalse);

    // selection 差异。
    final noSelection =
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [1, 2, 3]))
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 1,
                  blocks: const [],
                  generatedAt: 1000,
                ),
              ))
            .build();
    expect(SmartLayoutScenePatchEquality.deepEquals(a, noSelection), isFalse);
  });

  test('debug codec：双跑逐字节一致、全通道投影、仅诊断标记', () {
    SmartLayoutScenePatch build() =>
        (builder()
              ..removeElement('s1', baseVersion: 1, versionNonce: 101)
              ..addElement(rect('n1', x: 5, version: 1))
              ..addFile('f1', png(const [9, 9]))
              ..clearSmartLayoutDocument()
              ..setSelectionIntent(const []))
            .build();
    final patch = build();
    final encoded = ScenePatchDebugCodec.encode(patch);

    expect(encoded['codec'], 'scene-patch-debug-v1');
    expect(encoded['diagnosticOnly'], isTrue);
    expect(encoded['removes'], hasLength(1));
    expect(encoded['updates'], isEmpty);
    expect(
      (encoded['adds'] as List).first,
      isA<Map>().having((a) => a['element'], 'element', isA<Map>()),
    );
    expect(encoded['fileAdds'], hasLength(1));
    expect((encoded['documentOp'] as Map)['op'], 'clear');
    expect(encoded['selectionIntent'], isEmpty);
    expect((encoded['ledger'] as Map)['counts'], {
      'consumed': 1,
      'preserved': 1,
      'pending': 0,
    });
    expect(encoded['writeSet'], isA<Map>());
    expect(encoded['readSet'], isA<Map>());

    // 双跑：同输入两次构建→两次编码，文本形态逐字节一致。
    expect(
      ScenePatchDebugCodec.encodeToString(build()),
      ScenePatchDebugCodec.encodeToString(patch),
    );
    expect(ScenePatchDebugCodec.encode(build()), encoded);
  });
}
