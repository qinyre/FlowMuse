import 'dart:math' as math;

/// 手写转文字的排版字号估算。
///
/// 由笔迹包围盒与识别文本反推合适的 [TextElement] 字号：
/// - 高度是主信号：每行包围盒高度 ≈ 字高 × 语种系数
///   （CJK 字形近方形 ≈ 0.9em，拉丁含升降部 ≈ 0.72em）；
/// - 宽度是单行 CJK 的兜底信号：CJK 字符宽 ≈ 1em，
///   用于"一"等扁平字迹高度触底的场景；拉丁手写横向延展大，不采用；
/// - 上下限吸收估计误差与退化输入。
class InkTextSizing {
  static const double _minFontSize = 12;
  static const double _maxFontSize = 400;
  static const double _maxWidthBasedFontSize = 160;

  /// 估算手写字迹对应排版字号。
  ///
  /// [inkWidth]/[inkHeight] 为笔迹包围盒尺寸；[text] 为识别文本；
  /// [isMath] 为真时按公式启发式（与智能排版公式分支一致）。
  ///
  /// 高度是主信号；宽度兜底仅用于**单个 CJK 字符**的扁平字迹
  /// （如长横"一"：高度触底但宽度可靠），多字符时宽度含字距噪声不采用。
  static double estimateFontSize({
    required double inkWidth,
    required double inkHeight,
    required String text,
    bool isMath = false,
  }) {
    if (isMath) {
      return clampValue(inkHeight * 0.72, 16, 40);
    }
    final lines = normalizeLines(text);
    final lineCount = math.max(1, lines.length);
    final cjkRatio = _cjkRatio(text);
    final heightFactor = 0.72 + 0.18 * cjkRatio;
    final byHeight = math.max(inkHeight, 1.0) / lineCount * heightFactor;
    var byWidth = 0.0;
    if (lineCount == 1 && _isSingleCjkChar(text)) {
      byWidth = math.min(math.max(inkWidth, 1.0), _maxWidthBasedFontSize);
    }
    return clampValue(
      math.max(byHeight, byWidth),
      _minFontSize,
      _maxFontSize,
    );
  }

  /// 将 `\r\n` / `\r` 统一为 `\n` 后按行拆分。
  static List<String> normalizeLines(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
  }

  static double clampValue(double value, double min, double max) {
    return math.max(min, math.min(value, max));
  }

  /// CJK rune（非空白）占比；无有效字符时返回 0。
  static double _cjkRatio(String text) {
    var total = 0;
    var cjk = 0;
    for (final rune in text.runes) {
      if (String.fromCharCode(rune).trim().isEmpty) continue;
      total++;
      if (isCjkRune(rune)) cjk++;
    }
    return total == 0 ? 0 : cjk / total;
  }

  static bool isCjkRune(int rune) {
    return (rune >= 0x2E80 && rune <= 0x9FFF) || // CJK 部首/汉字/注音
        (rune >= 0x3040 && rune <= 0x30FF) || // 假名
        (rune >= 0xF900 && rune <= 0xFAFF) || // 兼容表意
        (rune >= 0x20000 && rune <= 0x3FFFD); // 扩展表意
  }

  /// 文本（忽略空白后）恰好是一个 CJK 字符。
  static bool _isSingleCjkChar(String text) {
    var count = 0;
    var allCjk = true;
    for (final rune in text.runes) {
      if (String.fromCharCode(rune).trim().isEmpty) continue;
      count++;
      if (!isCjkRune(rune)) allCjk = false;
    }
    return count == 1 && allCjk;
  }
}
