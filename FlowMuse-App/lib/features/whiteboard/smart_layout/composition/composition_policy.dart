import 'layout_block.dart';
import '../design/smart_layout_design_tokens.dart';

/// V3 整页构图初值；以页面宽 1024 归一，不读取屏幕 zoom，也不改旧 tokens/v1。
class CompositionPolicy {
  const CompositionPolicy({
    required this.pageWidth,
    this.compact = false,
    this.tight = false,
  });

  static const version = 'semantic-composition/2';
  final double pageWidth;
  final bool compact;
  final bool tight;
  double get scale => pageWidth / 1024;
  double get margin => 48 * scale;
  double get innerGap => (tight || compact ? 12 : 16) * scale;
  double get groupGap => (tight || compact ? 24 : 32) * scale;
  double get sectionGap => (tight || compact ? 36 : 48) * scale;
  double get bodySize => (compact ? 22 : 24) * scale;
  double get maxTextWidth => 32 * bodySize;
  String get key => '$version:$pageWidth:$compact:$tight';

  SmartLayoutDesignTokens get validationTokens => SmartLayoutDesignTokens(
    titleFloorSize: fontSize(LayoutBlockKind.title),
    bodySize: bodySize,
    minBodySize: 12 * scale,
    lineHeight: 1.2,
    paragraphSpacing: groupGap,
    compactGapFloor: innerGap,
    outlineRowGap: innerGap,
    columnGutter: groupGap,
    pageMargin: margin,
    snapStep: 8 * scale,
    minLineLength: 12 * bodySize,
    maxLineLength: maxTextWidth,
    widowOrphanMinLines: 2,
    figureTextGap: innerGap,
    targetDensity: .6,
  );

  double fontSize(LayoutBlockKind kind, {bool sectionHeading = false}) =>
      switch (kind) {
        LayoutBlockKind.title =>
          (sectionHeading ? (compact ? 28 : 30) : (compact ? 33 : 36)) * scale,
        LayoutBlockKind.caption => 20 * scale,
        _ => bodySize,
      };

  double lineHeight(LayoutBlockKind kind) =>
      kind == LayoutBlockKind.title ? 1.2 : 1.35;
}
