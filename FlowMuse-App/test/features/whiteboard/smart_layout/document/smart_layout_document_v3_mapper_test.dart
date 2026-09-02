import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/document/smart_layout_document_v3_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-601A：SmartLayoutDocument 版本映射——多版本 fixture 深度一致、
/// 旧读新写未知字段零丢失、确定性默认、非法版本拒绝；既有序列化框架
/// （editor_core toJson/fromJson 路径）零改动。
void main() {
  SmartLayoutBlock block(
    String id,
    String type,
    String text, {
    int order = 0,
    String? latex,
    List<String> sourceIds = const [],
  }) => SmartLayoutBlock(
    id: id,
    type: type,
    text: text,
    latex: latex,
    order: order,
    sourceIds: sourceIds,
  );

  final nativeDoc = SmartLayoutDocument(
    version: 1,
    generatedAt: 1725000001000,
    blocks: [
      block('b1', 'heading', '会议纪要', order: 0, sourceIds: ['ink-1']),
      block('b2', 'paragraph', '第一段正文', order: 1, sourceIds: ['ink-2']),
      block(
        'b3',
        'math',
        'E=mc^2',
        order: 2,
        latex: 'E = mc^2',
        sourceIds: ['ink-3'],
      ),
    ],
  );

  Map<String, Object?> nativeJson() => {
    'version': 1,
    'generatedAt': 1725000001000,
    'blocks': [
      {
        'id': 'b1',
        'type': 'heading',
        'text': '会议纪要',
        'order': 0,
        'sourceIds': ['ink-1'],
      },
      {
        'id': 'b2',
        'type': 'paragraph',
        'text': '第一段正文',
        'order': 1,
        'sourceIds': ['ink-2'],
      },
      {'id': 'b3', 'type': 'math', 'text': 'E=mc^2', 'order': 2, 'latex': 'E = mc^2', 'sourceIds': ['ink-3']},
    ],
  };

  /// legacy 存量：无 version、无 generatedAt、块缺 id（前版本化写出的
  /// 真实历史形态）。
  Map<String, Object?> legacyJson() => {
    'blocks': [
      {'type': 'paragraph', 'text': '旧文档第一块', 'order': 1},
      {'type': 'heading', 'text': '旧标题', 'order': 0},
    ],
  };

  /// 未来版本：version 2 + 文档级/块级未来字段（前向兼容读入）。
  Map<String, Object?> futureJson() => {
    'version': 2,
    'generatedAt': 1725000002000,
    'futureTopField': {'hint': 'v2 专属'},
    'blocks': [
      {
        'id': 'f1',
        'type': 'paragraph',
        'text': '未来块',
        'order': 0,
        'futureBlockField': 7,
      },
    ],
  };

  group('版本映射：多版本 fixture 深度一致', () {
    test('native v1 读入：版本/字段全保真，零未知字段', () {
      final read = SmartLayoutDocumentV3Mapper.readFromJson(nativeJson());
      expect(read.readVersion, 1);
      expect(read.versionWasAbsent, isFalse);
      expect(read.upgradedToCurrent, isFalse);
      expect(read.unknownDocumentFields, isEmpty);
      expect(read.unknownFieldsByBlockId, isEmpty);
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(read.document, nativeDoc),
        isTrue,
      );
    });

    test('legacy 存量读入：确定性默认（version=1/generatedAt=0/块 id 按序）', () {
      final read = SmartLayoutDocumentV3Mapper.readFromJson(legacyJson());
      expect(read.readVersion, SmartLayoutDocumentV3Mapper.legacyAbsentVersion);
      expect(read.versionWasAbsent, isTrue);
      expect(read.upgradedToCurrent, isTrue);
      expect(read.document.generatedAt, 0);
      expect(read.document.blocks.map((b) => b.id), [
        'legacy-block-0',
        'legacy-block-1',
      ]);
      // 双跑确定性：同输入两次读入深度一致（既有 fromJson 随机 id/now
      // 时间默认被 mapper 前置注入取代）。
      final again = SmartLayoutDocumentV3Mapper.readFromJson(legacyJson());
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(read.document, again.document),
        isTrue,
      );
    });

    test('未来 v2 读入：可读 + 未知字段捕获（文档级与块级分开）', () {
      final read = SmartLayoutDocumentV3Mapper.readFromJson(futureJson());
      expect(read.readVersion, 2);
      expect(read.upgradedToCurrent, isTrue);
      expect(read.unknownDocumentFields['futureTopField'], {
        'hint': 'v2 专属',
      });
      expect(read.unknownFieldsByBlockId['f1']!['futureBlockField'], 7);
    });

    test('非法输入拒收：负版本/非数值版本/blocks 非数组', () {
      expect(
        () => SmartLayoutDocumentV3Mapper.readFromJson({
          ...nativeJson(),
          'version': -1,
        }),
        throwsFormatException,
      );
      expect(
        () => SmartLayoutDocumentV3Mapper.readFromJson({
          ...nativeJson(),
          'version': 'one',
        }),
        throwsFormatException,
      );
      expect(
        () => SmartLayoutDocumentV3Mapper.readFromJson({
          ...nativeJson(),
          'blocks': 'nope',
        }),
        throwsFormatException,
      );
    });
  });

  group('旧读新写：未知字段零丢失 + 版本归一', () {
    test('未来 v2 旧读新写：写回 version=1 且未来字段原样保留', () {
      final read = SmartLayoutDocumentV3Mapper.readFromJson(futureJson());
      final written = SmartLayoutDocumentV3Mapper.writeJson(
        read.document,
        read: read,
      );
      expect(written['version'], SmartLayoutDocumentV3Mapper.currentVersion);
      expect(written['futureTopField'], {'hint': 'v2 专属'});
      final blockJson = (written['blocks'] as List).single as Map;
      expect(blockJson['futureBlockField'], 7);
      // 回读闭环：未知字段再次被捕获（重开不劣化）。
      final reread = SmartLayoutDocumentV3Mapper.readFromJson(
        Map<String, Object?>.from(written),
      );
      expect(reread.unknownDocumentFields['futureTopField'], {
        'hint': 'v2 专属',
      });
      expect(reread.unknownFieldsByBlockId['f1']!['futureBlockField'], 7);
    });

    test('legacy 旧读新写：写回当前版本且重开深度一致', () {
      final read = SmartLayoutDocumentV3Mapper.readFromJson(legacyJson());
      final written = SmartLayoutDocumentV3Mapper.writeJson(
        read.document,
        read: read,
      );
      expect(written['version'], 1);
      expect(written['generatedAt'], 0);
      final reread = SmartLayoutDocumentV3Mapper.readFromJson(
        Map<String, Object?>.from(written),
      );
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(read.document, reread.document),
        isTrue,
      );
      expect(reread.versionWasAbsent, isFalse);
    });

    test('native 写回与既有 SmartLayoutDocument.toJson 结构一致（仅版本键显式）',
        () {
      final written = SmartLayoutDocumentV3Mapper.writeJson(nativeDoc);
      // 序列化框架不变：除 version 显式归一外，结构=既有 toJson。
      final existing = nativeDoc.toJson();
      expect(written.keys.toSet(), existing.keys.toSet());
      expect(written['blocks'], existing['blocks']);
      expect(written['generatedAt'], existing['generatedAt']);
    });
  });

  group('deepEquals 判别力', () {
    test('同文档相等；块文本/order/版本号差异可判别', () {
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(nativeDoc, nativeDoc),
        isTrue,
      );
      final changedText = SmartLayoutDocument(
        version: 1,
        generatedAt: 1725000001000,
        blocks: [
          nativeDoc.blocks[0],
          SmartLayoutBlock(
            id: 'b2',
            type: 'paragraph',
            text: '改写文本',
            order: 1,
          ),
          nativeDoc.blocks[2],
        ],
      );
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(nativeDoc, changedText),
        isFalse,
      );
      final changedOrder = SmartLayoutDocument(
        version: 1,
        generatedAt: 1725000001000,
        blocks: [
          nativeDoc.blocks[0],
          ...nativeDoc.blocks.sublist(1)
              .map((b) => SmartLayoutBlock(
                    id: b.id,
                    type: b.type,
                    text: b.text,
                    latex: b.latex,
                    order: b.order == 1 ? 5 : b.order,
                    sourceIds: b.sourceIds,
                  )),
        ],
      );
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(nativeDoc, changedOrder),
        isFalse,
      );
    });
  });
}
