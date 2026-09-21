import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/resolved_page_scope.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/rendering/draft_scene_renderer.dart';

import 'fake_recognition_transport.dart';

// 原件不入库。显式本地目录时诊断真实分区，不联网，不冒充真实模型验收。
// flutter test --dart-define=TEAMMATE_NOTE_DIR=<目录> <本文件>
// 加 --dart-define=EXPORT_LAYOUT_EVIDENCE=true 导出区域图及几何（build/）。
const _noteDir = String.fromEnvironment('TEAMMATE_NOTE_DIR');
const _export = bool.fromEnvironment('EXPORT_LAYOUT_EVIDENCE');
const _cjkPath = String.fromEnvironment('LAYOUT_EVIDENCE_CJK_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(() async {
    final font = FontLoader('Excalifont');
    // 导图可提供本机中文字体；不改变生产字体配置，不冒充设备渲染证据。
    if (_export && _cjkPath.isNotEmpty) {
      font.addFont(File(_cjkPath).readAsBytes().then(ByteData.sublistView));
    } else {
      font.addFont(
        rootBundle.load('assets/fonts/markdraw/Excalifont-Regular.ttf'),
      );
    }
    await font.load();
  });
  test('编号和短笔画按完整行归属，下伸笔画不串行；平移缩放不改变成员', () {
    for (final scale in [.5, 1.0, 3.0]) {
      FreedrawElement ink(String id, double x, double y, double w, double h) =>
          FreedrawElement(
            id: ElementId(id),
            x: 137 + x * scale,
            y: 219 + y * scale,
            width: w * scale,
            height: h * scale,
            points: [const Point(0, 0), Point(w * scale, h * scale)],
            isComplete: true,
          );
      final scene = Scene()
          .addElement(ink('first', 100, 10, 60, 100))
          .addElement(ink('dash', 20, 55, 40, 2))
          .addElement(ink('dot', 72, 60, 4, 3))
          .addElement(ink('second', 100, 95, 60, 100))
          .addElement(ink('tail', 130, 166, 30, 3));
      final partitions = const RegionPartitioner().partition(scene);
      expect(partitions.map((p) => p.record.targetSourceIds.toSet()), [
        {'first', 'dash', 'dot'},
        {'second', 'tail'},
      ]);
    }
  });
  test('文字响应不能删除闭合轮廓；纠错合并也不能绕过原稿守卫', () async {
    final scene = Scene()
        .addElement(
          FreedrawElement(
            id: const ElementId('drawing'),
            x: 400,
            y: 200,
            width: 140,
            height: 100,
            points: const [
              Point(0, 100),
              Point(70, 0),
              Point(140, 100),
              Point(0, 100),
            ],
            isComplete: true,
          ),
        )
        .addElement(
          FreedrawElement(
            id: const ElementId('label'),
            x: 20,
            y: 40,
            width: 100,
            height: 20,
            points: const [Point(0, 0), Point(40, 20), Point(100, 0)],
            isComplete: true,
          ),
        );
    await _checkDrawingAdmission(scene, {'drawing'});
    await _checkDrawingAdmission(scene, {'drawing', 'label'}, merged: true);
  });
  if (_noteDir.isEmpty) {
    test('队员原始笔记离线回归需显式本地目录', () {}, skip: '未提供本地原件');
    return;
  }

  for (final (name, count) in [
    ('未命名空白', 70),
    ('未命名空白(1)', 183),
    ('未命名空白(2)', 218),
  ]) {
    test('原始笔记 $name 分区源唯一且完整', () async {
      final doc = ExcalidrawJsonCodec.parse(
        await File('$_noteDir/$name.excalidraw').readAsString(),
      ).value;
      var scene = Scene();
      for (final element in doc.allElements) {
        scene = scene.addElement(element);
      }
      for (final entry in doc.files.entries) {
        scene = scene.addFile(entry.key, entry.value);
      }
      final partitions = const RegionPartitioner().partition(scene);
      final sources = partitions
          .expand((p) => p.record.targetSourceIds)
          .toList();
      expect(sources, hasLength(count));
      expect(sources.toSet(), hasLength(count));
      if (count == 218) {
        expect(
          partitions.map((p) => p.strokes.length),
          [20, 38, 20, 12, 34, 17, 22, 19, 36],
          reason: '原稿9个完整文字行，章节编号和列表编号不能独立漂移',
        );
      }
      if (count == 183) {
        expect(
          partitions.map((p) => p.strokes.length),
          [80, 40, 63],
          reason: '两行前置说明和一行共享图注，不能拆掉字的下半部',
        );
        final scope = ResolvedPageScope.resolve(scene, 'page-1');
        expect(scope.excludedReasons, isEmpty);
        expect(
          scope.captureScene(scene).activeElements.whereType<ImageElement>(),
          hasLength(2),
        );
      }
      if (count == 70) {
        final drawingIds = {
          for (final s in scene.activeElements.whereType<FreedrawElement>())
            if (s.x > 700 && s.y > 300) s.id.value,
        };
        expect(drawingIds, hasLength(5));
        expect(
          {
            for (final p in partitions)
              if (p.isDrawingLike) ...p.record.targetSourceIds,
          },
          drawingIds,
          reason: '原稿五笔图形都应进入保守替换守卫，文字不得误命中',
        );
        for (final p in partitions) {
          final ids = p.record.targetSourceIds.toSet();
          if (ids.intersection(drawingIds).isNotEmpty) {
            expect(
              ids.difference(drawingIds),
              isEmpty,
              reason: '三幅图形不得和标题或标签共用一个整块替换许可',
            );
          }
        }
        await _checkDrawingAdmission(scene, drawingIds);
      }
      await _checkOriginalCandidates(name, count, scene, partitions);
      if (!_export) return;

      final dir = await Directory(
        'build/teammate-notes/$name',
      ).create(recursive: true);
      final builder = RegionAssetBuilder(capturedScene: scene);
      addTearDown(builder.dispose);
      final records = <Object?>[];
      for (var i = 0; i < partitions.length; i++) {
        final partition = partitions[i];
        final record = partition.record;
        final outcome = await builder.build(record, const RecognitionBudget());
        if (outcome is RegionAssetBuilt) {
          await File(
            '${dir.path}/region-$i.png',
          ).writeAsBytes(outcome.asset.pngBytes);
        }
        records.add({
          'index': i,
          'regionId': record.regionId,
          'bounds': record.bounds.toJson(),
          'lineHeight': record.localLineHeight,
          'rendered': outcome is RegionAssetBuilt,
          'drawingLike': partition.isDrawingLike,
          'strokes': [
            for (final s in partition.strokes)
              {
                'id': s.id.value,
                'x': s.x,
                'y': s.y,
                'w': s.width,
                'h': s.height,
              },
          ],
        });
      }
      await File(
        '${dir.path}/regions.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    });
  }
}

Future<void> _checkOriginalCandidates(
  String name,
  int count,
  Scene scene,
  List<RegionPartition> partitions,
) async {
  // 人工读原稿提供的离线响应；不调用线上模型、不把转写正确写成已验证。
  final lines = switch (count) {
    70 => ['手绘图形：', '三角形', '', '圆', '', '正方形', ''],
    183 => ['小懒羊羊喜欢侧身睡觉', '以下为实际照片', '小懒羊羊睡觉姿势'],
    _ => [
      '光合作用',
      '一、基本概念',
      '1.植物',
      '2.阳光',
      '二、影响因素',
      '1.光照',
      '2.温度',
      '三、意义',
      '能量来源',
    ],
  };
  expect(partitions, hasLength(lines.length));
  final texts = {
    for (var i = 0; i < lines.length; i++)
      partitions[i].record.regionId: lines[i],
  };
  String unit(int i) => lines[i].isEmpty
      ? 'native:${(partitions[i].record.targetSourceIds.toList()..sort()).first}'
      : 'ink:${partitions[i].record.regionId}';
  final figures = scene.activeElements.whereType<ImageElement>().toList()
    ..sort((a, b) => a.x.compareTo(b.x));
  final figureIds = figures.map((e) => 'native:${e.id.value}').toList();
  final transport = FakeRecognitionTransport(
    responder: (body) async {
      final json = jsonDecode(body) as Map<String, Object?>;
      if (json['stage'] != 'structure') {
        return buildBatchResponseBody(
          json,
          confidence: .99,
          textOf: (id) => texts[id]!,
          statusOf: (id) => texts[id]!.isEmpty ? 'nonText' : 'recognized',
        );
      }
      final request =
          RecognitionRequest.fromJson(json) as RecognitionStructureRequest;
      final order = count == 183
          ? [unit(0), unit(1), ...figureIds, unit(2)]
          : [for (var i = 0; i < lines.length; i++) unit(i)];
      return (
        200,
        jsonEncode(
          RecognitionStructureResponse(
            operationId: request.operationId,
            requestId: request.requestId,
            pageId: request.pageId,
            sceneRevision: request.sceneRevision,
            contentFingerprint: request.contentFingerprint,
            generation: request.generation,
            textFingerprint: request.textFingerprint,
            readingOrder: order,
            roles: [
              for (var i = 0; i < lines.length; i++)
                if (lines[i].isNotEmpty)
                  RecognitionRoleAssignment(
                    unitId: unit(i),
                    role: count == 183
                        // 现有协议用 mediaGroups 表达共享说明，caption 只认单图。
                        ? RecognitionStructureRole.body
                        : i == 0 || (count == 218 && [1, 4, 7].contains(i))
                        ? RecognitionStructureRole.title
                        : count == 70
                        ? RecognitionStructureRole.caption
                        : [2, 3, 5, 6].contains(i)
                        ? RecognitionStructureRole.listItem
                        : RecognitionStructureRole.body,
                  ),
            ],
            listGroups: [
              if (count == 218)
                for (final i in [2, 5])
                  RecognitionListGroup(
                    groupId: 'list-$i',
                    members: [unit(i), unit(i + 1)],
                    level: 1,
                    listType: RecognitionListType.ordered,
                    startNumber: 1,
                  ),
            ],
            captions: [
              if (count == 70)
                for (final i in [1, 3, 5])
                  RecognitionCaption(
                    captionUnitId: unit(i),
                    targetUnitId: unit(i + 1),
                  ),
            ],
            compositionHints: RecognitionCompositionHints(
              pageIntent: 'reading',
              sections: [
                if (count == 218)
                  for (final i in [1, 4, 7])
                    RecognitionSectionHint(
                      sectionId: 'section-$i',
                      headingUnitId: unit(i),
                      memberUnitIds: [unit(i + 1), if (i < 7) unit(i + 2)],
                    ),
              ],
              mediaGroups: [
                if (count == 183)
                  RecognitionMediaGroup(
                    groupId: 'shared-sheep',
                    figureUnitIds: figureIds,
                    textUnitIds: [unit(0), unit(1), unit(2)],
                    confidence: .99,
                  ),
              ],
            ),
            warnings: const [],
          ).toJson(),
        ),
      );
    },
  );
  final controller = MarkdrawController()..loadScene(scene);
  addTearDown(controller.dispose);
  final scope = SmartLayoutRealSessionScope.build(
    controller: controller,
    serverUri: Uri.parse('https://server.test'),
    pageId: 'page-1',
    post: transport.post,
  );
  addTearDown(scope.dispose);
  final before = SceneFingerprint.of(controller.currentScene);
  final ticket = scope.session.beginOperation();
  final outcome = await scope.dependencies.analysisRunner!(ticket);
  expect(outcome, isA<SmartLayoutRecognitionSucceeded>(), reason: '$outcome');
  final success = outcome as SmartLayoutRecognitionSucceeded;
  final structure = success.recognition.structureResult as StructureResult;
  expect(structure.modelRejected, isFalse, reason: '${structure.warnings}');
  expect(structure.usedModel, isTrue);
  final candidates = await scope.dependencies.candidateChainFromDocument!(
    success,
    ticket,
  );
  addTearDown(() {
    for (final c in candidates) {
      c.dispose();
    }
  });
  expect(candidates, isNotEmpty);
  for (final c in candidates) {
    final output = c.reduced.scene.activeElements;
    expect(
      output.whereType<ImageElement>().map((e) => e.id.value).toSet(),
      figures.map((e) => e.id.value).toSet(),
    );
    if (count == 70) {
      for (final s in scene.activeElements.whereType<FreedrawElement>().where(
        (e) => !partitions.first.record.targetSourceIds.contains(e.id.value),
      )) {
        expect(
          output.singleWhere((e) => e.id == s.id),
          same(s),
          reason: '图形和相关标签必须原样保留，不能只保图丢标签关联',
        );
      }
    } else {
      for (final line in lines) {
        expect(
          output.whereType<TextElement>().where((e) => e.text == line),
          hasLength(1),
        );
      }
    }
  }
  if (count == 183) {
    final images = candidates.first.reduced.scene.activeElements
        .whereType<ImageElement>()
        .toList();
    expect(images[0].y, closeTo(images[1].y, .01), reason: '共享双图的最高分方案须并排');
    expect(images[0].height, closeTo(images[1].height, .01));
  }
  expect(SceneFingerprint.of(controller.currentScene), before);
  final review = scope.dependencies.reviewContextBuilder!()!;
  debugPrint(
    'ORIGINAL $name candidates=${candidates.length} '
    'top=${candidates.first.diversityKey} recommend=${review.recommendation?.recommended} '
    'reason=${review.recommendation?.reason}',
  );
  if (_export) {
    final dir = await Directory(
      'build/teammate-notes/$name',
    ).create(recursive: true);
    final renderer = DraftSceneRenderer();
    try {
      for (final (label, scene) in [
        ('before', controller.currentScene),
        for (var i = 0; i < candidates.length; i++)
          ('after-$i', candidates[i].reduced.scene),
      ]) {
        final snapshot = await renderer.render(
          scene: scene,
          viewport: ViewportState(
            offset: ui.Offset(review.pageBounds.left, review.pageBounds.top),
            zoom: .6,
          ),
          pixelSize: ui.Size(
            review.pageBounds.size.width * .6,
            review.pageBounds.size.height * .6,
          ),
        );
        try {
          // 与白板预览一样铺浅色背景，透明 PNG 上的黑字不能当“缺字”。
          final recorder = ui.PictureRecorder();
          ui.Canvas(recorder)
            ..drawColor(const ui.Color(0xfffffcf4), ui.BlendMode.src)
            ..drawImage(snapshot.image, ui.Offset.zero, ui.Paint());
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            snapshot.image.width,
            snapshot.image.height,
          );
          picture.dispose();
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '${dir.path}/$label.png',
            ).writeAsBytes(png!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        } finally {
          snapshot.dispose();
        }
      }
    } finally {
      renderer.dispose();
    }
  }
}

Future<void> _checkDrawingAdmission(
  Scene scene,
  Set<String> preserved, {
  bool merged = false,
}) async {
  final transport = FakeRecognitionTransport(
    responder: (body) async {
      final request = jsonDecode(body) as Map<String, Object?>;
      return request['stage'] == 'structure'
          ? buildStructureResponseBody(request)
          : buildBatchResponseBody(
              request,
              confidence: .99,
              textOf: (_) => '标签',
            );
    },
  );
  final result =
      await RecognitionPipeline(
        repository: RecognitionRepository(
          gateway: SmartLayoutHttpGateway(
            serverUri: Uri.parse('https://server.test'),
            post: transport.post,
          ),
        ),
        structureRecoverer: const StructureRecovery(),
      ).run(
        RecognitionCapture(
          scene: scene,
          sceneRevision: const RecognitionSceneRevision(
            epoch: 0,
            revision: 0,
            fingerprint: 'test',
          ),
          contentFingerprint: 'test',
          operationId: 'drawing-safety',
          generation: 1,
          pageId: 'page-1',
        ),
        correctedPartitions: merged
            ? [
                RegionPartition(
                  strokes: scene.activeElements
                      .whereType<FreedrawElement>()
                      .toList(),
                  record: RegionRecord(
                    regionId: 'r:drawing',
                    targetSourceIds: const ['drawing', 'label'],
                    bounds: const RecognitionBounds(
                      left: 20,
                      top: 40,
                      width: 520,
                      height: 260,
                    ),
                    localLineHeight: 100,
                  ),
                ),
              ]
            : null,
      );
  final settled = const RecognitionSemanticAdapter().settle(result);
  expect(
    settled.ledger.projection.preservedReasons.keys.toSet(),
    preserved,
    reason: '模拟模型把所有区域都报 recognized；原图形仍须保留',
  );
  expect(
    settled.ledger.preservedCount + settled.ledger.consumedCount,
    scene.activeElements.whereType<FreedrawElement>().length,
  );
  final facts = ReplacementGuard.factsOf(settled);
  for (final id in preserved) {
    expect(settled.ledger.entryOf(id).status, SourceLedgerStatus.preserved);
  }
  expect(
    ReplacementGuard.check(
      recognition: settled.ledger,
      unitFactsByUnitId: facts,
      deletedSourceIds: preserved,
      modifiedSourceIds: const [],
    ),
    isNotEmpty,
  );
}
