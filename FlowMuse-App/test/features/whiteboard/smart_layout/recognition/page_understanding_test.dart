import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/composition/layout_block_assembler.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/placement/flow_placer.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_json_reader.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';

import 'fake_recognition_transport.dart';

// 合成页面 + 假模型响应用于端到端接线回归，不冒充在线语义准确率评测。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('生产捕获：缺归属图片进入同一识别与布局范围，他页保留且纠错不丢图', () async {
    var scene = await _scene();
    final image = scene.activeElements.singleWhere(
      (e) => e.id.value == 'blue-image',
    );
    scene = scene
        .updateElement(image.copyWith(customData: const {}))
        .addElement(
          RectangleElement(
            id: const ElementId('second-page'),
            x: 1600,
            y: 0,
            width: 1400,
            height: 1200,
            customData: const {
              'flowMuse': {'role': 'page', 'pageId': 'page-2'},
            },
          ),
        )
        .addElement(
          TextElement(
            id: const ElementId('foreign-text'),
            x: 48,
            y: 32,
            width: 300,
            height: 48,
            text: '属于另一页的固定内容',
            fontFamily: 'Excalifont',
            customData: const {
              'flowMuse': {'pageId': 'page-2'},
            },
          ),
        );
    final controller = MarkdrawController()..loadScene(scene);
    addTearDown(controller.dispose);
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request =
            RecognitionRequest.fromJson(jsonDecode(body))
                as RecognitionStructureRequest;
        expect(
          request.units.map((u) => u.unitId),
          containsAll(['native:red-image', 'native:blue-image']),
        );
        expect(
          request.units.map((u) => u.unitId),
          isNot(contains('native:foreign-text')),
        );
        return (200, jsonEncode(_response(request).toJson()));
      },
    );
    final scope = SmartLayoutRealSessionScope.build(
      controller: controller,
      serverUri: Uri.parse('http://test.invalid'),
      pageId: 'page-1',
      post: transport.post,
    );
    addTearDown(scope.dispose);
    final before = SceneFingerprint.of(controller.currentScene);
    final ticket = scope.session.beginOperation();
    final result =
        await scope.dependencies.analysisRunner!(ticket)
            as SmartLayoutRecognitionSucceeded;
    expect(result.recognition.ledger.consumedCount, 6);
    expect(scope.dependencies.reviewContextBuilder!()!.excludedScopeReasons, {
      'foreign-text': 'other-page',
    });
    final candidates = await scope.dependencies.candidateChainFromDocument!(
      result,
      ticket,
    );
    expect(candidates, isNotEmpty, reason: '不能因他页页框超出当前页而拒绝所有候选');
    for (final c in candidates) {
      final output = {
        for (final e in c.reduced.scene.activeElements) e.id.value: e,
      };
      expect(
        output['foreign-text'],
        same(
          controller.currentScene.activeElements.singleWhere(
            (e) => e.id.value == 'foreign-text',
          ),
        ),
      );
      expect(output['blue-image']!.pageId, isNull, reason: '有效临时归属不能回写 Scene');
      final fixed = result.recognition.pageScope!.fixedBounds['foreign-text']!;
      for (final op in [
        ...c.patch.adds.map((o) => o.element),
        ...c.patch.updates.map((o) => o.element),
      ]) {
        final actual = conservativeVisualBounds(op);
        expect(
          actual.left >= fixed.right ||
              actual.right <= fixed.left ||
              actual.top >= fixed.bottom ||
              actual.bottom <= fixed.top,
          isTrue,
          reason: '可见他页固定内容必须被绕开（可以从侧方通过）',
        );
      }
      c.dispose();
    }
    final affected = scope.dependencies.correctionHandler(
      const RegionCorrectionIntent(
        kind: 'role',
        subjectIds: ['native:title'],
        detail: 'body',
      ),
    );
    final rerun = await scope.dependencies.rerunChain(affected.strokeSourceIds);
    expect(rerun, isNotEmpty);
    for (final c in rerun) {
      c.dispose();
    }
    expect(transport.requests, hasLength(1), reason: '语义重排复用捕获范围，不重新识别');
    expect(SceneFingerprint.of(controller.currentScene), before);
  });

  test('整页含两张真图：跨距离配对、同字号标题、完整正文传到实际候选', () async {
    final scene = await _scene();
    final before = SceneFingerprint.of(scene);
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request =
            RecognitionRequest.fromJson(jsonDecode(body))
                as RecognitionStructureRequest;
        expect(request.includeFigureTextLinks, isTrue);
        expect(
          request.units.singleWhere((u) => u.unitId == 'native:red-text').text,
          _redText,
        );
        expect(
          request.overviewPngBase64!.length,
          lessThanOrEqualTo(recognitionMaxImageBase64Chars),
        );
        final codec = await ui.instantiateImageCodec(
          base64Decode(request.overviewPngBase64!),
        );
        final frame = await codec.getNextFrame();
        try {
          final image = frame.image;
          expect(image.width, lessThanOrEqualTo(2048));
          expect(image.height, lessThanOrEqualTo(2048));
          expect(
            image.width * image.height,
            lessThanOrEqualTo(2 * 1024 * 1024),
          );
          final raw = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var red = 0;
          var blue = 0;
          for (var i = 0; i < raw.length; i += 4) {
            if (raw[i] > 200 && raw[i + 1] < 40 && raw[i + 2] < 40) red++;
            if (raw[i] < 40 && raw[i + 1] < 40 && raw[i + 2] > 200) blue++;
          }
          expect(red, greaterThan(500), reason: '概览必须含真实红图像素，不能只有框/坐标');
          expect(blue, greaterThan(500), reason: '概览必须含真实蓝图像素');
        } finally {
          frame.image.dispose();
          codec.dispose();
        }
        return (200, jsonEncode(_response(request).toJson()));
      },
    );
    final result = await _run(scene, transport);
    expect(transport.requests, hasLength(1), reason: '只做一次整页结构请求；原生文字不 OCR');
    final structure = result.structureResult as StructureResult;
    expect(structure.roles['native:title'], 'title');
    expect(structure.figureTextLinks, hasLength(2), reason: '低置信/无关段落不硬配');

    const adapter = RecognitionSemanticAdapter();
    final settled = adapter.settle(result);
    final semantic = adapter.assemble(
      settled,
      measure: TextMeasureAdapter(),
      tokens: SmartLayoutDesignTokens.v1,
    );
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: 'page-1',
      sceneRevision: SceneRevision(epoch: 0, revision: 1, fingerprint: before),
    );
    final blocks = const LayoutBlockAssembler().assemble(
      document: semantic.document,
      snapshot: snapshot,
      measure: TextMeasureAdapter(),
    );
    expect(blocks.ledgerConserved, isTrue);
    final redBody = blocks.blockById('native:red-text')!;
    expect(redBody.kind, LayoutBlockKind.paragraph, reason: '正文不能冒充图注');
    expect(redBody.text!.text, _redText);
    final units = FlowPlacer.placementUnits(blocks);
    expect(
      units
          .singleWhere((g) => g.any((b) => b.id == 'native:red-image'))
          .map((b) => b.id),
      contains('native:red-text'),
    );
    expect(
      units
          .singleWhere((g) => g.any((b) => b.id == 'native:blue-image'))
          .map((b) => b.id),
      contains('native:blue-text'),
    );
    expect(
      blocks.relationships.any((r) => r.fromBlockId == 'native:unrelated'),
      isFalse,
    );

    final outcome = await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
      baseScene: scene,
      snapshot: snapshot,
      semantic: semantic,
      recognition: settled,
      measure: TextMeasureAdapter(),
    );
    expect(outcome, isA<RealGenerationSucceeded>(), reason: '$outcome');
    final candidates = (outcome as RealGenerationSucceeded).candidates;
    addTearDown(() {
      for (final candidate in candidates) {
        candidate.dispose();
      }
    });
    expect(candidates, isNotEmpty);
    final best = candidates.first;
    expect(best.hardReport.passed, isTrue);
    final output = best.reduced.scene.activeElements;
    final redFigure = output.whereType<ImageElement>().singleWhere(
      (e) => e.fileId == 'red',
    );
    final blueFigure = output.whereType<ImageElement>().singleWhere(
      (e) => e.fileId == 'blue',
    );
    final redText = output.whereType<TextElement>().singleWhere(
      (e) => e.text == _redText,
    );
    final blueText = output.whereType<TextElement>().singleWhere(
      (e) => e.text == _blueText,
    );
    expect(redText.y, greaterThanOrEqualTo(redFigure.y + redFigure.height));
    expect(blueText.y, greaterThanOrEqualTo(blueFigure.y + blueFigure.height));
    expect(redText.y - redFigure.y - redFigure.height, lessThan(50));
    expect(blueText.y - blueFigure.y - blueFigure.height, lessThan(50));
    expect(SceneFingerprint.of(scene), before, reason: '生成预览不改原稿');
  });

  test('缺图和预算不足均不伪造视觉匹配，也不把文字扔掉', () async {
    final scene = await _scene(missingImages: true);
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request =
            RecognitionRequest.fromJson(jsonDecode(body))
                as RecognitionStructureRequest;
        expect(request.overviewPngBase64, isNull);
        expect(request.includeFigureTextLinks, isFalse);
        return (200, jsonEncode(_response(request, links: false).toJson()));
      },
    );
    final result = await _run(scene, transport);
    expect(
      (result.structureResult as StructureResult).figureTextLinks,
      isEmpty,
    );
    expect(result.partialNotes.join(), contains('未完成图像内容匹配'));
    final noBudget = FakeRecognitionTransport();
    final local = await _run(
      scene,
      noBudget,
      budget: const RecognitionBudget(modelCallBudget: 0),
    );
    expect(noBudget.requests, isEmpty);
    expect(
      (local.structureResult as StructureResult).units.where(
        (u) => u.isTextUnit,
      ),
      hasLength(4),
    );
    expect(local.partialNotes.join(), contains('预算不足'));
  });

  test('整页模型在途取消后，迟到的有效关联不得进入装配或改变原稿', () async {
    final scene = await _scene();
    final before = SceneFingerprint.of(scene);
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request =
            RecognitionRequest.fromJson(jsonDecode(body))
                as RecognitionStructureRequest;
        return (200, jsonEncode(_response(request).toJson()));
      },
    )..blockRequests();
    addTearDown(transport.release);
    final pipeline = _pipeline(transport);
    final run = pipeline.run(_capture(scene));
    final cancelled = expectLater(
      run,
      throwsA(isA<RecognitionCancelledException>()),
    );
    await transport.firstRequestSeen.future.timeout(
      const Duration(seconds: 10),
    );
    pipeline.cancel();
    transport.release();
    await cancelled;
    expect(
      pipeline.stateHistory,
      isNot(contains(RecognitionPipelineState.assembling)),
    );
    expect(transport.requests, hasLength(1));
    expect(SceneFingerprint.of(scene), before);
  });

  test('图文协议：错误ID、重复、角色冲突、越界置信、未协商和正文注入拒绝', () async {
    final scene = await _scene();
    RecognitionStructureRequest? captured;
    await _run(
      scene,
      FakeRecognitionTransport(
        responder: (body) async {
          captured =
              RecognitionRequest.fromJson(jsonDecode(body))
                  as RecognitionStructureRequest;
          return (200, jsonEncode(_response(captured!).toJson()));
        },
      ),
    );
    final request = captured!;
    final valid = _response(request).toJson();
    final link = {
      'textUnitId': 'native:red-text',
      'figureUnitId': 'native:red-image',
      'confidence': 0.95,
    };
    for (final links in [
      [
        {...link, 'figureUnitId': 'missing'},
      ],
      [
        {...link, 'figureUnitId': 'native:blue-text'},
      ],
      [link, link],
      [
        {...link, 'textUnitId': 'native:title'},
      ],
      [
        {...link, 'confidence': 1.1},
      ],
      [
        {...link, 'text': '不得改写正文'},
      ],
    ]) {
      expect(
        () => RecognitionResponse.fromJson({
          ...valid,
          'figureTextLinks': links,
        }, expectedFor: request),
        throwsA(isA<RecognitionProtocolException>()),
      );
    }
    final oldRequest = RecognitionRequest.fromJson(
      {...request.toJson()}..remove('includeFigureTextLinks'),
    );
    expect(
      () => RecognitionResponse.fromJson(valid, expectedFor: oldRequest),
      throwsA(isA<RecognitionProtocolException>()),
    );
    final oldResponse = {...valid}..remove('figureTextLinks');
    expect(
      (RecognitionResponse.fromJson(oldResponse, expectedFor: oldRequest)
              as RecognitionStructureResponse)
          .figureTextLinks,
      isEmpty,
    );
  });
}

