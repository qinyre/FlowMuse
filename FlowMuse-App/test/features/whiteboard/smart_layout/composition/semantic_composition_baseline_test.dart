import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/source_coverage_ledger.dart';

import 'fixtures/semantic_composition/pages.dart';

// 历史版本看图入口：复制本文件和 pages.dart 到 3356c9a 的隔离 checkout，
// 用同一批 integration_test 导出的 .excalidraw 运行。只用该基线已有 API，
// 不复制旧生产算法到当前链路。角色/关系来自独立 fixture，不调用模型。
// flutter test --dart-define=LAYOUT_BASELINE_INPUT_DIR=<绝对导出目录>
//   --dart-define=LAYOUT_EVIDENCE_CJK_FONT=<字体路径> <本文件>
const _input = String.fromEnvironment('LAYOUT_BASELINE_INPUT_DIR');
const _font = String.fromEnvironment('LAYOUT_EVIDENCE_CJK_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (_input.isEmpty || _font.isEmpty) {
    test('旧基线看图需显式输入与字体，在隔离旧 checkout 执行', () {}, skip: '非历史对比运行');
    return;
  }
  setUpAll(() async {
    await (FontLoader(
      'Excalifont',
    )..addFont(File(_font).readAsBytes().then(ByteData.sublistView))).load();
  });
  for (final page in effectPages) {
    test('旧算法默认结果 ${page.name}', () async {
      final doc = ExcalidrawJsonCodec.parse(
        await File('$_input/${page.name}.excalidraw').readAsString(),
      ).value;
      var scene = Scene();
      for (final e in doc.allElements) {
        // 两版使用同一完整范围，只比较构图，不把旧缺 pageId 漏图混入分数。
        scene = scene.addElement(
          e.copyWith(
            customData: {
              ...?e.customData,
              'flowMuse': {if (e.isCanvasPage) 'role': 'page', 'pageId': 'p'},
            },
          ),
        );
      }
      for (final f in doc.files.entries) {
        scene = scene.addFile(f.key, f.value);
      }
      String unit(String id) =>
          page.soft.containsKey(id) ? 'ink:r:$id' : 'native:$id';
      final kept = page.fixed ? ['fixed', 'arrow'] : <String>[];
      final all = [...page.order, ...kept];
      var ledger = SourceLedger.register(all).registerUnits(all.map(unit));
      for (final id in page.order) {
        ledger = ledger.consume(id, unit(id));
      }
      for (final id in kept) {
        ledger = ledger.preserve(id, SourcePreserveReason.binding);
      }
      final revision = SceneRevision(
        epoch: 0,
        revision: 0,
        fingerprint: SceneFingerprint.of(scene),
      );
      final blocks = <SemanticBlock>[];
      for (final id in all) {
        final ink = page.soft.containsKey(id);
        final text = page.texts[id];
        final figures = page.groups
            .where((g) => g.contains(id))
            .expand((g) => g.where((m) => !page.texts.containsKey(m)));
        blocks.add(
          SemanticBlock(
            id: unit(id),
            role: kept.contains(id)
                ? SemanticRole.unknown
                : page.titles.contains(id)
                ? SemanticRole.title
                : page.lists.contains(id)
                ? SemanticRole.list
                : page.captions.containsKey(id)
                ? SemanticRole.caption
                : text == null
                ? SemanticRole.figure
                : SemanticRole.body,
            sourceIds: [id],
            orderIndex: all.indexOf(id),
            confidence: 1,
            text: ink ? null : text,
            extras: {
              if (ink) 'transcribedText': text,
              if (page.captions[id] != null)
                'captionOf': unit(page.captions[id]!),
              // 旧协议一文一图上限；共同说明只关联第一图，不复制文字。
              if (text != null && figures.isNotEmpty)
                'relatedFigure': unit(figures.first),
              if (page.lists.contains(id)) ...{
                'listGroupId': 'list',
                'level': 1,
              },
            },
          ),
        );
      }
      final semantic = SemanticAssembly(
        document: SemanticDocument(
          formatVersion: 1,
          pageId: 'p',
          epoch: 0,
          revision: 0,
          fingerprint: revision.fingerprint.value,
          blocks: blocks,
          readingOrder: SemanticReadingOrder(
            orderedBlockIds: blocks.map((b) => b.id).toList(),
          ),
          conflicts: const [],
          consumedSourceIds: page.order,
          preservedSourceIds: kept,
        ),
        ledger: SourceCoverageLedger.pending(
          all,
        ).markConsumed(page.order).markPreserved(kept),
      );
      final recognition = RecognitionSessionResult(
        operationId: 'offline-baseline',
        generation: 1,
        pageId: 'p',
        scene: scene,
        sceneRevision: RecognitionSceneRevision(
          epoch: 0,
          revision: 0,
          fingerprint: revision.fingerprint.value,
        ),
        contentFingerprint: revision.fingerprint.value,
        regionRecords: [
          for (final id in page.soft.keys)
            RegionRecord(
              regionId: 'r:$id',
              bounds: const RecognitionBounds(
                left: 0,
                top: 0,
                width: 240,
                height: 70,
              ),
              targetSourceIds: [id],
              localLineHeight: 24,
            ),
        ],
        regionOutcomes: {
          for (final id in page.soft.keys)
            'r:$id': RegionReadOutcome(
              regionId: 'r:$id',
              status: RecognitionRegionStatus.recognized,
              targetSourceIds: [id],
              text: page.texts[id],
              confidence: 1,
            ),
        },
        ledger: ledger,
        assetIndex: RegionAssetIndex(),
      );
      final outcome =
          await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
            baseScene: scene,
            snapshot: const SnapshotExtractor().extract(
              scene: scene,
              pageId: 'p',
              sceneRevision: revision,
            ),
            semantic: semantic,
            recognition: recognition,
            measure: TextMeasureAdapter(),
          );
      // 不把旧算法无解包装成通过；导出原稿并报告真实失败原因供人工比较。
      final candidates = outcome is RealGenerationSucceeded
          ? outcome.candidates
          : null;
      final selected = candidates?.firstOrNull;
      debugPrint(
        'BASELINE ${page.name} ${selected?.diversityKey ?? (outcome is RealGenerationFailed ? '${outcome.reason}: ${outcome.detail}' : 'original')}',
      );
      final renderer = DraftSceneRenderer();
      final snapshot = await renderer.render(
        scene: selected?.reduced.scene ?? scene,
        viewport: const ViewportState(),
        pixelSize: ui.Size(1024, page.height),
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const ui.Color(0xfffffdf5), ui.BlendMode.src);
      canvas.drawImage(snapshot.image, ui.Offset.zero, ui.Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(1024, page.height.round());
      final dir = Directory('build/semantic-composition-baseline')
        ..createSync(recursive: true);
      await File('${dir.path}/${page.name}.png').writeAsBytes(
        (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
      image.dispose();
      picture.dispose();
      snapshot.dispose();
      renderer.dispose();
      for (final candidate in candidates ?? []) {
        candidate.dispose();
      }
    });
  }
}
