import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';

import 'structure_test_helpers.dart';

/// §6.4-2 物化后置检查：删除源 ⊆ 已批准替换集合（识别账本 consume 且
/// 七条件通过）；保留源未被删除或修改。
void main() {
  const adapter = RecognitionSemanticAdapter();

  SourceGuardFacts inkGuard({bool locked = false, bool binding = false}) =>
      SourceGuardFacts(
        isReplaceableInk: !locked && !binding,
        isLocked: locked,
        hasCrossBinding: binding,
      );

  test('正例：已消费且准入通过的源可删除，无违规', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '可替换正文'),
    ]);
    final settled = adapter.settle(result);
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: const {
        'ink:r:a': ReplacementUnitFacts(
          unitId: 'ink:r:a',
          text: '可替换正文',
          regionTargetSourceIds: {'s-a'},
          sourceGuards: {'s-a': SourceGuardFacts(isReplaceableInk: true, isLocked: false, hasCrossBinding: false)},
        ),
      },
      deletedSourceIds: const ['s-a'],
      modifiedSourceIds: const [],
    );
    expect(violations, isEmpty);
  });

  test('删除识别账本保留的源 → deletedPreserved', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
      RegionSpec(regionId: 'r:miss', top: 50, left: 0),
    ]);
    final settled = adapter.settle(result);
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: const {},
      deletedSourceIds: const ['s-miss'],
      modifiedSourceIds: const [],
    );
    expect(
      violations.map((v) => v.kind),
      contains(ReplacementViolation.deletedPreserved),
    );
    expect(violations.first.sourceId, 's-miss');
  });

  test('删除未结算/未消费的源 → deletedNotConsumed', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final settled = adapter.settle(result);
    // s-unknown 不在任何终态（伪造 pending 账本行不可得，用未知 id 模拟
    // 未消费路径：账本投影无 consume 记录）。
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: const {},
      deletedSourceIds: const ['s-unknown'],
      modifiedSourceIds: const [],
    );
    expect(
      violations.map((v) => v.kind),
      contains(ReplacementViolation.deletedNotConsumed),
    );
  });

  test('删除源准入失败（纯标点正文）→ admissionFailed', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '。！！'),
    ]);
    final settled = adapter.settle(result);
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: const {
        'ink:r:a': ReplacementUnitFacts(
          unitId: 'ink:r:a',
          text: '。！！',
          regionTargetSourceIds: {'s-a'},
          sourceGuards: {'s-a': SourceGuardFacts(isReplaceableInk: true, isLocked: false, hasCrossBinding: false)},
        ),
      },
      deletedSourceIds: const ['s-a'],
      modifiedSourceIds: const [],
    );
    expect(
      violations.map((v) => v.kind),
      contains(ReplacementViolation.admissionFailed),
      reason: '条件 2：trim 后非空、非纯标点',
    );
  });

  test('删除源准入失败（锁定笔迹）→ admissionFailed', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
    ]);
    final settled = adapter.settle(result);
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: {
        'ink:r:a': ReplacementUnitFacts(
          unitId: 'ink:r:a',
          text: '正文',
          regionTargetSourceIds: const {'s-a'},
          sourceGuards: {'s-a': inkGuard(locked: true)},
        ),
      },
      deletedSourceIds: const ['s-a'],
      modifiedSourceIds: const [],
    );
    expect(
      violations.map((v) => v.kind),
      contains(ReplacementViolation.admissionFailed),
      reason: '条件 5：锁定源禁止进入删除集合',
    );
  });

  test('保留源被修改 → preservedTouched', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '正文'),
      RegionSpec(regionId: 'r:miss', top: 50, left: 0),
    ]);
    final settled = adapter.settle(result);
    final violations = ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: const {
        'ink:r:a': ReplacementUnitFacts(
          unitId: 'ink:r:a',
          text: '正文',
          regionTargetSourceIds: {'s-a'},
          sourceGuards: {'s-a': SourceGuardFacts(isReplaceableInk: true, isLocked: false, hasCrossBinding: false)},
        ),
      },
      deletedSourceIds: const ['s-a'],
      modifiedSourceIds: const ['s-miss'],
    );
    expect(
      violations.map((v) => v.kind),
      contains(ReplacementViolation.preservedTouched),
      reason: '保留源不得被删除或修改',
    );
  });
}
