import 'dart:convert';
import 'dart:io';

import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/geometry/layout_rect.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/anti_gaming_veto.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_calculator.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_metric_contract.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/metrics/layout_profile.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-404A：七类软指标冻结、硬软隔离、三 profile、反投机否决与
/// score 可还原分解。
void main() {
  const calc = LayoutMetricCalculator();
  const vetoDetector = AntiGamingVetoDetector();
  const scorer = LayoutProfileScorer();

  LayoutBlock paraBlock(String id) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.paragraph,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: false,
        textOrigin: LayoutTextOrigin.typed,
        text: const TextBlockSpec(
          text: '正文内容',
          fontFamily: 'Excalifont',
          fontSize: 20,
          lineHeight: 1.25,
        ),
      );

  LayoutBlock titleBlock(String id) => LayoutBlock(
        id: id,
        kind: LayoutBlockKind.title,
        sourceRefs: [id],
        orderIndex: 0,
        keepTogether: false,
        textOrigin: LayoutTextOrigin.typed,
        text: const TextBlockSpec(
          text: '标题',
          fontFamily: 'Excalifont',
          fontSize: 28,
          lineHeight: 1.25,
        ),
      );

  LayoutBlockAssembly assemblyOf(
    List<LayoutBlock> blocks, {
    List<BlockRelationship> relationships = const [],
  }) =>
      LayoutBlockAssembly(
        blocks: List.unmodifiable(blocks),
        relationships: relationships,
        atomicGroups: const [],
        documentConsumedSourceIds: [for (final b in blocks) b.id],
        documentPreservedSourceIds: const [],
      );

  PlacedBlock placed(
    String id,
    LayoutRect rect,
    int column, {
    double font = 20,
  }) =>
      PlacedBlock(
        blockId: id,
        rect: rect,
        columnIndex: column,
        lineCount: 2,
        appliedFontSize: font,
        shrunk: font != 20,
      );

  const columns2 = [
    LayoutRect(left: 0, top: 0, width: 588, height: 800),
    LayoutRect(left: 612, top: 0, width: 588, height: 800),
  ];

  /// 干净基线 fixture：双栏 2+2、等距 24、对齐精确、填充 0.63。
  LayoutMetricInput cleanInput({
    Map<String, LayoutRect>? originals,
    bool hardValidated = true,
  }) =>
      LayoutMetricInput(
        assembly: assemblyOf([paraBlock('a'), paraBlock('b'), paraBlock('c'), paraBlock('d')]),
        placed: [
          placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0),
          placed('b', const LayoutRect(left: 0, top: 264, width: 588, height: 240), 0),
          placed('c', const LayoutRect(left: 612, top: 0, width: 588, height: 240), 1),
          placed('d', const LayoutRect(left: 612, top: 264, width: 588, height: 240), 1),
        ],
        columnRects: columns2,
        preservedRects: const {},
        originalBounds: originals ??
            {
              'a': const LayoutRect(left: 0, top: 500, width: 588, height: 240),
              'b': const LayoutRect(left: 0, top: 0, width: 588, height: 240),
              'c': const LayoutRect(left: 612, top: 500, width: 588, height: 240),
              'd': const LayoutRect(left: 612, top: 0, width: 588, height: 240),
            },
        contentHeight: 800,
        hardValidated: hardValidated,
      );

  test('契约冻结：七类指标、界 [0,1]、向量校验拒绝越界/缺失/多余', () {
    expect(LayoutMetricContract.definitions.length, 7);
    expect(
      LayoutMetricContract.definitions.map((d) => d.id).toSet().length,
      7,
    );
    for (final def in LayoutMetricContract.definitions) {
      expect(def.lowerBound, 0);
      expect(def.upperBound, 1);
    }
    final good = {
      for (final d in LayoutMetricContract.definitions) d.id: 0.5,
    };
    LayoutMetricContract.validateVector(good); // 不抛。
    expect(
      () => LayoutMetricContract.validateVector({
        ...good,
        LayoutMetricId.hierarchy: 1.5,
      }),
      throwsStateError,
    );
    expect(
      () => LayoutMetricContract.validateVector({
        ...good,
        LayoutMetricId.hierarchy: double.nan,
      }),
      throwsStateError,
    );
    expect(
      () => LayoutMetricContract.validateVector({
        for (final d in LayoutMetricContract.definitions)
          if (d.id != LayoutMetricId.hierarchy) d.id: 0.5,
      }),
      throwsStateError,
    );
  });

  test('rubric/evaluationspec 引用不复制：版本与 hash 钉死单一来源', () {
    final rubric = jsonDecode(
      File(
        '../docs/研发记录/evidence/smart-layout-v3/tasks/V3-000B/artifacts/rubric.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(rubric['rubric_version'], LayoutMetricContract.rubricVersion);
    final spec = jsonDecode(
      File('../docs/研发记录/specs/smart-layout-v3/evaluation-spec.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(spec['content_sha256'], LayoutMetricContract.evaluationSpecContentSha256);
  });

  test('硬软隔离：硬未通过不产生软分（软分不能抵消硬失败）', () {
    final outcome = calc.calculate(cleanInput(hardValidated: false));
    expect(outcome, isA<MetricsHardRejected>());
  }, skip: false);

  test('干净 fixture：七类指标全在界内且方向正确；双跑确定', () {
    final first = calc.calculate(cleanInput());
    expect(first, isA<LayoutMetricVector>());
    final v = first as LayoutMetricVector;
    for (final def in LayoutMetricContract.definitions) {
      expect(v.values[def.id], inInclusiveRange(0, 1), reason: def.id.name);
    }
    expect(v.values[LayoutMetricId.readingOrder], 1.0);
    expect(v.values[LayoutMetricId.alignmentRhythm], 1.0);
    expect(v.values[LayoutMetricId.visualBalance], 1.0);
    expect(v.values[LayoutMetricId.densityWhitespace], 1.0);
    // 层级/亲和：无 title/无 captionOf 关系 → 中性 1.0。
    expect(v.values[LayoutMetricId.hierarchy], 1.0);
    expect(v.values[LayoutMetricId.figureTextAffinity], 1.0);
    // 改动成本：块确有移动 → < 1。
    expect(v.values[LayoutMetricId.modificationCost], lessThan(1.0));

    final second = calc.calculate(cleanInput()) as LayoutMetricVector;
    expect(second.factsFingerprint, v.factsFingerprint);
    expect(second.values, v.values);
  });

  test('单调性：移动越远改动成本越低；栏失衡视觉平衡越低', () {
    final near = (calc.calculate(cleanInput(
      originals: {
        'a': const LayoutRect(left: 0, top: 20, width: 588, height: 240),
        'b': const LayoutRect(left: 0, top: 244, width: 588, height: 240),
        'c': const LayoutRect(left: 612, top: 20, width: 588, height: 240),
        'd': const LayoutRect(left: 612, top: 244, width: 588, height: 240),
      },
    )) as LayoutMetricVector)
        .values[LayoutMetricId.modificationCost]!;
    final far = (calc.calculate(cleanInput()) as LayoutMetricVector)
        .values[LayoutMetricId.modificationCost]!;
    expect(near, greaterThan(far));

    final balanced = (calc.calculate(cleanInput()) as LayoutMetricVector)
        .values[LayoutMetricId.visualBalance]!;
    final unbalanced = (calc.calculate(LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b'), paraBlock('c')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 224), 0),
        placed('b', const LayoutRect(left: 0, top: 248, width: 588, height: 224), 0),
        placed('c', const LayoutRect(left: 0, top: 472, width: 588, height: 224), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    )) as LayoutMetricVector)
        .values[LayoutMetricId.visualBalance]!;
    expect(unbalanced, lessThan(balanced));
  });

  test('层级与图文亲和：违规降分', () {
    // title 被缩到 12（< 正文 20 中位）→ 层级 0。
    final flatTitle = LayoutMetricInput(
      assembly: assemblyOf([titleBlock('t'), paraBlock('a')]),
      placed: [
        placed('t', const LayoutRect(left: 0, top: 0, width: 588, height: 15), 0, font: 12),
        placed('a', const LayoutRect(left: 0, top: 39, width: 588, height: 200), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    final flat = (calc.calculate(flatTitle) as LayoutMetricVector)
        .values[LayoutMetricId.hierarchy]!;
    expect(flat, 0.0);

    // captionOf 关系对跨栏 → 亲和 0；同栏紧贴 → 1。
    final fig = LayoutBlock(
      id: 'fig',
      kind: LayoutBlockKind.figure,
      sourceRefs: const ['fig'],
      orderIndex: 0,
      keepTogether: true,
      figure: const FigureBlockSpec(fileId: 'f', displayAspectRatio: 2.0),
    );
    final cap = paraBlock('cap');
    final relation = const BlockRelationship(
      kind: BlockRelationKind.captionOf,
      fromBlockId: 'cap',
      toBlockId: 'fig',
    );
    LayoutMetricInput affinityInput({required int capColumn}) =>
        LayoutMetricInput(
          assembly: assemblyOf([fig, cap], relationships: [relation]),
          placed: [
            placed('fig', const LayoutRect(left: 612, top: 0, width: 588, height: 294), 1),
            placed('cap', LayoutRect(left: capColumn == 1 ? 612 : 0, top: 318, width: 588, height: 25), capColumn),
          ],
          columnRects: columns2,
          preservedRects: const {},
          originalBounds: const {},
          contentHeight: 800,
          hardValidated: true,
        );
    final ok = (calc.calculate(affinityInput(capColumn: 1)) as LayoutMetricVector)
        .values[LayoutMetricId.figureTextAffinity]!;
    final split = (calc.calculate(affinityInput(capColumn: 0)) as LayoutMetricVector)
        .values[LayoutMetricId.figureTextAffinity]!;
    expect(ok, 1.0);
    expect(split, 0.0);
  });

  test('顺序：相邻放置对逆序降分', () {
    final outcome = calc.calculate(LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b')]),
      placed: [
        placed('b', const LayoutRect(left: 0, top: 264, width: 588, height: 240), 0),
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    ));
    expect(
      (outcome as LayoutMetricVector).values[LayoutMetricId.readingOrder],
      0.0,
    );
  });

  test('反投机：六类投机 fixture 全否决，干净 fixture 零否决', () {
    // 干净基线。
    final cleanVector = calc.calculate(cleanInput()) as LayoutMetricVector;
    final cleanVeto = vetoDetector.evaluate(cleanInput(), claimedVector: cleanVector);
    expect(cleanVeto.vetoed, isFalse, reason: cleanVeto.reasons.join(';'));

    // no-op：全部块与原位重合。
    final noOpInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0),
        placed('b', const LayoutRect(left: 0, top: 264, width: 588, height: 240), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {
        'a': LayoutRect(left: 0, top: 0, width: 588, height: 240),
        'b': LayoutRect(left: 0, top: 264, width: 588, height: 240),
      },
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(noOpInput).kinds,
      contains(AntiGamingVetoKind.noOp),
    );

    // 极缩：全部文本块最小字号。
    final shrinkInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0, font: 12),
        placed('b', const LayoutRect(left: 0, top: 264, width: 588, height: 240), 0, font: 12),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(shrinkInput).kinds,
      contains(AntiGamingVetoKind.extremeShrink),
    );

    // 隐藏：文本盒被压到 10（< 15 下限）。
    final hiddenInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 10), 0),
        placed('b', const LayoutRect(left: 0, top: 34, width: 588, height: 240), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(hiddenInput).kinds,
      contains(AntiGamingVetoKind.hiddenText),
    );

    // 大留白（投机口径）：内容体量本可达下限（4×60/800=0.30 ≥ 0.20）
    // 却被挤在两栏顶部（填充 144/800≈0.18）——布局浪费，否决。
    final blankInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b'), paraBlock('c'), paraBlock('d')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 60), 0),
        placed('b', const LayoutRect(left: 0, top: 84, width: 588, height: 60), 0),
        placed('c', const LayoutRect(left: 612, top: 0, width: 588, height: 60), 1),
        placed('d', const LayoutRect(left: 612, top: 84, width: 588, height: 60), 1),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(blankInput).kinds,
      contains(AntiGamingVetoKind.excessiveWhitespace),
    );

    // 大留白（稀疏豁免）：内容体量天然达不到下限（4×20/800=0.10 <
    // 0.20，任何排列都填不满页面）——留白是内容体量的诚实结果而非
    // 投机，不否决（真实稀疏手写转写页口径）。
    final sparseInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b'), paraBlock('c'), paraBlock('d')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 20), 0),
        placed('b', const LayoutRect(left: 0, top: 44, width: 588, height: 20), 0),
        placed('c', const LayoutRect(left: 612, top: 0, width: 588, height: 20), 1),
        placed('d', const LayoutRect(left: 612, top: 44, width: 588, height: 20), 1),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(sparseInput).kinds,
      isNot(contains(AntiGamingVetoKind.excessiveWhitespace)),
    );

    // 重复：两个块占完全相同盒。
    final dupInput = LayoutMetricInput(
      assembly: assemblyOf([paraBlock('a'), paraBlock('b')]),
      placed: [
        placed('a', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0),
        placed('b', const LayoutRect(left: 0, top: 0, width: 588, height: 240), 0),
      ],
      columnRects: columns2,
      preservedRects: const {},
      originalBounds: const {},
      contentHeight: 800,
      hardValidated: true,
    );
    expect(
      vetoDetector.evaluate(dupInput).kinds,
      contains(AntiGamingVetoKind.duplicateContent),
    );

    // 成本造假：事实大幅移动，宣称向量 cost=0.999。
    final movedInput = cleanInput();
    final forged = LayoutMetricVector(
      values: {
        for (final d in LayoutMetricContract.definitions)
          d.id: d.id == LayoutMetricId.modificationCost ? 0.999 : 0.5,
      },
      factsFingerprint: 'forged',
    );
    expect(
      vetoDetector.evaluate(movedInput, claimedVector: forged).kinds,
      contains(AntiGamingVetoKind.costFraud),
    );

    // 否决候选在三个 profile 下都不能进入排序（Top 3）。
    for (final gaming in [noOpInput, shrinkInput, hiddenInput, blankInput, dupInput]) {
      final vector = calc.calculate(gaming) as LayoutMetricVector;
      final verdict = vetoDetector.evaluate(gaming, claimedVector: vector);
      for (final profile in LayoutProfile.all) {
        final ranked = scorer.rank(profile, vector, verdict);
        expect(ranked, isA<ProfileGamingRejected>(),
            reason: '${profile.id} 必须拒绝投机样本');
      }
    }
  });

  test('score 可还原：分解贡献之和 == score；权重和恒 1', () {
    for (final profile in LayoutProfile.all) {
      expect(
        profile.weights.values.reduce((a, b) => a + b),
        closeTo(1.0, 1e-12),
        reason: profile.id.name,
      );
    }
    final vector = calc.calculate(cleanInput()) as LayoutMetricVector;
    final score = scorer.rank(LayoutProfile.readability, vector, const VetoVerdict(kinds: [], reasons: []))
        as ProfileScore;
    expect(score.entries.length, 7);
    var sum = 0.0;
    for (final e in score.entries) {
      expect(e.contribution, closeTo(e.value * e.weight, 1e-15));
      sum += e.contribution;
    }
    expect(score.score, closeTo(sum, 1e-12));
    expect(score.factsFingerprint, vector.factsFingerprint);
  });

  test('三 profile 共用同一向量：排序偏好翻转', () {
    double metricValue(LayoutMetricId id, bool a) => switch (id) {
          LayoutMetricId.hierarchy => a ? 0.4 : 0.9,
          LayoutMetricId.modificationCost => a ? 1.0 : 0.3,
          _ => 0.5,
        };
    LayoutMetricVector vector(bool a) => LayoutMetricVector(
          values: {
            for (final d in LayoutMetricContract.definitions)
              d.id: metricValue(d.id, a),
          },
          factsFingerprint: a ? 'pair-A' : 'pair-B',
        );
    final a = vector(true);
    final b = vector(false);
    double scoreOf(LayoutProfile p, LayoutMetricVector v) =>
        (scorer.rank(p, v, const VetoVerdict(kinds: [], reasons: [])) as ProfileScore)
            .score;
    // 可读性偏好层级 → B 胜；保留原结构偏好改动成本 → A 胜。
    expect(scoreOf(LayoutProfile.readability, b), greaterThan(scoreOf(LayoutProfile.readability, a)));
    expect(
      scoreOf(LayoutProfile.structurePreservation, a),
      greaterThan(scoreOf(LayoutProfile.structurePreservation, b)),
    );
  });
}
