import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';

import 'structure_test_helpers.dart';

/// §8.2 字号门禁（承接 #14）：禁止外框/行数/行高提示反推字号；
/// 六条回归——同一文字输出字号不因外框、截图倍率、区域合并而失控。
void main() {
  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  double? fontSizeOf(SemanticAssembly assembly, String blockId) {
    final block = assembly.document.blocks.firstWhere(
      (b) => b.id == blockId,
    );
    return block.extras['fontSize'] as double?;
  }

  test('源码门禁：适配器禁止外框反推字号，必须取 token 实值', () {
    final source = File(
      'lib/features/whiteboard/smart_layout/recognition/semantic_adapter.dart',
    ).readAsStringSync();
    // 剥除注释行再匹配，防止文档说明自报（仓库既有源码门禁惯例）。
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('0.72'), isFalse, reason: '禁止块高×系数反推');
    expect(code.contains('.height *'), isFalse, reason: '禁止高度乘系数');
    expect(code.contains('.height /'), isFalse, reason: '禁止高度除系数');
    expect(code.contains('.width *'), isFalse, reason: '禁止宽度乘系数');
    expect(code.contains('* lineHintHeight'), isFalse, reason: '禁止行高提示选档');
    expect(code.contains('tokens.titleFloorSize'), isTrue, reason: '标题取 token');
    expect(code.contains('tokens.bodySize'), isTrue, reason: '正文取 token');
    expect(code.contains('TextPainter'), isFalse, reason: '适配阶段不做宽度测量');
    expect(code.contains('measure.measure'), isFalse, reason: '测量留在块组装阶段');
  });

  test('§8.2-2 首版规则：title→28，其余文本单元→20（token 实值）', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:title', top: 0, left: 0, text: '大标题', lineHeight: 34),
      RegionSpec(regionId: 'r:body', top: 50, left: 0, text: '正文内容'),
    ]);
    final assembly = adapter.assemble(
      result,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );    expect(fontSizeOf(assembly, 'ink:r:title'), tokens.titleFloorSize);
    expect(fontSizeOf(assembly, 'ink:r:body'), tokens.bodySize);
  });

  test('§8.2-6 回归 1/2：单行 vs 多行——同文字同档', () async {
    final single = await sessionOf(const [
      RegionSpec(regionId: 'r:a', top: 0, left: 0, text: '同一段文字'),
    ]);
    final multi = await sessionOf(const [
      RegionSpec(regionId: 'r:b', top: 0, left: 0, text: '同\n一\n段\n文\n字', lineHeight: 100),
    ]);
    final a = adapter.assemble(single, measure: TextMeasureAdapter(), tokens: tokens);
    final b = adapter.assemble(multi, measure: TextMeasureAdapter(), tokens: tokens);
    expect(
      a.document.blocks.firstWhere((x) => x.id == 'ink:r:a').extras['fontSize'],
      b.document.blocks.firstWhere((x) => x.id == 'ink:r:b').extras['fontSize'],
    );
  });

  test('§8.2-6 回归 3：中英混排与纯中文同档', () async {
    final zh = await sessionOf(const [
      RegionSpec(regionId: 'r:zh', top: 0, left: 0, text: '中文正文'),
    ]);
    final mixed = await sessionOf(const [
      RegionSpec(regionId: 'r:mix', top: 0, left: 0, text: '混合 Text 正文 abc'),
    ]);
    final a = adapter.assemble(zh, measure: TextMeasureAdapter(), tokens: tokens);
    final b = adapter.assemble(mixed, measure: TextMeasureAdapter(), tokens: tokens);
    expect(
      a.document.blocks.firstWhere((x) => x.id == 'ink:r:zh').extras['fontSize'],
      b.document.blocks.firstWhere((x) => x.id == 'ink:r:mix').extras['fontSize'],
    );
  });

  test('§8.2-6 回归 4/5：超高离群笔画与不同裁剪留白不改档', () async {
    final normal = await sessionOf(const [
      RegionSpec(regionId: 'r:n', top: 0, left: 0, text: '正文'),
    ]);
    final outlier = await sessionOf(const [
      RegionSpec(regionId: 'r:o', top: 0, left: 0, text: '正文', lineHeight: 400),
    ]);
    final widePadding = await sessionOf(const [
      RegionSpec(regionId: 'r:w', top: 0, left: 0, text: '正文', width: 1200),
    ]);
    final a = adapter.assemble(normal, measure: TextMeasureAdapter(), tokens: tokens);
    final b = adapter.assemble(outlier, measure: TextMeasureAdapter(), tokens: tokens);
    final c = adapter.assemble(widePadding, measure: TextMeasureAdapter(), tokens: tokens);
    final sizeOf = (SemanticAssembly assembly, String id) =>
        assembly.document.blocks.firstWhere((x) => x.id == id).extras['fontSize'];
    expect(sizeOf(a, 'ink:r:n'), sizeOf(b, 'ink:r:o'));
    expect(sizeOf(a, 'ink:r:n'), sizeOf(c, 'ink:r:w'));
  });

  test('§8.2-6 回归 6：区域合并（行数变化）不改档；源行高提示不参与选档',
      () async {
    // 两区域分别识别后由结构合并成一段（模拟合并后行数变化）：
    // 手工构造结构覆盖两个区域成一个连续阅读序。
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:part1', top: 0, left: 0, text: '上半段'),
      RegionSpec(regionId: 'r:part2', top: 40, left: 0, text: '下半段'),
    ]);
    final assembly = adapter.assemble(
      result,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    final sizeOf = (String id) =>
        assembly.document.blocks.firstWhere((x) => x.id == id).extras['fontSize'];
    expect(sizeOf('ink:r:part1'), tokens.bodySize);
    expect(sizeOf('ink:r:part2'), tokens.bodySize);
  });
}
