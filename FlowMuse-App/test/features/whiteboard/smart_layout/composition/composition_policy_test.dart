import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/composition_policy.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';

void main() {
  test('统一字号档随页面尺寸缩放，与 zoom 无关', () {
    const normal = CompositionPolicy(pageWidth: 1024);
    const large = CompositionPolicy(pageWidth: 2048);
    const compact = CompositionPolicy(pageWidth: 1024, compact: true);
    expect(normal.bodySize, 24);
    expect(large.fontSize(LayoutBlockKind.title), 72);
    expect(large.innerGap, normal.innerGap * 2);
    expect(compact.bodySize, 22);
    expect(compact.fontSize(LayoutBlockKind.title, sectionHeading: true), 28);
    expect(compact.groupGap, 24);
  });

  DisplayTextProjection project(
    String raw,
    List<int> indexes, {
    LayoutTextOrigin origin = LayoutTextOrigin.transcribed,
    LayoutBlockKind kind = LayoutBlockKind.paragraph,
    double confidence = .95,
  }) => DisplayTextProjection.create(
    rawText: raw,
    origin: origin,
    kind: kind,
    newlineIndexes: indexes,
    confidence: confidence,
  );

  test('只合并批准的换行：中英文、CRLF、emoji、不改连字符与未批准换行', () {
    const raw = '小🐈\n和 dog\r\nsleep\nsoft-\nware\n保留\n换行';
    final result = project(raw, [0, 1, 3]);
    expect(result.rawText, raw);
    expect(result.displayText, '小🐈和 dog sleep\nsoft-ware\n保留\n换行');
    expect(result.approvedNewlines, [0, 1, 3]);
    expect(
      result.displayText.replaceAll(RegExp(r'\s'), ''),
      raw.replaceAll(RegExp(r'\s'), ''),
    );
  });

  test('原生文字、列表、低置信及无提示保持原文', () {
    const raw = '第一行\n第二行';
    expect(project(raw, []).displayText, raw);
    expect(project(raw, [0], origin: LayoutTextOrigin.typed).displayText, raw);
    expect(project(raw, [0], kind: LayoutBlockKind.list).displayText, raw);
    expect(project(raw, [0], confidence: .8).displayText, raw);
    expect(project(raw, [0], confidence: double.nan).displayText, raw);
    expect(() => project(raw, [1]), throwsStateError);
    expect(() => project(raw, [0, 0]), throwsStateError);
    expect(() => project('段落\n\n下一段', [0]), throwsStateError);
  });
}
