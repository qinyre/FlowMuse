import '../design/text_measure_result.dart';
import '../geometry/layout_rect.dart';

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

enum CompositionGroupKind { textFlow, mediaStack, mediaSide }

/// 候选声明的组与阅读路径；验证器只用它取期望，几何真值从 renderer 读取。
class CompositionGroupIntent {
  CompositionGroupIntent({
    required this.id,
    required this.kind,
    required List<List<String>> tracks,
    required this.slot,
    required this.row,
    required this.column,
    required this.maxGap,
  }) : tracks = List.unmodifiable(
         tracks.map((t) => List<String>.unmodifiable(t)),
       );

  final String id;
  final CompositionGroupKind kind;
  final List<List<String>> tracks;
  final LayoutRect slot;
  final int row;
  final int column;
  final double maxGap;
  List<String> get memberIds => tracks.expand((t) => t).toList();
  List<Object?> toCanonical() => [
    id,
    kind.name,
    tracks,
    row,
    column,
    maxGap,
    slot.left,
    slot.top,
    slot.width,
    slot.height,
  ];
}

/// 文本排版规格：真实测量的全部输入（V3-300A 适配器契约）。
class TextBlockSpec {
  const TextBlockSpec({
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    required this.lineHeight,
    this.direction = TextDirectionSpec.ltr,
    this.projection,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final TextDirectionSpec direction;
  final DisplayTextProjection? projection;
}

/// 只改经确认的 OCR 软换行；raw 永久保留，正文内容不被“清洗”。
class DisplayTextProjection {
  DisplayTextProjection._(this.rawText, this.displayText, List<int> indexes)
    : approvedNewlines = List.unmodifiable(indexes);

  factory DisplayTextProjection.create({
    required String rawText,
    required LayoutTextOrigin origin,
    required LayoutBlockKind kind,
    List<int> newlineIndexes = const [],
    double confidence = 0,
  }) {
    if (newlineIndexes.isEmpty ||
        origin != LayoutTextOrigin.transcribed ||
        (kind != LayoutBlockKind.paragraph &&
            kind != LayoutBlockKind.title &&
            kind != LayoutBlockKind.caption) ||
        !confidence.isFinite ||
        confidence < 0.9 ||
        confidence > 1) {
      return DisplayTextProjection._(rawText, rawText, const []);
    }
    final lines = rawText.split('\n');
    final indexes = newlineIndexes.toSet().toList()..sort();
    if (indexes.length != newlineIndexes.length ||
        indexes.any(
          (n) =>
              n < 0 ||
              n >= lines.length - 1 ||
              lines[n].trim().isEmpty ||
              lines[n + 1].trim().isEmpty,
        )) {
      throw StateError('invalid-soft-line-break');
    }
    final approved = indexes.toSet();
    final result = StringBuffer();
    final latinWord = RegExp(r'[A-Za-z0-9\u00c0-\u024f]');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (approved.contains(i)) {
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
        result.write(line);
        if (latinWord.hasMatch(line.substring(line.length - 1)) &&
            latinWord.hasMatch(lines[i + 1].substring(0, 1))) {
          result.write(' ');
        }
      } else {
        result.write(line);
        if (i + 1 < lines.length) result.write('\n');
      }
    }
    return DisplayTextProjection._(rawText, result.toString(), indexes);
  }

  final String rawText;
  final String displayText;
  final List<int> approvedNewlines;
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
    this.displayWidth,
  });

  final String fileId;

  /// 显示宽高比（含 crop：intrinsic.w·crop.w / intrinsic.h·crop.h）。
  final double displayAspectRatio;

  /// 资产缺失事实（不删块、不造数据；消费方按 preserved 语义处理）。
  final bool missingAsset;

  /// 源场景显示宽度；已有小图只缩不放，避免被拉伸铺满一栏。
  final double? displayWidth;

  double widthInColumn(double columnWidth) =>
      displayWidth != null && displayWidth! > 0 && displayWidth! < columnWidth
      ? displayWidth!
      : columnWidth;
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
  String toString() => '${kind.name}($fromBlockId -> $toBlockId)';
}
