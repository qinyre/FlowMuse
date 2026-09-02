import '../composition/layout_block.dart';
import '../composition/layout_block_assembler.dart';
import '../geometry/layout_rect.dart';
import '../placement/flow_placer.dart';

/// 七类软指标稳定标识（V3-404A 冻结；层级/顺序/图文亲和/对齐节奏/
/// 密度留白/视觉平衡/改动成本）。方向统一：**值越大越好**，全部
/// 有界 [0,1]；任何硬约束失败都不产生软分（硬软隔离）。
enum LayoutMetricId {
  hierarchy,
  readingOrder,
  figureTextAffinity,
  alignmentRhythm,
  densityWhitespace,
  visualBalance,
  modificationCost,
}

/// 单指标冻结定义（v1）。
class LayoutMetricDefinition {
  const LayoutMetricDefinition({
    required this.id,
    required this.name,
    required this.lowerBound,
    required this.upperBound,
  });

  final LayoutMetricId id;

  /// 中文名（仅审计展示；排序/判定只用 id 与数值）。
  final String name;
  final double lowerBound;
  final double upperBound;
}

/// 软指标契约（V3-404A）：七类指标的唯一权威定义与校验。
///
/// 溯源（引用不复制——版本变化由测试钉死，单一来源在 Gate 0 工件）：
/// - rubric 维度 D5「布局质量」，rubric_version [rubricVersion]；
/// - EvaluationSpec [evaluationSpecContentSha256]（score 相关性门禁的
///   预注册母本）。
class LayoutMetricContract {
  const LayoutMetricContract._();

  /// 契约版本（增删指标或改定义必须升版）。
  static const String version = 'v1';

  /// Gate 0 冻结 rubric 版本（唯一引用，不复制定义）。
  static const String rubricVersion = '1.0.0';

  /// rubric 布局维度 id。
  static const String rubricDimension = 'D5';

  /// EvaluationSpec content_sha256（V3-004A 冻结件）。
  static const String evaluationSpecContentSha256 =
      '83dc663e5f7eee107c40f528df555a45e86a52c2a097bf4afa908171635ef303';

  static const List<LayoutMetricDefinition> definitions = [
    LayoutMetricDefinition(
      id: LayoutMetricId.hierarchy,
      name: '层级',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.readingOrder,
      name: '顺序',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.figureTextAffinity,
      name: '图文亲和',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.alignmentRhythm,
      name: '对齐节奏',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.densityWhitespace,
      name: '密度留白',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.visualBalance,
      name: '视觉平衡',
      lowerBound: 0,
      upperBound: 1,
    ),
    LayoutMetricDefinition(
      id: LayoutMetricId.modificationCost,
      name: '改动成本',
      lowerBound: 0,
      upperBound: 1,
    ),
  ];

  /// 校验指标向量：全部指标存在、有限、在界内；违例抛 StateError
  ///（契约失败即程序缺陷，不容忍脏数据进入排序）。
  static void validateVector(Map<LayoutMetricId, double> values) {
    for (final def in definitions) {
      final v = values[def.id];
      if (v == null) {
        throw StateError('metric ${def.id.name} missing');
      }
      if (v.isNaN || v < def.lowerBound - _eps || v > def.upperBound + _eps) {
        throw StateError(
          'metric ${def.id.name} out of bounds: $v '
          '(${def.lowerBound}..${def.upperBound})',
        );
      }
    }
    if (values.length != definitions.length) {
      throw StateError('unexpected metric ids: ${values.keys}');
    }
  }

  static const double _eps = 1e-9;
}

/// 软指标向量（仅经 LayoutMetricCalculator 在硬通过后产生；
/// [factsFingerprint] 钉住来源几何，供审计与反投机交叉核对）。
class LayoutMetricVector {
  LayoutMetricVector({required this.values, required this.factsFingerprint}) {
    LayoutMetricContract.validateVector(values);
  }

  final Map<LayoutMetricId, double> values;

  /// 输入事实的 canonical 指纹（fingerprint64；双跑一致）。
  final String factsFingerprint;

  double operator [](LayoutMetricId id) => values[id]!;
}

/// 指标计算的输入事实（纯几何 + 冻结 token；无软分/排名/profile 通道）。
///
/// [placed] 必须按阅读序给出（placer 语义）；[originalBounds] 为各块
/// 原位投影（改动成本基准；preserved/protected 块不参与放置，天然
/// 零改动）；[hardValidated] 为真实 Scene 硬门禁结论——false 时计算器
/// 拒绝产出软分（硬失败不能被软分抵消）。
class LayoutMetricInput {
  const LayoutMetricInput({
    required this.assembly,
    required this.placed,
    required this.columnRects,
    required this.preservedRects,
    required this.originalBounds,
    required this.contentHeight,
    required this.hardValidated,
    this.hardViolationCount = 0,
  });

  final LayoutBlockAssembly assembly;
  final List<PlacedBlock> placed;
  final List<LayoutRect> columnRects;
  final Map<String, LayoutRect> preservedRects;
  final Map<String, LayoutRect> originalBounds;
  final double contentHeight;
  final bool hardValidated;
  final int hardViolationCount;

  /// 块种类/阅读序查表。
  LayoutBlock? blockOf(String id) {
    for (final b in assembly.blocks) {
      if (b.id == id) return b;
    }
    return null;
  }
}
