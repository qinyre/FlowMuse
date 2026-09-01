import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/document/smart_layout_document_compatibility.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/document/smart_layout_document_v3_mapper.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/patch/smart_layout_scene_patch_builder.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

/// V3-601A：文档重开与既有导出兼容——重开/undo/redo/reconcile 全部走
/// 既有机制（documentOp 事务 + reducer + upsertRemoteElements），复用
/// SmartLayoutExporter 验证导出字符、顺序和关系；不新增格式或 importer。
void main() {
  SmartLayoutDocument doc(String marker, {int generatedAt = 1725000001000}) =>
      SmartLayoutDocument(
        version: 1,
        generatedAt: generatedAt,
        blocks: [
          SmartLayoutBlock(
            id: 'b1-$marker',
            type: 'heading',
            text: '标题-$marker',
            order: 0,
            sourceIds: ['ink-1'],
          ),
          SmartLayoutBlock(
            id: 'b2-$marker',
            type: 'math',
            text: 'E=mc^2',
            latex: 'E = mc^2',
            order: 2,
            sourceIds: ['ink-3'],
          ),
          SmartLayoutBlock(
            id: 'b3-$marker',
            type: 'paragraph',
            text: '正文-$marker',
            order: 1,
            sourceIds: ['ink-2'],
          ),
        ],
      );

  RectangleElement rect(String id, {int version = 1, double x = 10}) =>
      RectangleElement(
        id: ElementId(id),
        x: x,
        y: 10,
        width: 40,
        height: 40,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: version,
      );

  group('重开一致性（确定性默认）', () {
    test('native/legacy/future 三类 fixture 重开 round-trip 深度一致', () {
      expect(SmartLayoutDocumentCompatibility.reopenRoundTrip(doc('a')), isTrue);

      // legacy：无 version/generatedAt、块缺 id——经 mapper 确定性默认后重开一致。
      final legacyRead = SmartLayoutDocumentV3Mapper.readFromJson({
        'blocks': [
          {'type': 'paragraph', 'text': '旧块', 'order': 0},
        ],
      });
      expect(
        SmartLayoutDocumentCompatibility.reopenRoundTrip(legacyRead.document),
        isTrue,
      );

      // future v2：未知字段保真下重开一致。
      final futureRead = SmartLayoutDocumentV3Mapper.readFromJson({
        'version': 2,
        'generatedAt': 1725000002000,
        'futureTopField': 3,
        'blocks': [
          {'id': 'f1', 'type': 'paragraph', 'text': '未来块', 'order': 0},
        ],
      });
      expect(
        SmartLayoutDocumentCompatibility.reopenRoundTrip(futureRead.document),
        isTrue,
      );
    });
  });

  group('undo/redo：文档通道事务经真实 documentOp+reducer', () {
    test('replace→replace→undo→redo 全链文档状态精确往返', () {
      final d1 = doc('v1');
      final d2 = doc('v2', generatedAt: 1725000002000);
      var scene = Scene().addElement(rect('r1'));

      // commit d1（基线 null → d1）。
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d1,
        revisionCount: 1,
      );
      expect(SmartLayoutDocumentV3Mapper.deepEquals(scene.smartLayout!, d1), isTrue);

      // commit d2。
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d2,
        revisionCount: 2,
      );
      expect(SmartLayoutDocumentV3Mapper.deepEquals(scene.smartLayout!, d2), isTrue);

      // undo：历史回放前一文档状态（replace d1，与 pushHistory 同粒度）。
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d1,
        revisionCount: 3,
      );
      expect(SmartLayoutDocumentV3Mapper.deepEquals(scene.smartLayout!, d1), isTrue);

      // redo：回到 d2。
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d2,
        revisionCount: 4,
      );
      expect(SmartLayoutDocumentV3Mapper.deepEquals(scene.smartLayout!, d2), isTrue);

      // 元素通道全程未被文档事务触碰。
      expect(scene.elements.single.id.value, 'r1');
      expect(scene.elements.single.version, 1);
    });

    test('clear 事务：回到无文档基线（undo replace 的逆操作）', () {
      final d1 = doc('v1');
      var scene = Scene();
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d1,
        revisionCount: 1,
      );
      expect(scene.smartLayout, isNotNull);
      scene = SmartLayoutDocumentCompatibility.applyDocumentClear(
        base: scene,
        revisionCount: 2,
      );
      expect(scene.smartLayout, isNull);
    });

    test('documentOp 是 patch 触碰文档通道的唯一入口（写集口径）', () {
      // 纯文档事务：写集 touchesDocument 为真。
      final documentPatch = SmartLayoutScenePatchBuilder(
        baseScene: Scene(),
        baseRevision: SceneRevision(
          epoch: 0,
          revision: 0,
          fingerprint: SceneFingerprint.of(Scene()),
        ),
        sourceCoverage: SourceCoverageLedger.pending(const []),
      )..replaceSmartLayoutDocument(doc('x'));

      final documentBuilt = documentPatch.build();
      expect(
        SmartLayoutDocumentCompatibility.patchTouchesDocumentChannel(
          documentBuilt,
        ),
        isTrue,
      );
      // 写集口径与 documentOp 存在性一致（V3-502 冲突判定的权威面）。
      expect(documentBuilt.writeSet.touchesDocument, documentBuilt.documentOp != null);

      // 纯元素事务：不得隐式触碰文档通道。
      final elementPatch = SmartLayoutScenePatchBuilder(
        baseScene: Scene(),
        baseRevision: SceneRevision(
          epoch: 0,
          revision: 0,
          fingerprint: SceneFingerprint.of(Scene()),
        ),
        sourceCoverage: SourceCoverageLedger.pending(const []),
      )..addElement(rect('n1'));

      final elementBuilt = elementPatch.build();
      expect(elementBuilt.documentOp, isNull);
      expect(
        SmartLayoutDocumentCompatibility.patchTouchesDocumentChannel(
          elementBuilt,
        ),
        isFalse,
      );
    });
  });

  group('reconcile：元素通道与文档通道隔离', () {
    test('远端元素合并不触碰 smartLayout（文档单写者通道）', () {
      final d1 = doc('v1');
      var scene = Scene()
          .addElement(rect('r1'))
          .addElement(rect('r2', version: 2));
      scene = SmartLayoutDocumentCompatibility.applyDocumentReplace(
        base: scene,
        document: d1,
        revisionCount: 1,
      );

      final merged = SmartLayoutDocumentCompatibility.mergeRemoteElements(
        scene,
        [rect('r2', version: 3, x: 999)],
      );
      // 元素通道：远端新版本胜出。
      expect(
        merged.elements.firstWhere((e) => e.id.value == 'r2').version,
        3,
      );
      // 文档通道：原样保留（deepEquals 而非 identical——隔离的是内容语义）。
      expect(
        SmartLayoutDocumentV3Mapper.deepEquals(merged.smartLayout!, d1),
        isTrue,
      );
    });
  });

  /// 导出转义专用 fixture：正文含 LaTeX 特殊字符（_ % # $ &）。
  SmartLayoutDocument escapeDoc() => SmartLayoutDocument(
    version: 1,
    generatedAt: 7,
    blocks: const [
      SmartLayoutBlock(id: 'e1', type: 'paragraph', text: 'a_b %c #d', order: 0),
    ],
  );

  group('既有导出兼容：复用 SmartLayoutExporter，不新增格式', () {
    test('导出字符/顺序/关系：order 排序、heading/math 映射、latex 优先', () {
      final markdown = SmartLayoutExporter.export(
        doc('exp'),
        SmartLayoutExportFormat.markdown,
      );
      expect(markdown, equals('# 标题-exp\n\n正文-exp\n\n\$\$\nE = mc^2\n\$\$\n'));

      final latex = SmartLayoutExporter.export(
        doc('exp'),
        SmartLayoutExportFormat.latex,
      );
      expect(latex, contains(r'\section*{标题-exp}'));
      expect(latex, contains(r'\[' '\n' 'E = mc^2' '\n' r'\]'));
      // 转义关系：正文经 _escapeLatex（特殊字符逐个映射）。
      final escaped = SmartLayoutExporter.export(
        escapeDoc(),
        SmartLayoutExportFormat.latex,
      );
      expect(escaped, contains(r'a\_b \%c \#d'));
    });

    test('多版本 fixture 同逻辑内容导出一致（版本/未知字段不影响导出）', () {
      final nativeRead = SmartLayoutDocumentV3Mapper.readFromJson({
        'version': 1,
        'generatedAt': 42,
        'blocks': [
          {'id': 'x1', 'type': 'paragraph', 'text': '同一段', 'order': 0},
        ],
      });
      final futureRead = SmartLayoutDocumentV3Mapper.readFromJson({
        'version': 3,
        'generatedAt': 42,
        'futureTop': [1, 2],
        'blocks': [
          {
            'id': 'x1',
            'type': 'paragraph',
            'text': '同一段',
            'order': 0,
            'futureBlock': 'z',
          },
        ],
      });
      expect(
        SmartLayoutExporter.export(
          nativeRead.document,
          SmartLayoutExportFormat.markdown,
        ),
        equals(
          SmartLayoutExporter.export(
            futureRead.document,
            SmartLayoutExportFormat.markdown,
          ),
        ),
      );
    });

    test('latex 缺失时 math 块回退原文（既有 exporter 语义）', () {
      final noLatex = SmartLayoutDocument(
        version: 1,
        generatedAt: 1,
        blocks: const [
          SmartLayoutBlock(id: 'm', type: 'math', text: 'a+b', order: 0),
        ],
      );
      expect(
        SmartLayoutExporter.export(noLatex, SmartLayoutExportFormat.markdown),
        contains('a+b'),
      );
    });
  });
}
