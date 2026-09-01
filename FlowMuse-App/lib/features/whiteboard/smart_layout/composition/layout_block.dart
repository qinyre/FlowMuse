import '../design/text_measure_result.dart';

/// 排版块类别（V3-400A）：从语义 role 投影，外加排版专属两类
/// preserved（原样保留）/ protected（锁定障碍，供绕置）。
enum LayoutBlockKind {
  title,
  paragraph,
  list,
  caption,
  figure,
  formula,
  table,
  preserved,
  protected,
}

/// 文本来源三态（acceptance：typed/transcribed/preserved 必须明确）。
/// - typed：来自快照 exactText（协议保证，绝不来自模型）。
/// - transcribed：分析层转写文本（SemanticBlock.extras['transcribedText']，
///   当前管线可能缺席；出现即如实标注）。
/// 非文本块（figure/preserved/protected）origin 为 null。
enum LayoutTextOrigin { typed, transcribed }

/// 文本排版规格：真实测量的全部输入（V3-300A 适配器契约）。
class TextBlockSpec {
  const TextBlockSpec({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    this.direction = TextDirectionSpec.ltr,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final TextDirectionSpec direction;
}

/// 文本方向（RTL 语义块显式标注；测量基向影响 bidi）。
enum TextDirectionSpec { ltr, rtl }

/// 图片排版规格：比例来自快照显示/内在尺寸与归一化 crop——
/// 排版只按显示比例约束，绝不改写裁剪或内在尺寸。
class FigureBlockSpec {
  const FigureBlockSpec({
    required this.fileId,
    required this.displayAspectRatio,
    this.missingAsset = false,
  });

  final String fileId;

  /// 显示宽高比（含 crop：intrinsic.w·crop.w / intrinsic.h·crop.h）。
  final double displayAspectRatio;

  /// 资产缺失事实（不删块、不造数据；消费方按 preserved 语义处理）。
  final bool missingAsset;
}

/// 排版块（V3-400A）：语义块 → 候选生成原语的不可变投影。
///
/// 守恒约束：[sourceRefs] 透传语义 sourceIds；整个 assembly 的
/// 全部 sourceRefs 并集必须等于文档 ledger（assembler 复核，
/// 违例 fail closed）。未知字段经 [extras] 原样保留不丢失。
class LayoutBlock {
  const LayoutBlock({
    required this.id,
    required this.kind,
    required this.sourceRefs,
    required this.orderIndex,
    required this.keepTogether,
    this.textOrigin,
    this.text,
    this.figure,
    this.measuredIntrinsic,
    this.extras = const {},
  });

  /// 与语义块同 id（确定性；planner/patch 全链可追溯）。
  final String id;
  final LayoutBlockKind kind;
  final List<String> sourceRefs;

  /// 阅读序位置（语义 orderIndex 透传）。
  final double orderIndex;

  /// 块级原子性（figure+caption 由关系组表达，此位为块自身不可拆）。
  final bool keepTogether;
  final LayoutTextOrigin? textOrigin;
  final TextBlockSpec? text;
  final FigureBlockSpec? figure;

  /// 真实测量（不限宽 intrinsic；由注入的 TextMeasureAdapter 计算，
  /// 禁止估算）。非文本块为 null。
  final TextMeasureResult? measuredIntrinsic;

  /// 未知字段/分析 extras 原样保留。
  final Map<String, Object?> extras;

  bool get isTextual => text != null;
  bool get isPreservedLike =>
      kind == LayoutBlockKind.preserved || kind == LayoutBlockKind.protected;
}

/// 关系原子性（acceptance：caption/keep-together 不丢失）。
enum BlockRelationKind {
  /// caption 绑定其 figure（阅读序最近的前驱 figure）。
  captionOf,

  /// section 语义：标题与阅读序后继首块必须同组（不拆开）。
  keepWith,
}

/// 块间关系（不可变；两端 id 必须存在于 assembly）。
class BlockRelationship {
  const BlockRelationship({
    required this.kind,
    required this.fromBlockId,
    required this.toBlockId,
  });

  final BlockRelationKind kind;

  /// 关系发起端（caption / section 标题）。
  final String fromBlockId;

  /// 关系目标端（figure / 后继首块）。
  final String toBlockId;

  @override
  bool operator ==(Object other) =>
      other is BlockRelationship &&
      other.kind == kind &&
      other.fromBlockId == fromBlockId &&
      other.toBlockId == toBlockId;

  @override
  int get hashCode => Object.hash(kind, fromBlockId, toBlockId);

  @override
  String toString() =>
      '${kind.name}($fromBlockId -> $toBlockId)';
}
