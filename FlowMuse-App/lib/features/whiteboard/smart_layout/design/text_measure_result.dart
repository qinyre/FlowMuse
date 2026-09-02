/// 真实排版测量结果（任务 V3-300A）。
///
/// 契约：不估算、不截断——[width] 是真实最宽行宽。引擎对超长词会在词内
/// 断行（真实 renderer 行为，测量如实反映为多行）；只有单个原子字素簇
///（如一个 emoji/一个大字号 CJK 字）宽于 [maxWidth] 时无法断行，
/// [overflows] 为 true 且 [width] 如实大于 [maxWidth]，不省略、不截断。
/// 调用方（planner/preflight）据 [overflows] 与 [lineCount] 拒绝或换档，
/// 而不是假装放得下。
final class TextMeasureResult {
  /// 真实最宽行宽（不受 [maxWidth] 钳制；原子簇过宽时可大于 [maxWidth]）。
  final double width;

  /// 排版后的真实总高（行数 × 行高）。
  final double height;

  /// 行数（孤行/寡行规则与换行决策的输入；词内断行也如实计入）。
  final int lineCount;

  /// 测量时的目标宽度约束（无约束时为 [double.infinity]）。
  final double maxWidth;

  /// 是否存在无法断行而超出 [maxWidth] 的原子字素簇。
  final bool overflows;

  const TextMeasureResult({
    required this.width,
    required this.height,
    required this.lineCount,
    required this.maxWidth,
    required this.overflows,
  });

  /// 空文本的零尺寸结果。
  static const TextMeasureResult empty = TextMeasureResult(
    width: 0,
    height: 0,
    lineCount: 0,
    maxWidth: double.infinity,
    overflows: false,
  );

  @override
  String toString() =>
      'TextMeasureResult(${width.toStringAsFixed(2)}x${height.toStringAsFixed(2)} '
      'lines=$lineCount maxWidth=$maxWidth overflows=$overflows)';
}
