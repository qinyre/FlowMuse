import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';

import 'structure_test_helpers.dart';

/// §7 本地规则逐条：编号/项目符号列表、x 向缩进、嵌套挂靠、标题四证据、
/// 图注唯一目标、原生文本绕过 OCR、孤立小数不成列表。
void main() {
  test('有序列表：编号连续 + 同缩进带成组（startNumber=1）', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '1. 第一项'),
      RegionSpec(regionId: 'r:b', top: 130, left: 2, text: '2. 第二项'),
      RegionSpec(regionId: 'r:c', top: 160, left: 1, text: '3. 第三项'),
    ]);
    expect(result.usedModel, isFalse, reason: '单组无歧义不触发结构请求');
    expect(result.listGroups, hasLength(1));
    final group = result.listGroups.single;
    expect(group.listType, RecognitionListType.ordered);
    expect(group.startNumber, 1);
    expect(group.level, 1);
    expect(group.members, ['ink:r:a', 'ink:r:b', 'ink:r:c']);
    for (final member in group.members) {
      expect(result.roles[member], 'listItem');
    }
  });

  test('"1.2" 小数排除：孤立的带小数文本不成列表', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '1.2 米宽'),
      RegionSpec(regionId: 'r:b', top: 130, left: 0, text: '3.14 是圆周率'),
    ]);
    expect(result.listGroups, isEmpty);
    expect(result.roles['ink:r:a'], 'body');
    expect(result.roles['ink:r:b'], 'body');
  });

  test('项目符号列表：- 开头连续两项成无序组', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '- 苹果'),
      RegionSpec(regionId: 'r:b', top: 130, left: 3, text: '- 香蕉'),
    ]);
    expect(result.listGroups, hasLength(1));
    expect(result.listGroups.single.listType, RecognitionListType.unordered);
    expect(result.listGroups.single.startNumber, isNull);
  });

  test('x 向缩进不一致不成组：横向错位列表项被拒', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '1. 第一项'),
      RegionSpec(regionId: 'r:b', top: 130, left: 40, text: '2. 第二项'),
    ]);
    // 缩进差 40 > 容差 0.6×行高(12) → 不构成同组（两项各不成组）。
    expect(result.listGroups, isEmpty);
  });

  test('嵌套挂靠：子组首成员缩进带对应最近上方父组末项', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:p1', top: 100, left: 0, text: '1. 父项一'),
      RegionSpec(regionId: 'r:p2', top: 130, left: 0, text: '2. 父项二'),
      RegionSpec(regionId: 'r:c1', top: 160, left: 24, text: '1. 子项一'),
      RegionSpec(regionId: 'r:c2', top: 190, left: 25, text: '2. 子项二'),
    ]);
    expect(result.listGroups, hasLength(2));
    final child = result.listGroups.firstWhere(
      (group) => group.level == 2,
      orElse: () => throw StateError('缺少子组'),
    );
    expect(child.parentUnitId, 'ink:r:p2', reason: '父项=最近上方父组末成员');
    final parent = result.listGroups.firstWhere((group) => group.level == 1);
    expect(parent.members, ['ink:r:p1', 'ink:r:p2']);
  });

  test('标题四证据：全部满足判 title', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(
        regionId: 'r:title',
        top: 20,
        left: 0,
        text: '会议纪要',
        lineHeight: 36,
      ),
      RegionSpec(
        regionId: 'r:body',
        top: 80,
        left: 0,
        text: '正文第一行',
        lineHeight: 20,
      ),
      RegionSpec(
        regionId: 'r:body2',
        top: 110,
        left: 0,
        text: '正文第二行',
        lineHeight: 20,
      ),
    ]);
    expect(result.roles['ink:r:title'], 'title');
    expect(result.roles['ink:r:body'], 'body');
  });

  test('标题任一证据不满足一律 body', () async {
    // 行高不足 1.3×中位数。
    var result = await recoverWithRegions(const [
      RegionSpec(
        regionId: 'r:t',
        top: 20,
        left: 0,
        text: '小标题',
        lineHeight: 22,
      ),
      RegionSpec(
        regionId: 'r:b',
        top: 80,
        left: 0,
        text: '正文行',
        lineHeight: 20,
      ),
    ]);
    expect(result.roles['ink:r:t'], 'body', reason: '行高不足');

    // 句末标点。
    result = await recoverWithRegions(const [
      RegionSpec(
        regionId: 'r:t',
        top: 20,
        left: 0,
        text: '这是一个标题。',
        lineHeight: 36,
      ),
      RegionSpec(
        regionId: 'r:b',
        top: 80,
        left: 0,
        text: '正文行',
        lineHeight: 20,
      ),
    ]);
    expect(result.roles['ink:r:t'], 'body', reason: '句末标点拒绝');

    // 多行。
    result = await recoverWithRegions(const [
      RegionSpec(
        regionId: 'r:t',
        top: 20,
        left: 0,
        text: '第一行\n第二行',
        lineHeight: 36,
      ),
      RegionSpec(
        regionId: 'r:b',
        top: 80,
        left: 0,
        text: '正文行',
        lineHeight: 20,
      ),
    ]);
    expect(result.roles['ink:r:t'], 'body', reason: '多行拒绝');

    // 不在前 25% 纵向区间。
    result = await recoverWithRegions(const [
      RegionSpec(
        regionId: 'r:b',
        top: 20,
        left: 0,
        text: '正文行',
        lineHeight: 20,
      ),
      RegionSpec(
        regionId: 'r:t',
        top: 400,
        left: 0,
        text: '晚出现的标题',
        lineHeight: 36,
      ),
      RegionSpec(
        regionId: 'r:b2',
        top: 450,
        left: 0,
        text: '更多正文',
        lineHeight: 20,
      ),
    ]);
    expect(result.roles['ink:r:t'], 'body', reason: '不在前 25% 区间');
  });

  test('图注：紧邻唯一 figure 目标建立关系；无唯一目标不入关系', () async {
    final scene = Scene().addElement(
      ImageElement(
        id: const ElementId('img-1'),
        x: 0,
        y: 300,
        width: 200,
        height: 150,
        fileId: 'file-1',
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      ),
    );
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:cap', top: 460, left: 60, text: '图1 架构示意'),
    ], scene: scene);
    expect(result.captions, hasLength(1));
    expect(result.captions.single.captionUnitId, 'ink:r:cap');
    expect(result.captions.single.targetUnitId, 'native:img-1');
    expect(result.roles['ink:r:cap'], 'caption');

    // 两个 figure 横向并列、同距 → 无唯一目标，不建立关系。
    final twoFigures = Scene()
        .addElement(
          ImageElement(
            id: const ElementId('img-1'),
            x: 0,
            y: 300,
            width: 100,
            height: 150,
            fileId: 'file-1',
            seed: 7,
            versionNonce: 11,
            updated: 1000,
          ),
        )
        .addElement(
          ImageElement(
            id: const ElementId('img-2'),
            x: 100,
            y: 300,
            width: 100,
            height: 150,
            fileId: 'file-1',
            seed: 7,
            versionNonce: 11,
            updated: 1000,
          ),
        );
    // 无唯一目标 → 结构触发表命中（captionWithoutUniqueTarget）；
    // 模型被拒回退本地后仍不建立关系。
    final ambiguous = await recoverWithRegions(
      const [
        RegionSpec(regionId: 'r:cap', top: 460, left: 90, text: '图1 架构示意'),
      ],
      scene: twoFigures,
      send: (request) async => null,
    );
    expect(ambiguous.captions, isEmpty);
    expect(ambiguous.modelRejected, isTrue);
    expect(ambiguous.usedModel, isTrue);
  });

  test('原生文本绕过 OCR：TextElement 直接入 unit（typed）', () async {
    final scene = Scene().addElement(
      TextElement(
        id: const ElementId('text-1'),
        x: 0,
        y: 20,
        width: 200,
        height: 40,
        text: '原生标题',
        fontSize: 28,
        fontFamily: 'Excalifont',
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      ),
    );
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:body', top: 100, left: 0, text: '手写正文'),
    ], scene: scene);
    final typed = result.units.firstWhere(
      (unit) => unit.unitId == 'native:text-1',
    );
    expect(typed.kind, RecognitionUnitKind.typed);
    expect(typed.text, '原生标题');
    expect(result.roles['native:text-1'], 'title', reason: '原生大字号文本同样参与标题判定');
  });

  test('阅读顺序：行带优先、同行按左缘；figure 参与', () async {
    final scene = Scene().addElement(
      ImageElement(
        id: const ElementId('img-1'),
        x: 300,
        y: 105,
        width: 100,
        height: 90,
        fileId: 'file-1',
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      ),
    );
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:b', top: 130, left: 0, text: '第二行'),
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '第一行'),
      RegionSpec(regionId: 'r:c', top: 102, left: 150, text: '同带靠右'),
    ], scene: scene);
    expect(result.readingOrder.first, 'ink:r:a');
    expect(
      result.readingOrder.indexOf('ink:r:c'),
      lessThan(result.readingOrder.indexOf('ink:r:b')),
      reason: '同带按左缘',
    );
    expect(result.readingOrder, contains('native:img-1'));
  });

  test('保留区域成为 preserved 障碍单元（native 命名空间）', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:ok', top: 100, left: 0, text: '可识别'),
      RegionSpec(regionId: 'r:bad', top: 200, left: 0),
    ]);
    final preserved = result.units.firstWhere(
      (unit) => unit.kind == RecognitionUnitKind.preserved,
    );
    expect(preserved.unitId, 'native:s-bad');
    expect(preserved.text, isNull);
    expect(result.readingOrder, contains('native:s-bad'));
  });
}
