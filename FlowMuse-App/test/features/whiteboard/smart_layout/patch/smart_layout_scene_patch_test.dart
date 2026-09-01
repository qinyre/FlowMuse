import 'dart:typed_data';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/patch_invariant.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 全部 fixture 显式 seed/versionNonce/updated，保证构建双跑确定。
  RectangleElement rect(
    String id, {
    double x = 10,
    int version = 1,
    bool deleted = false,
    String? frameId,
    List<BoundElement> boundElements = const [],
  }) => RectangleElement(
    id: ElementId(id),
    x: x,
    y: 10,
    width: 40,
    height: 40,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: version,
    isDeleted: deleted,
    frameId: frameId,
    boundElements: boundElements,
  );

  TextElement text(
    String id, {
    String body = '文本',
    int version = 1,
    String? containerId,
  }) => TextElement(
    id: ElementId(id),
    x: 5,
    y: 5,
    width: 30,
    height: 20,
    text: body,
    seed: 7,
    versionNonce: 11,
    updated: 1000,
    version: version,
    containerId: containerId,
  );

  ImageFile png(List<int> bytes) =>
      ImageFile(mimeType: 'image/png', bytes: Uint8List.fromList(bytes));

  SourceCoverageLedger finalizedLedger() => SourceCoverageLedger.pending(const [
    's1',
    't1',
  ]).markConsumed(const ['t1']).markPreserved(const ['s1']);

  // base：s1(v1 容器)、ar1(v1 箭头目标)、t1(v1 绑定文本)、d1(软删)。
  Scene baseScene() => Scene()
      .addElement(rect('s1'))
      .addElement(rect('ar1'))
      .addElement(text('t1', containerId: 's1'))
      .addElement(rect('d1', deleted: true));

  SceneRevision revisionOf(Scene scene) => SceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: SceneFingerprint.of(scene),
  );

  SmartLayoutScenePatchBuilder builderWith({SourceCoverageLedger? ledger}) =>
      SmartLayoutScenePatchBuilder(
        baseScene: baseScene(),
        baseRevision: revisionOf(baseScene()),
        sourceCoverage: ledger ?? finalizedLedger(),
      );

  test('全量操作构建成功：规范排序、固定应用序与读写集精确', () {
    final scene = baseScene();
    final builder =
        SmartLayoutScenePatchBuilder(
            baseScene: scene,
            baseRevision: revisionOf(scene),
            sourceCoverage: finalizedLedger(),
          )
          ..removeElement('t1', baseVersion: 1, versionNonce: 101)
          ..updateElement(rect('s1', x: 99, version: 2), baseVersion: 1)
          ..addElement(text('n1', containerId: 's1', version: 1))
          ..addElement(
            rect(
              'a1',
              version: 1,
              boundElements: [BoundElement(id: 'ar1', type: 'arrow')],
            ),
          )
          ..addFile('img1', png(const [1, 2, 3]))
          ..replaceSmartLayoutDocument(
            SmartLayoutDocument(
              version: 1,
              blocks: const [],
              generatedAt: 1000,
            ),
          )
          ..setSelectionIntent(const ['s1', 'n1']);

    final patch = builder.build();

    expect(patch.removes.map((o) => o.elementId), ['t1']);
    expect(patch.updates.map((o) => o.elementId), ['s1']);
    expect(patch.adds.map((o) => o.elementId), [
      'a1',
      'n1',
    ], reason: 'adds 按 id 排序');
    expect(patch.fileAdds.map((o) => o.fileId), ['img1']);
    expect(patch.documentOp!.clears, isFalse);
    expect(patch.selectionIntent, ['n1', 's1']);

    // remove 的 version delta 由构建器推导。
    expect(patch.removes.single.newVersion, 2);

    // 写集 = 全部副作用。
    final write = patch.writeSet;
    expect(write.elementIds, ['a1', 'n1', 's1', 't1']);
    expect(write.fileIds, ['img1']);
    expect(write.touchesDocument, isTrue);
    expect(write.touchesSelection, isTrue);
    expect(write.isEmpty, isFalse);

    // 读集 = update/remove 目标 + 指向 base 的关系引用
    //（n1.containerId=s1 已被本 patch 写、a1.boundElements→ar1 是 base 读）。
    expect(patch.readSet.elementIds, ['ar1', 's1', 't1']);

    // 固定应用序：remove → update → add。
    final kinds = patch.elementOps.map((op) {
      if (op is ScenePatchElementRemove) return 'remove';
      if (op is ScenePatchElementUpdate) return 'update';
      return 'add';
    }).toList();
    expect(kinds, ['remove', 'update', 'add', 'add']);
  });

  test('构建结果不可变：列表与选择意图不可再改', () {
    final patch =
        (builderWith()
              ..removeElement('t1', baseVersion: 1, versionNonce: 101)
              ..setSelectionIntent(const ['s1']))
            .build();
    expect(
      () => patch.removes.add(
        const ScenePatchElementRemove(
          elementId: 'x',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ),
      throwsUnsupportedError,
    );
    expect(() => patch.selectionIntent!.add('x'), throwsUnsupportedError);
  });

  test('builder 可多次 build 且结果一致', () {
    final builder = builderWith()
      ..removeElement('t1', baseVersion: 1, versionNonce: 101);
    final a = builder.build();
    final b = builder.build();
    expect(identical(a, b), isFalse);
    expect(a.writeSet.elementIds, b.writeSet.elementIds);
    expect(a.removes.first.versionNonce, b.removes.first.versionNonce);
  });

  test('写集相交判定：元素/文件 id 重叠与 document/selection 通道', () {
    final left = builderWith()
      ..removeElement('t1', baseVersion: 1, versionNonce: 101)
      ..addElement(rect('newL', version: 1))
      ..addFile('fL', png(const [1]));
    final leftPatch = left.build();

    // 元素 id 重叠（t1）。
    final elementOverlap =
        (builderWith()
              ..updateElement(
                text('t1', containerId: 's1', version: 2),
                baseVersion: 1,
              ))
            .build();
    expect(
      leftPatch.writeSet.intersects(elementOverlap.writeSet),
      isTrue,
      reason: 't1 同时被两个 patch 触碰',
    );

    // 元素不相交但文件 id 重叠。
    final fileOverlap =
        (builderWith()
              ..updateElement(rect('ar1', version: 2), baseVersion: 1)
              ..addFile('fL', png(const [9])))
            .build();
    expect(
      leftPatch.writeSet.intersects(fileOverlap.writeSet),
      isTrue,
      reason: '文件 fL 同时被两个 patch 触碰',
    );

    // document/selection 同通道。
    final docTouch =
        (builderWith()
              ..removeElement('ar1', baseVersion: 1, versionNonce: 1)
              ..clearSmartLayoutDocument())
            .build();
    final docTouch2 =
        (builderWith()
              ..removeElement('s1', baseVersion: 1, versionNonce: 1)
              ..updateElement(text('t1', version: 2), baseVersion: 1)
              ..replaceSmartLayoutDocument(
                SmartLayoutDocument(
                  version: 2,
                  blocks: const [],
                  generatedAt: 2000,
                ),
              ))
            .build();
    expect(docTouch.writeSet.intersects(docTouch2.writeSet), isTrue);

    final selectionTouch =
        (builderWith()
              ..removeElement('ar1', baseVersion: 1, versionNonce: 1)
              ..setSelectionIntent(const ['s1']))
            .build();
    final selectionTouch2 =
        (builderWith()
              ..removeElement('s1', baseVersion: 1, versionNonce: 2)
              ..updateElement(text('t1', version: 2), baseVersion: 1)
              ..setSelectionIntent(const []))
            .build();
    expect(
      selectionTouch.writeSet.intersects(selectionTouch2.writeSet),
      isTrue,
      reason: 's1 重叠 + 双方都触碰选择通道',
    );

    // 完全不相交：元素/文件各异、不触碰 document/selection。
    final disjoint =
        (builderWith()..updateElement(rect('ar1', version: 2), baseVersion: 1))
            .build();
    expect(leftPatch.writeSet.intersects(disjoint.writeSet), isFalse);
  });

  test('悬空与冲突操作拒绝：dangling add/update/remove 与重复操作', () {
    final base = baseScene();
    final revision = revisionOf(base);
    final ledger = finalizedLedger();

    Set<PatchInvariantViolationKind> kindsOf({
      List<ScenePatchElementRemove> removes = const [],
      List<ScenePatchElementUpdate> updates = const [],
      List<ScenePatchElementAdd> adds = const [],
    }) => PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: removes,
      updates: updates,
      adds: adds,
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    ).map((v) => v.kind).toSet();

    expect(
      kindsOf(adds: [ScenePatchElementAdd(element: rect('s1', version: 1))]),
      {PatchInvariantViolationKind.addConflictsWithBase},
    );
    expect(
      kindsOf(
        updates: [
          ScenePatchElementUpdate(
            element: rect('ghost', version: 2),
            baseVersion: 1,
          ),
        ],
      ),
      {PatchInvariantViolationKind.updateDangling},
    );
    expect(
      kindsOf(
        removes: [
          ScenePatchElementRemove(
            elementId: 'ghost',
            baseVersion: 1,
            newVersion: 2,
            versionNonce: 1,
          ),
        ],
      ),
      {PatchInvariantViolationKind.removeDangling},
    );
    // 同一 id 双操作（add + update）。
    expect(
      kindsOf(
        adds: [ScenePatchElementAdd(element: rect('n1', version: 1))],
        updates: [
          ScenePatchElementUpdate(
            element: rect('n1', version: 2),
            baseVersion: 1,
          ),
        ],
      ),
      contains(PatchInvariantViolationKind.duplicateElementOp),
    );
  });

  test('version 契约：baseVersion 匹配、add=1、update/remove delta=+1', () {
    final base = baseScene();
    final revision = revisionOf(base);
    final ledger = finalizedLedger();

    Set<PatchInvariantViolationKind> kindsOf({
      List<ScenePatchElementRemove> removes = const [],
      List<ScenePatchElementUpdate> updates = const [],
      List<ScenePatchElementAdd> adds = const [],
    }) => PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: removes,
      updates: updates,
      adds: adds,
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    ).map((v) => v.kind).toSet();

    // add version != 1。
    expect(
      kindsOf(adds: [ScenePatchElementAdd(element: rect('n1', version: 2))]),
      {PatchInvariantViolationKind.addVersionNotOne},
    );
    // add 携带软删标记。
    expect(
      kindsOf(
        adds: [
          ScenePatchElementAdd(element: rect('n1', version: 1, deleted: true)),
        ],
      ),
      {PatchInvariantViolationKind.addElementSoftDeleted},
    );
    // baseVersion 不匹配（s1 实际 v1）且 delta 同步破坏（5 != 2+1）。
    expect(
      kindsOf(
        updates: [
          ScenePatchElementUpdate(
            element: rect('s1', version: 5),
            baseVersion: 2,
          ),
        ],
      ),
      containsAll([
        PatchInvariantViolationKind.baseVersionMismatch,
        PatchInvariantViolationKind.updateVersionDelta,
      ]),
    );
    // update version delta != +1。
    expect(
      kindsOf(
        updates: [
          ScenePatchElementUpdate(
            element: rect('s1', version: 5),
            baseVersion: 1,
          ),
        ],
      ),
      {PatchInvariantViolationKind.updateVersionDelta},
    );
    // remove version delta != +1（绕过构建器直接构造）。
    expect(
      kindsOf(
        removes: [
          ScenePatchElementRemove(
            elementId: 't1',
            baseVersion: 1,
            newVersion: 9,
            versionNonce: 1,
          ),
        ],
      ),
      {PatchInvariantViolationKind.removeVersionDelta},
    );
    // 软删目标。
    expect(
      kindsOf(
        removes: [
          ScenePatchElementRemove(
            elementId: 'd1',
            baseVersion: 1,
            newVersion: 2,
            versionNonce: 1,
          ),
        ],
      ),
      {PatchInvariantViolationKind.opTargetsSoftDeleted},
    );
  });

  test('关系完整性：悬空 frameId/containerId/boundElements 拒绝，patch 内自洽通过', () {
    final base = baseScene();
    final revision = revisionOf(base);
    final ledger = finalizedLedger();

    // update 指向不存在 frame。
    final danglingFrame = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: const [],
      updates: [
        ScenePatchElementUpdate(
          element: rect('s1', version: 2, frameId: 'fX'),
          baseVersion: 1,
        ),
      ],
      adds: const [],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(danglingFrame.map((v) => v.kind), [
      PatchInvariantViolationKind.relationDangling,
    ], reason: danglingFrame.toString());

    // 新元素的 containerId 指向被 remove 的 t1。
    final refRemoved = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: [
        ScenePatchElementRemove(
          elementId: 't1',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: const [],
      adds: [
        ScenePatchElementAdd(
          element: text('n1', containerId: 't1', version: 1),
        ),
      ],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(refRemoved.map((v) => v.kind), [
      PatchInvariantViolationKind.relationDangling,
    ]);

    // 新元素互引（containerId 指向另一新增元素）：patch 内自洽，通过。
    final selfContained = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: const [],
      updates: const [],
      adds: [
        ScenePatchElementAdd(
          element: text('n1', containerId: 'n0', version: 1),
        ),
        ScenePatchElementAdd(element: rect('n0', version: 1)),
      ],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(selfContained, isEmpty);
  });

  test('反向悬空：remove 容器必须同时处理引用它的绑定文本', () {
    final base = baseScene();
    final revision = revisionOf(base);
    final ledger = finalizedLedger();

    List<PatchInvariantViolation> checkWith({required bool handleBoundText}) =>
        PatchInvariant.check(
          baseScene: base,
          baseRevision: revision,
          sourceCoverage: ledger,
          removes: [
            ScenePatchElementRemove(
              elementId: 's1',
              baseVersion: 1,
              newVersion: 2,
              versionNonce: 1,
            ),
          ],
          updates: handleBoundText
              ? [
                  ScenePatchElementUpdate(
                    element: text('t1', version: 2),
                    baseVersion: 1,
                  ),
                ]
              : const [],
          adds: const [],
          fileAdds: const [],
          documentOp: null,
          selectionIntent: null,
        );

    expect(
      checkWith(handleBoundText: false).map((v) => v.kind),
      [PatchInvariantViolationKind.reverseRelationDangling],
      reason: 't1.containerId 指向被删的 s1 且 t1 未被处理',
    );
    expect(checkWith(handleBoundText: true), isEmpty);
  });

  test('baseRevision 指纹错配与未终结账本拒绝', () {
    final base = baseScene();
    final other = base.addElement(rect('zz', version: 1));
    final staleRevision = SceneRevision(
      epoch: 0,
      revision: 9,
      fingerprint: SceneFingerprint.of(other),
    );

    final mismatch = PatchInvariant.check(
      baseScene: base,
      baseRevision: staleRevision,
      sourceCoverage: finalizedLedger(),
      removes: [
        ScenePatchElementRemove(
          elementId: 't1',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: const [],
      adds: const [],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(mismatch.map((v) => v.kind), [
      PatchInvariantViolationKind.baseRevisionFingerprintMismatch,
    ]);

    // 未终结账本（有 pending）。
    final pendingLedger = SourceCoverageLedger.pending(const ['s1', 't1']);
    final pending = PatchInvariant.check(
      baseScene: base,
      baseRevision: revisionOf(base),
      sourceCoverage: pendingLedger,
      removes: [
        ScenePatchElementRemove(
          elementId: 't1',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: const [],
      adds: const [],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(pending.map((v) => v.kind), [
      PatchInvariantViolationKind.ledgerNotFinalized,
    ]);

    // builder 集成路径：StateError 携带全部违反项。
    expect(
      () =>
          (SmartLayoutScenePatchBuilder(
            baseScene: base,
            baseRevision: staleRevision,
            sourceCoverage: pendingLedger,
          )..removeElement('t1', baseVersion: 1, versionNonce: 1))
              .build(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('baseRevisionFingerprintMismatch'),
            contains('ledgerNotFinalized'),
          ),
        ),
      ),
    );
  });

  test('零副作用 patch 与悬空 selection/fileAdd 拒绝', () {
    final base = baseScene();
    final revision = revisionOf(base);
    final ledger = finalizedLedger();

    final empty = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: const [],
      updates: const [],
      adds: const [],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(empty.map((v) => v.kind), [
      PatchInvariantViolationKind.emptyWriteSet,
    ]);

    // selection 引用应用后不存在的元素。
    final selection = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: [
        ScenePatchElementRemove(
          elementId: 't1',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: const [],
      adds: const [],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: const ['t1', 'ghost'],
    );
    expect(
      selection.map((v) => v.kind),
      contains(PatchInvariantViolationKind.selectionDangling),
    );

    // fileId 与 base 冲突 + 重复 fileAdd。
    final files = PatchInvariant.check(
      baseScene: base,
      baseRevision: revision,
      sourceCoverage: ledger,
      removes: const [],
      updates: const [],
      adds: const [],
      fileAdds: [
        ScenePatchFileAdd(fileId: 'dup', file: png(const [1])),
        ScenePatchFileAdd(fileId: 'dup', file: png(const [2])),
      ],
      documentOp: null,
      selectionIntent: null,
    );
    expect(files.map((v) => v.kind).toSet(), {
      PatchInvariantViolationKind.duplicateFileAdd,
    });

    // 空选择意图 = 清空选择，本身合法（配合至少一个副作用）。
    final clearSelection =
        (builderWith()
              ..removeElement('t1', baseVersion: 1, versionNonce: 1)
              ..setSelectionIntent(const []))
            .build();
    expect(clearSelection.selectionIntent, isEmpty);
    expect(clearSelection.writeSet.touchesSelection, isTrue);
  });

  test('违反项全量收集且确定性排序（类型序→subjectId→detail）', () {
    final base = baseScene();
    final violations = PatchInvariant.check(
      baseScene: base,
      baseRevision: revisionOf(base),
      sourceCoverage: SourceCoverageLedger.pending(const ['s1']),
      removes: [
        ScenePatchElementRemove(
          elementId: 'ghost',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: [
        ScenePatchElementUpdate(
          element: rect('s1', version: 9, frameId: 'fX'),
          baseVersion: 7,
        ),
      ],
      adds: [ScenePatchElementAdd(element: rect('n1', version: 3))],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    final kinds = violations.map((v) => v.kind.index).toList();
    expect(kinds, equals(kinds.toList()..sort()), reason: '按类型序稳定排序');
    expect(violations.length, greaterThanOrEqualTo(6));
    // 双跑逐字节一致。
    final again = PatchInvariant.check(
      baseScene: base,
      baseRevision: revisionOf(base),
      sourceCoverage: SourceCoverageLedger.pending(const ['s1']),
      removes: [
        ScenePatchElementRemove(
          elementId: 'ghost',
          baseVersion: 1,
          newVersion: 2,
          versionNonce: 1,
        ),
      ],
      updates: [
        ScenePatchElementUpdate(
          element: rect('s1', version: 9, frameId: 'fX'),
          baseVersion: 7,
        ),
      ],
      adds: [ScenePatchElementAdd(element: rect('n1', version: 3))],
      fileAdds: const [],
      documentOp: null,
      selectionIntent: null,
    );
    expect(
      again.map((v) => v.toString()).toList(),
      violations.map((v) => v.toString()).toList(),
    );
  });
}
