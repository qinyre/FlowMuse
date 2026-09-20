import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/composition_policy.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';

import '../rendering/flow_muse_test_scene.dart' show onePixelPng;
import 'structure_test_helpers.dart';

/// B：程序构造的八类页面，不是在线 OCR 或真机质量评测。
/// 覆盖识别事实 → 语义 → 排名第一的实际渲染/物化产物，不能只验中间角色。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  const shortList = [
    RegionSpec(
      regionId: 'r:title',
      top: 120,
      left: 150,
      text: '你好，这是标题',
      lineHeight: 40,
    ),
    RegionSpec(regionId: 'r:a', top: 190, left: 150, text: '1. 真的 假的'),
    RegionSpec(regionId: 'r:b', top: 225, left: 150, text: '2. 真的'),
    RegionSpec(regionId: 'r:c', top: 260, left: 150, text: '3. 假的'),
  ];
  final cases =
      <
        ({
          String name,
          List<RegionSpec> ink,
          bool figure,
          bool preserve,
          bool native,
        })
      >[
        (
          name: '历史标题短列表',
          ink: shortList,
          figure: false,
          preserve: false,
          native: false,
        ),
        (
          name: '短列表加小图',
          ink: shortList,
          figure: true,
          preserve: false,
          native: false,
        ),
        (
          name: '长段落',
          ink: [
            RegionSpec(
              regionId: 'r:a',
              top: 150,
              left: 150,
              text: List.filled(12, '长段落需要自然换行，不应形成横贯整页的文字带。').join(),
            ),
            const RegionSpec(
              regionId: 'r:b',
              top: 480,
              left: 150,
              text: '第二段内容保留。',
            ),
          ],
          figure: false,
          preserve: false,
          native: false,
        ),
        (
          name: '图下方图注',
          ink: const [
            RegionSpec(regionId: 'r:cap', top: 490, left: 160, text: '图1 示例'),
          ],
          figure: true,
          preserve: false,
          native: false,
        ),
        (
          name: '图上方图注',
          ink: const [
            RegionSpec(regionId: 'r:cap', top: 370, left: 160, text: '图1 示例'),
          ],
          figure: true,
          preserve: false,
          native: false,
        ),
        (
          name: '原生文字混手写',
          ink: shortList,
          figure: false,
          preserve: false,
          native: true,
        ),
        (
          name: '公式不可读保留',
          ink: const [
            RegionSpec(regionId: 'r:a', top: 160, left: 150, text: '公式说明'),
            RegionSpec(regionId: 'r:formula', top: 650, left: 650),
          ],
          figure: false,
          preserve: false,
          native: false,
        ),
        (
          name: '复杂图形保留',
          ink: shortList,
          figure: false,
          preserve: true,
          native: false,
        ),
      ];
  for (final example in cases) {
    test('默认结果：${example.name}', () async {
      var scene = Scene().addElement(
        RectangleElement(
          id: const ElementId('page'),
          x: 0,
          y: 0,
          width: 1200,
          height: 900,
          seed: 7,
          versionNonce: 11,
          updated: 1000,
          customData: const {
            'flowMuse': {'role': 'page', 'pageId': 'page-1'},
          },
        ),
      );
      if (example.figure) {
        scene = scene
            .addElement(
              ImageElement(
                id: const ElementId('figure'),
                x: 150,
                y: 400,
                width: 80,
                height: 80,
                fileId: 'picture',
                seed: 7,
                versionNonce: 11,
                updated: 1000,
                customData: const {
                  'flowMuse': {'pageId': 'page-1'},
                },
              ),
            )
            .addFile(
              'picture',
              ImageFile(mimeType: 'image/png', bytes: onePixelPng),
            );
      }
      if (example.native) {
        scene = scene.addElement(
          TextElement(
            id: const ElementId('typed'),
            x: 150,
            y: 500,
            width: 250,
            height: 25,
            text: '原生文字不重新识别',
            fontSize: 20,
            fontFamily: 'Excalifont',
            seed: 7,
            versionNonce: 11,
            updated: 1000,
            customData: const {
              'flowMuse': {'pageId': 'page-1'},
            },
          ),
        );
      }
      if (example.preserve) {
        scene = scene.addElement(
          RectangleElement(
            id: const ElementId('drawing'),
            x: 900,
            y: 650,
            width: 100,
            height: 100,
            seed: 7,
            versionNonce: 11,
            updated: 1000,
            customData: const {
              'flowMuse': {'pageId': 'page-1'},
            },
          ),
        );
      }
      final result = await sessionOf(
        example.ink,
        scene: scene,
        pageId: 'page-1',
      );
      const adapter = RecognitionSemanticAdapter();
      final settled = adapter.settle(result);
      final measure = TextMeasureAdapter();
      final semantic = adapter.assemble(
        settled,
        measure: measure,
        tokens: SmartLayoutDesignTokens.v1,
      );
      final sourceFingerprint = SceneFingerprint.of(result.scene);
      final snapshot = const SnapshotExtractor().extract(
        scene: result.scene,
        pageId: 'page-1',
        sceneRevision: SceneRevision(
          epoch: 0,
          revision: 5,
          fingerprint: sourceFingerprint,
        ),
      );
      final outcome =
          await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
            baseScene: result.scene,
            snapshot: snapshot,
            semantic: semantic,
            recognition: settled,
            measure: measure,
          );
      expect(
        outcome,
        isA<RealGenerationSucceeded>(),
        reason: outcome is RealGenerationFailed
            ? '${outcome.reason}: ${outcome.detail}'
            : example.name,
      );
      final candidates = (outcome as RealGenerationSucceeded).candidates;
      addTearDown(() {
        for (final candidate in candidates) {
          candidate.dispose();
        }
      });
      expect(candidates, isNotEmpty, reason: '不能以空候选冒充质量通过');
      final best = candidates.first;
      expect(best.hardReport.passed, isTrue);
      expect(best.snapshot.hasMissingResources, isFalse);
      expect(
        SceneFingerprint.of(result.scene),
        sourceFingerprint,
        reason: '预览不写原稿',
      );
      final output =
          best.reduced.scene.activeElements.whereType<TextElement>().toList()
            ..sort((a, b) => a.y.compareTo(b.y));
      final expected = [
        for (final spec in example.ink)
          if (spec.text != null) spec.text!,
      ];
      if (example.native) expected.add('原生文字不重新识别');
      expect(
        output.map((e) => e.text),
        orderedEquals(expected),
        reason: '默认结果正文无丢失、重复、乱序',
      );
      for (final sourceId in semantic.document.preservedSourceIds) {
        final before = result.scene.activeElements.firstWhere(
          (e) => e.id.value == sourceId,
        );
        final after = best.reduced.scene.activeElements.firstWhere(
          (e) => e.id.value == sourceId,
        );
        expect(identical(before, after), isTrue, reason: '保留原件不可改写');
      }
      if (identical(example.ink, shortList)) {
        expect(best.diversityKey, anyOf('single', 'conservativeLayout'));
        expect(output.take(4).map((e) => e.x).toSet(), hasLength(1));
        expect(output.first.fontSize, greaterThan(output[1].fontSize));
        expect(
          output[3].y + output[3].height,
          lessThan(400),
          reason: '短页允许留白，不为填满页面拉开清单',
        );
      }
      if (example.figure) {
        final figure = best.reduced.scene.activeElements
            .whereType<ImageElement>()
            .single;
        expect(figure.width, lessThanOrEqualTo(80.001), reason: '小图不能铺满整栏');
        if (example.name.startsWith('图')) {
          final caption = output.single;
          expect(caption.x, closeTo(figure.x, .001));
          if (example.name == '图上方图注') {
            expect(caption.y + caption.height, lessThan(figure.y));
          } else {
            expect(caption.y, greaterThan(figure.y + figure.height));
          }
        }
      }
      if (example.name == '长段落') {
        expect(
          output.first.width,
          lessThanOrEqualTo(
            const CompositionPolicy(pageWidth: 1200).maxTextWidth,
          ),
          reason: '新策略按页宽归一，最多约 32 字；旧 tokens/v1 的 560 不再是生产链行宽',
        );
        expect(
          output.first.height,
          greaterThan(output.first.fontSize * output.first.lineHeight * 2),
          reason: '长文必须真实换行，不能变成整页文字带',
        );
      }
    });
  }
}
