import 'dart:math' as math;

import '../design/smart_layout_design_tokens.dart';
import '../placement/flow_placer.dart';
import 'layout_metric_contract.dart';

/// 反投机否决稳定码（V3-404A 冻结）：命中的候选**无论软分多高**都
/// 不得进入 Top 3（计划 §5.3 条 4）。全部由几何/事实谓词判定，
/// 不读软分。
enum AntiGamingVetoKind {
  /// no-op：声称重排但零修改（preserveFallback 才是零修改的正身）。
  noOp,

  /// 极缩：全部文本块被压到最小字号档以“放下”内容。
  extremeShrink,

  /// 隐藏：文本块被压到低于最小字号行高的盒（不可读≈不可见）。
  hiddenText,

  /// 大留白：块数 ≥3 且各栏填充率均值过低（空页投机）。
  excessiveWhitespace,

  /// 重复：同一块被放置两次或两个块占完全相同盒。
  duplicateContent,

  /// 成本造假：宣称的改动成本指标与事实移动量矛盾（伪造向量）。
  costFraud,
}

/// 否决结论。
class VetoVerdict {
  const VetoVerdict({required this.kinds, required this.reasons});

  final List<AntiGamingVetoKind> kinds;
  final List<String> reasons;

  bool get vetoed => kinds.isNotEmpty;
}

/// 反投机否决线（V3-404A）：对**事实输入**做谓词判定；成本造假
/// 通过交叉核对（claimed 向量 vs 事实移动量）发现，不信任向量自述。
class AntiGamingVetoDetector {
  const AntiGamingVetoDetector();

  /// [claimedVector] 为计算器产出的软分向量（可缺席——缺席时跳过
  /// costFraud 交叉核对，其余否决线照常生效）。
  VetoVerdict evaluate(
    LayoutMetricInput input, {
    LayoutMetricVector? claimedVector,
    SmartLayoutDesignTokens tokens = SmartLayoutDesignTokens.v1,
  }) {
    final kinds = <AntiGamingVetoKind>[];
    final reasons = <String>[];

    // 重复：blockId 重复或完全相同盒。
    final seenIds = <String>{};
    final seenRects = <String, String>{};
    for (final p in input.placed) {
      if (!seenIds.add(p.blockId)) {
        kinds.add(AntiGamingVetoKind.duplicateContent);
        reasons.add('block ${p.blockId} placed twice');
      }
      final rectKey =
          '${p.rect.left},${p.rect.top},${p.rect.width},${p.rect.height}';
      final owner = seenRects[rectKey];
      if (owner != null && owner != p.blockId) {
        kinds.add(AntiGamingVetoKind.duplicateContent);
        reasons.add('blocks $owner and ${p.blockId} share identical rect');
      }
      seenRects.putIfAbsent(rectKey, () => p.blockId);
    }

    // 隐藏：文本盒被压碎（低于最小字号行高）或非正盒。
    final minLineHeight = tokens.minBodySize * tokens.lineHeight;
    for (final p in input.placed) {
      final block = input.blockOf(p.blockId);
      if (block == null || !block.isTextual) continue;
      final crushed = p.rect.height + _eps < minLineHeight;
      final nonPositive = p.rect.width <= 0 || p.rect.height <= 0;
      if (crushed || nonPositive) {
        kinds.add(AntiGamingVetoKind.hiddenText);
        reasons.add('text block ${p.blockId} not readable '
            '(h=${p.rect.height}, floor=$minLineHeight)');
      }
    }

    // 极缩：≥2 个文本块且全部已在最小字号档。
    final textual = <PlacedBlock>[];
    for (final p in input.placed) {
      final block = input.blockOf(p.blockId);
      if (block != null && block.isTextual) textual.add(p);
    }
    if (textual.length >= 2) {
      final allAtFloor = textual.every(
        (p) => p.appliedFontSize <= tokens.minBodySize + _eps,
      );
      if (allAtFloor) {
        kinds.add(AntiGamingVetoKind.extremeShrink);
        reasons.add('all ${textual.length} text blocks at min font size');
      }
    }

    // no-op / 成本造假：事实移动量（原位投影存在时才可判）。
    final meanMove = _meanNormalizedMove(input);
    if (input.placed.isNotEmpty &&
        meanMove != null &&
        meanMove < _noOpMoveEpsilon) {
      kinds.add(AntiGamingVetoKind.noOp);
      reasons.add('mean normalized move $meanMove < $_noOpMoveEpsilon');
    }
    if (claimedVector != null &&
        meanMove != null &&
        meanMove > _costFraudMoveFloor &&
        claimedVector.values[LayoutMetricId.modificationCost]! >
            _costFraudClaimFloor) {
      kinds.add(AntiGamingVetoKind.costFraud);
      reasons.add('claimed cost '
          '${claimedVector.values[LayoutMetricId.modificationCost]} vs '
          'actual mean move $meanMove');
    }

    // 大留白：≥3 块且各栏填充率均值 < 0.20。前提是内容体量本可达下限
    // （零间隙堆叠的理论填充 ≥ 下限）——稀疏内容页（如少量手写转写成
    // 标准字号文本后远小于页面）任何排列都无法达到下限，留白是内容
    // 体量的诚实结果而非布局投机，不适用本否决线。
    if (input.placed.length >= 3 && input.columnRects.isNotEmpty) {
      var fillSum = 0.0;
      var placedHeightSum = 0.0;
      for (final p in input.placed) {
        placedHeightSum += p.rect.height;
      }
      for (var c = 0; c < input.columnRects.length; c++) {
        var deepest = 0.0;
        for (final p in input.placed) {
          if (p.columnIndex != c) continue;
          final depth = p.rect.bottom - input.columnRects[c].top;
          if (depth > deepest) deepest = depth;
        }
        fillSum += (deepest / input.contentHeight).clamp(0.0, 1.0);
      }
      final density = fillSum / input.columnRects.length;
      final achievable =
          (placedHeightSum / input.contentHeight).clamp(0.0, 1.0);
      if (density < _whitespaceDensityFloor &&
          achievable >= _whitespaceDensityFloor) {
        kinds.add(AntiGamingVetoKind.excessiveWhitespace);
        reasons.add('mean column fill $density < $_whitespaceDensityFloor');
      }
    }

    return VetoVerdict(kinds: List.unmodifiable(kinds), reasons: reasons);
  }

  /// 均值归一化移动（对角线归一）；无原位投影覆盖时返回 null。
  double? _meanNormalizedMove(LayoutMetricInput input) {
    var diag = 0.0;
    for (final column in input.columnRects) {
      diag = math.max(diag, column.right);
    }
    diag = math.sqrt(diag * diag + input.contentHeight * input.contentHeight);
    if (diag <= _eps) return null;
    var sum = 0.0;
    var count = 0;
    for (final p in input.placed) {
      final original = input.originalBounds[p.blockId];
      if (original == null) continue;
      final dx = (p.rect.left + p.rect.width / 2) -
          (original.left + original.width / 2);
      final dy = (p.rect.top + p.rect.height / 2) -
          (original.top + original.height / 2);
      sum += math.sqrt(dx * dx + dy * dy) / diag;
      count++;
    }
    if (count == 0) return null;
    return sum / count;
  }

  /// 冻结常数（v1）：no-op 判定、留白下限、成本造假交叉核对线。
  static const double _noOpMoveEpsilon = 1e-3;
  static const double _whitespaceDensityFloor = 0.20;
  static const double _costFraudMoveFloor = 0.05;
  static const double _costFraudClaimFloor = 0.995;

  static const double _eps = 1e-9;
}