final _redText =
    '${List.filled(5, '这里记录实验观察、测量步骤与结果说明，正文不能截断。').join()}对应的是红色圆形，颜色用于说明这组实验。';
const _blueText = '蓝色方形代表另一组实验，不能因为靠近红图而被配错。';

Future<Scene> _scene({bool missingImages = false}) async {
  const pageData = {
    'flowMuse': {'pageId': 'page-1'},
  };
  var scene = Scene().addElement(
    RectangleElement(
      id: const ElementId('page'),
      x: 0,
      y: 0,
      width: 1400,
      height: 1200,
      customData: const {
        'flowMuse': {'role': 'page', 'pageId': 'page-1'},
      },
      seed: 1,
      versionNonce: 1,
      updated: 1,
    ),
  );
  for (final spec in [
    ('title', '两组实验对比', 100.0, 80.0),
    ('red-text', _redText, 650.0, 330.0),
    ('blue-text', _blueText, 100.0, 330.0),
    ('unrelated', '下次课堂安排与这些图片无关。', 100.0, 550.0),
  ]) {
    scene = scene.addElement(
      TextElement(
        id: ElementId(spec.$1),
        text: spec.$2,
        x: spec.$3,
        y: spec.$4,
        width: 450,
        height: 120,
        fontSize: 20,
        fontFamily: 'Excalifont',
        customData: pageData,
        seed: 1,
        versionNonce: 1,
        updated: 1,
      ),
    );
  }
  for (final spec in [
    ('red', 100.0, 0xffff0000),
    ('blue', 650.0, 0xff0000ff),
  ]) {
    scene = scene.addElement(
      ImageElement(
        id: ElementId('${spec.$1}-image'),
        fileId: spec.$1,
        x: spec.$2,
        y: 200,
        width: 100,
        height: 100,
        customData: pageData,
        seed: 1,
        versionNonce: 1,
        updated: 1,
      ),
    );
    if (!missingImages) {
      scene = scene.addFile(
        spec.$1,
        ImageFile(mimeType: 'image/png', bytes: await _png(spec.$3)),
      );
    }
  }
  return scene;
}

