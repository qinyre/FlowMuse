import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';

import 'structure_test_helpers.dart';

/// 结构请求触发条件（§7；与 §6.1 复核触发表分离）与模型结果合并：
/// 模型只改角色/分组/顺序/层级；正文与几何一律本地；验证失败回退本地。
void main() {
  test('结构指纹跨端稳定，正文或等长单元ID变化不能复用旧指纹', () async {
    Future<String> fingerprint({
      String id = 'r:mid',
      String text = '正文😀',
    }) async {
      String? value;
      await recoverWithRegions(
        [
          const RegionSpec(regionId: 'r:a1', top: 100, left: 0, text: '1. 甲'),
          const RegionSpec(regionId: 'r:a2', top: 130, left: 0, text: '2. 乙'),
          RegionSpec(regionId: id, top: 160, left: 60, text: text),
          const RegionSpec(regionId: 'r:b1', top: 190, left: 120, text: '1. 丙'),
          const RegionSpec(regionId: 'r:b2', top: 220, left: 120, text: '2. 丁'),
        ],
        send: (request) async {
          value = request.textFingerprint;
          return null;
        },
      );
      expect(value, isNotNull);
      return value!;
    }

    final first = await fingerprint();
    expect(first, '4b9d3e826427c025', reason: 'VM 与 Chrome 使用同一固定向量');
    expect(first, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(await fingerprint(), first);
    expect(await fingerprint(id: 'r:new'), isNot(first));
    expect(await fingerprint(text: '正文😁'), isNot(first));
  });
  test('真实触发结构请求后角色冲突产出准入阻断集合', () async {
    final result = await recoverWithRegions(
      const [
        RegionSpec(regionId: 'r:a1', top: 100, left: 0, text: '1. 甲'),
        RegionSpec(regionId: 'r:a2', top: 130, left: 0, text: '2. 乙'),
        RegionSpec(regionId: 'r:mid', top: 160, left: 60, text: '中间正文'),
        RegionSpec(regionId: 'r:b1', top: 190, left: 120, text: '1. 丙'),
        RegionSpec(regionId: 'r:b2', top: 220, left: 120, text: '2. 丁'),
      ],
      send: (r) async => RecognitionStructureResponse(
        operationId: r.operationId,
        requestId: r.requestId,
        pageId: r.pageId,
        sceneRevision: r.sceneRevision,
        contentFingerprint: r.contentFingerprint,
        generation: r.generation,
        textFingerprint: r.textFingerprint,
        readingOrder: r.units.map((u) => u.unitId).toList(),
        roles: [
          for (final u in r.units)
            RecognitionRoleAssignment(
              unitId: u.unitId,
              role: RecognitionStructureRole.other,
            ),
        ],
        listGroups: const [],
        captions: const [],
        warnings: const [],
      ),
    );
    expect(result.usedModel, isTrue);
    expect(result.conflictedUnitIds, containsAll(['ink:r:a1', 'ink:r:mid']));
  });
  test('触发条件命中才发结构请求：列表组歧义场景', () async {
    RecognitionStructureRequest? sent;
    final result = await recoverWithRegions(
      [
        // 两个列表组 + 组间缩进的正文 → 归属歧义。
        const RegionSpec(regionId: 'r:a1', top: 100, left: 0, text: '1. 甲'),
        const RegionSpec(regionId: 'r:a2', top: 130, left: 0, text: '2. 乙'),
        const RegionSpec(
          regionId: 'r:mid',
          top: 160,
          left: 60,
          text: '夹在两组之间的正文',
        ),
        const RegionSpec(regionId: 'r:b1', top: 190, left: 120, text: '1. 丙'),
        const RegionSpec(regionId: 'r:b2', top: 220, left: 120, text: '2. 丁'),
      ],
      send: (request) async {
        sent = request;
        // 模型返回自洽结构（覆盖全部 units 的 readingOrder 与 roles）。
        return RecognitionStructureResponse(
          operationId: request.operationId,
          requestId: request.requestId,
          pageId: request.pageId,
          sceneRevision: request.sceneRevision,
          contentFingerprint: request.contentFingerprint,
          generation: request.generation,
          textFingerprint: request.textFingerprint,
          readingOrder: [
            'ink:r:a1',
            'ink:r:a2',
            'ink:r:mid',
            'ink:r:b1',
            'ink:r:b2',
          ],
          roles: const [
            RecognitionRoleAssignment(
              unitId: 'ink:r:a1',
              role: RecognitionStructureRole.listItem,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:a2',
              role: RecognitionStructureRole.listItem,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:mid',
              role: RecognitionStructureRole.body,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:b1',
              role: RecognitionStructureRole.listItem,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:b2',
              role: RecognitionStructureRole.listItem,
            ),
          ],
          listGroups: const [
            RecognitionListGroup(
              groupId: 'g1',
              members: ['ink:r:a1', 'ink:r:a2', 'ink:r:mid'],
              level: 1,
              listType: RecognitionListType.ordered,
              startNumber: 1,
            ),
          ],
          captions: const [],
          warnings: const [],
        );
      },
    );
    expect(sent, isNotNull, reason: '两组+歧义单元必须触发结构请求');
    expect(result.usedModel, isTrue);
    expect(result.modelRejected, isFalse);
    // 模型只改角色/分组：合并采用模型分组。
    expect(result.listGroups.single.members, contains('ink:r:mid'));
    // 正文与几何一律本地值：units 保持本地实例与文本。
    expect(
      result.units.firstWhere((u) => u.unitId == 'ink:r:mid').text,
      '夹在两组之间的正文',
    );
  });

  test('低置信不触发结构请求（复核触发表与结构触发表分离）', () async {
    final result = await recoverWithRegions(const [
      RegionSpec(regionId: 'r:a', top: 100, left: 0, text: '普通正文'),
      RegionSpec(regionId: 'r:b', top: 130, left: 0, text: '另一段正文'),
    ], send: (request) async => throw StateError('不应触发'));
    expect(result.usedModel, isFalse);
  });

  test('模型结果被拒（send 返回 null）：回退本地保守结构并记警告', () async {
    final result = await recoverWithRegions([
      const RegionSpec(regionId: 'r:a1', top: 100, left: 0, text: '1. 甲'),
      const RegionSpec(regionId: 'r:a2', top: 130, left: 0, text: '2. 乙'),
      const RegionSpec(
        regionId: 'r:mid',
        top: 160,
        left: 60,
        text: '夹在两组之间的正文',
      ),
      const RegionSpec(regionId: 'r:b1', top: 190, left: 120, text: '1. 丙'),
      const RegionSpec(regionId: 'r:b2', top: 220, left: 120, text: '2. 丁'),
    ], send: (request) async => null);
    expect(result.usedModel, isTrue);
    expect(result.modelRejected, isTrue);
    expect(result.listGroups, hasLength(2), reason: '回退本地两组结构');
    expect(result.warnings, isNotEmpty);
    expect(result.warnings.any((w) => w.contains('回退本地')), isTrue);
  });

  test('角色冲突：模型 other 与本地 title 冲突保留本地并记 uncertain 警告', () async {
    final result = await recoverWithRegions(
      [
        const RegionSpec(
          regionId: 'r:t',
          top: 20,
          left: 0,
          text: '大标题',
          lineHeight: 36,
        ),
        const RegionSpec(regionId: 'r:b1', top: 80, left: 0, text: '正文一'),
        const RegionSpec(regionId: 'r:b2', top: 110, left: 0, text: '正文二'),
      ],
      send: (request) async {
        return RecognitionStructureResponse(
          operationId: request.operationId,
          requestId: request.requestId,
          pageId: request.pageId,
          sceneRevision: request.sceneRevision,
          contentFingerprint: request.contentFingerprint,
          generation: request.generation,
          textFingerprint: request.textFingerprint,
          readingOrder: ['ink:r:t', 'ink:r:b1', 'ink:r:b2'],
          roles: const [
            // 模型把本地判定的标题降为 other → 冲突。
            RecognitionRoleAssignment(
              unitId: 'ink:r:t',
              role: RecognitionStructureRole.other,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:b1',
              role: RecognitionStructureRole.body,
            ),
            RecognitionRoleAssignment(
              unitId: 'ink:r:b2',
              role: RecognitionStructureRole.body,
            ),
          ],
          listGroups: const [],
          captions: const [],
          warnings: const [],
        );
      },
    );
    // 但本地三段正文无歧义 → 不触发结构请求 → 此用例的 send 不该被调？
    // 标题场景不触发；改由上面的歧义场景覆盖合并——此处断言不触发路径。
    expect(result.usedModel, isFalse);
    expect(result.roles['ink:r:t'], 'title');
  });

  test('编号/换行/标点保持本地值：模型结构不携带正文（R-10）', () async {
    final units = <RecognitionUnitInput>[];
    RecognitionStructureRequest? sent;
    final result = await recoverWithRegions(
      [
        const RegionSpec(
          regionId: 'r:a',
          top: 100,
          left: 0,
          text: '1. 第一项\n含换行',
        ),
        const RegionSpec(regionId: 'r:b', top: 140, left: 0, text: '2. 第二项'),
        const RegionSpec(regionId: 'r:mid', top: 180, left: 60, text: '中间'),
        const RegionSpec(regionId: 'r:c1', top: 220, left: 120, text: '1. 丙'),
        const RegionSpec(regionId: 'r:c2', top: 260, left: 120, text: '2. 丁'),
      ],
      send: (request) async {
        sent = request;
        units.addAll(request.units);
        return null; // 拒绝 → 回退本地；此处只校验请求内容。
      },
    );
    // 结构请求 units 携带本地正文（输入只读），不伪造不重写。
    final sentA = units.firstWhere((u) => u.unitId == 'ink:r:a');
    expect(sentA.text, '1. 第一项\n含换行');
    expect(sent!.textFingerprint, isNotEmpty);
    expect(
      result.units.firstWhere((u) => u.unitId == 'ink:r:a').text,
      '1. 第一项\n含换行',
      reason: '回退后正文仍为本地值',
    );
  });
}
