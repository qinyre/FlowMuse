import 'package:flutter_test/flutter_test.dart';

import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';

/// V3-300A 设计令牌测试：基线值锚定、canonical JSON/hash 冻结、
/// validation 后版本冻结机制可拦截静默改动。
void main() {
  test('v1 值全部锚定现有渲染/模板基线', () {
    const t = SmartLayoutDesignTokens.v1;
    // TextElement 默认 + 模板引擎既有规则。
    expect(t.bodySize, 20); // TextElement.fontSize 默认
    expect(t.lineHeight, 1.25); // TextElement.lineHeight 默认
    expect(t.titleFloorSize, 28); // _styledTitle 下限
    expect(t.minBodySize, 12); // _scaledBody 下限
    // handoutCompressionSteps 首档/末档 gap 与 outlineRowGap。
    expect(t.paragraphSpacing, 24);
    expect(t.compactGapFloor, 8);
    expect(t.outlineRowGap, 16);
    expect(t.columnGutter, 24); // 半栏切分用首档 gap
    expect(t.figureTextGap, 24); // 图与图注栈 gap 首档
    // 推导初始值：页边距 = 2× 首档段距；snap = 压缩下限。
    expect(t.pageMargin, t.paragraphSpacing * 2);
    expect(t.snapStep, t.compactGapFloor);
    // 行长区间有序且为正。
    expect(t.minLineLength, lessThan(t.maxLineLength));
    expect(t.minLineLength, greaterThan(0));
    // 孤行规则与密度目标在合法范围。
    expect(t.widowOrphanMinLines, greaterThanOrEqualTo(2));
    expect(t.targetDensity, inExclusiveRange(0, 1));
  });

  test('canonicalJson 键序确定且逐字节稳定', () {
    const t = SmartLayoutDesignTokens.v1;
    final a = t.canonicalJson();
    final b = t.canonicalJson();
    expect(a, b);
    expect(
      a,
      '{"bodySize":20,"columnGutter":24,"compactGapFloor":8,'
      '"figureTextGap":24,"lineHeight":1.25,"maxLineLength":560,'
      '"minBodySize":12,"minLineLength":240,"outlineRowGap":16,'
      '"pageMargin":48,"paragraphSpacing":24,"snapStep":8,'
      '"targetDensity":0.6,"titleFloorSize":28,"widowOrphanMinLines":2}',
    );
  });

  test('v1 指纹冻结：hash 等于固定值（validation 后调值必须 bump 版本）', () {
    const t = SmartLayoutDesignTokens.v1;
    const pinned = 'b0879098413fd0bf';
    if (t.canonicalHash() != pinned) {
      // 失败信息携带实际指纹，供冻结时回填固定值。
      fail('canonicalHash=${t.canonicalHash()} != pinned($pinned)');
    }
  });

  test('tokenVersion 标注 v1 冻结版本', () {
    expect(SmartLayoutDesignTokens.tokenVersion, 'design-tokens/v1');
  });

  test('数值变动必然改变指纹（冻结机制有效性）', () {
    const t = SmartLayoutDesignTokens.v1;
    final mutated = SmartLayoutDesignTokens(
      titleFloorSize: t.titleFloorSize,
      bodySize: t.bodySize,
      minBodySize: t.minBodySize,
      lineHeight: t.lineHeight,
      paragraphSpacing: t.paragraphSpacing,
      compactGapFloor: t.compactGapFloor,
      outlineRowGap: t.outlineRowGap,
      columnGutter: t.columnGutter,
      pageMargin: t.pageMargin,
      snapStep: t.snapStep,
      minLineLength: t.minLineLength,
      maxLineLength: t.maxLineLength,
      widowOrphanMinLines: t.widowOrphanMinLines,
      figureTextGap: t.figureTextGap,
      targetDensity: 0.62, // 微调密度目标
    );
    expect(mutated.canonicalHash(), isNot(t.canonicalHash()));
    expect(mutated.canonicalJson(), isNot(t.canonicalJson()));
  });
}