Future<Uint8List> _png(int color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(ui.Color(color), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<RecognitionSessionResult> _run(
  Scene scene,
  FakeRecognitionTransport transport, {
  RecognitionBudget budget = const RecognitionBudget(),
}) => _pipeline(transport).run(_capture(scene), budget: budget);

RecognitionPipeline _pipeline(FakeRecognitionTransport transport) =>
    RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('http://test.invalid'),
          post: transport.post,
        ),
      ),
      structureRecoverer: const StructureRecovery(),
    );

RecognitionCapture _capture(Scene scene) => RecognitionCapture(
  scene: scene,
  operationId: 'op-page',
  generation: 0,
  pageId: 'page-1',
  contentFingerprint: 'contents',
  sceneRevision: const RecognitionSceneRevision(
    epoch: 0,
    revision: 1,
    fingerprint: 'revision',
  ),
);

RecognitionStructureResponse _response(
  RecognitionStructureRequest r, {
  bool links = true,
}) => RecognitionStructureResponse(
  operationId: r.operationId,
  requestId: r.requestId,
  pageId: r.pageId,
  sceneRevision: r.sceneRevision,
  contentFingerprint: r.contentFingerprint,
  generation: r.generation,
  textFingerprint: r.textFingerprint,
  readingOrder: const [
    'native:title',
    'native:red-image',
    'native:red-text',
    'native:blue-image',
    'native:blue-text',
    'native:unrelated',
  ],
  roles: [
    for (final u in r.units)
      if (u.isTextUnit)
        RecognitionRoleAssignment(
          unitId: u.unitId,
          role: u.unitId == 'native:title'
              ? RecognitionStructureRole.title
              : RecognitionStructureRole.body,
        ),
  ],
  listGroups: const [],
  captions: const [],
  warnings: const [],
  figureTextLinks: links
      ? const [
          RecognitionFigureTextLink(
            textUnitId: 'native:red-text',
            figureUnitId: 'native:red-image',
            confidence: 0.95,
          ),
          RecognitionFigureTextLink(
            textUnitId: 'native:blue-text',
            figureUnitId: 'native:blue-image',
            confidence: 0.92,
          ),
          RecognitionFigureTextLink(
            textUnitId: 'native:unrelated',
            figureUnitId: 'native:red-image',
            confidence: 0.3,
          ),
        ]
      : const [],
);
