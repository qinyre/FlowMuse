import '../snapshot/deterministic_hash.dart';

/// 智能排版 v3 设计令牌（计划书 §4.7，任务 V3-300A）。
///
/// 只冻结“类别 + v1 值”，类别为计划书列举的：字号层级、最小正文、行距、
/// 段距、栏沟、页边距、snap、行长、孤行、图文距离、密度目标。
/// v1 值全部锚定现有渲染/模板基线，未引入无出处的拍脑袋数值：
/// - 字号与行距：`TextElement` 默认（正文 20 / 行距 1.25）；
/// - 标题下限 28、正文下限 12：`SmartLayoutTemplateEngine` 既有规则；
/// - 段距/栏沟/图文距离 24、压缩下限 8、outline 行距 16：模板引擎
///   `handoutCompressionSteps` 首档与下限、`outlineRowGap`；
/// - 页边距 48 = 2× 首档段距、snap 8 = 压缩下限（v2 无独立常数，属
///   基线推导的 v1 初始值）；
/// - 行长 240～560：正文 20pt 下约 12～28 个全宽 CJK 字（版式惯例区间）；
/// - 孤行 2/2、密度目标 0.6：排版惯例初始值，待 validation 校准。
///
/// 冻结机制：[canonicalJson]/[canonicalHash] 给出全字段确定性指纹，
/// 测试固定 v1 指纹；validation 之后任何数值调整都必须 bump
/// [tokenVersion] 并同步测试固定值，静默改动会被拦截。
final class SmartLayoutDesignTokens {
  /// 令牌版本；v1 冻结于 V3-300A。
  static const String tokenVersion = 'design-tokens/v1';

  /// 标题字号下限（模板引擎 `_styledTitle` 的 28pt 规则）。
  final double titleFloorSize;

  /// 正文字号基线（`TextElement.fontSize` 默认 20）。
  final double bodySize;

  /// 正文字号下限（模板引擎 `_scaledBody` 的 12pt 下限）。
  final double minBodySize;

  /// 行距倍数（`TextElement.lineHeight` 默认 1.25）。
  final double lineHeight;

  /// 段落间距（模板引擎 handout 首档 gap 24）。
  final double paragraphSpacing;

  /// 空间紧张时的间距压缩下限（handout 压缩档末档 gap 8）。
  final double compactGapFloor;

  /// outline 模板条目行距（引擎 `outlineRowGap` 16）。
  final double outlineRowGap;

  /// 双栏栏沟（handout 半栏切分使用首档 gap：`(width - gap) / 2`）。
  final double columnGutter;

  /// 页边距；v2 内容区直接取场景包围盒，无独立常数，v1 取 2× 首档段距。
  final double pageMargin;

  /// 吸附步长；v2 无独立常数，v1 对齐压缩下限 8。
  final double snapStep;

  /// 行长下限（pt）：正文 20pt 下约 12 个全宽 CJK 字。
  final double minLineLength;

  /// 行长上限（pt）：正文 20pt 下约 28 个全宽 CJK 字。
  final double maxLineLength;

  /// 孤行/寡行规则：断页/断栏处前后各保留的最少行数（2/2 惯例）。
  final int widowOrphanMinLines;

  /// 图文最小间距（handout 图与上下图注栈之间的 gap，取首档 24）。
  final double figureTextGap;

  /// 密度目标（0～1）：内容区期望填充率下限；v1 取排版惯例 0.6，
  /// validation 校准后如调整需 bump 版本。
  final double targetDensity;

  const SmartLayoutDesignTokens({
    required this.titleFloorSize,
    required this.bodySize,
    required this.minBodySize,
    required this.lineHeight,
    required this.paragraphSpacing,
    required this.compactGapFloor,
    required this.outlineRowGap,
    required this.columnGutter,
    required this.pageMargin,
    required this.snapStep,
    required this.minLineLength,
    required this.maxLineLength,
    required this.widowOrphanMinLines,
    required this.figureTextGap,
    required this.targetDensity,
  });

  /// v1 冻结基线（值来源见各字段文档）。
  static const SmartLayoutDesignTokens v1 = SmartLayoutDesignTokens(
    titleFloorSize: 28,
    bodySize: 20,
    minBodySize: 12,
    lineHeight: 1.25,
    paragraphSpacing: 24,
    compactGapFloor: 8,
    outlineRowGap: 16,
    columnGutter: 24,
    pageMargin: 48,
    snapStep: 8,
    minLineLength: 240,
    maxLineLength: 560,
    widowOrphanMinLines: 2,
    figureTextGap: 24,
    targetDensity: 0.6,
  );

  /// 数字的规范形：整数值 double 去掉 `.0`，其余用最短表示。
  static String _num(num v) =>
      v is int ? v.toString() : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  /// 全字段确定性 JSON（键按字母序、无空白），作为指纹负载。
  String canonicalJson() {
    final fields = <String, num>{
      'bodySize': bodySize,
      'columnGutter': columnGutter,
      'compactGapFloor': compactGapFloor,
      'figureTextGap': figureTextGap,
      'lineHeight': lineHeight,
      'maxLineLength': maxLineLength,
      'minBodySize': minBodySize,
      'minLineLength': minLineLength,
      'outlineRowGap': outlineRowGap,
      'pageMargin': pageMargin,
      'paragraphSpacing': paragraphSpacing,
      'snapStep': snapStep,
      'targetDensity': targetDensity,
      'titleFloorSize': titleFloorSize,
      'widowOrphanMinLines': widowOrphanMinLines,
    };
    final keys = fields.keys.toList()..sort();
    return '{${keys.map((k) => '"$k":${_num(fields[k]!)}').join(',')}}';
  }

  /// 指纹（snapshot/deterministic_hash 的双通道 FNV，VM/dart2js 一致）。
  String canonicalHash() => fingerprint64('design-tokens/$tokenVersion|${canonicalJson()}');

  @override
  String toString() => 'SmartLayoutDesignTokens($tokenVersion ${canonicalHash()})';
}
