import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';

import 'fake_recognition_transport.dart';

// 原件不入库。显式本地目录时诊断真实分区，不联网，不冒充真实模型验收。
// flutter test --dart-define=TEAMMATE_NOTE_DIR=<目录> <本文件>
// 加 --dart-define=EXPORT_LAYOUT_EVIDENCE=true 导出区域图及几何（build/）。
const _noteDir = String.fromEnvironment('TEAMMATE_NOTE_DIR');
const _export = bool.fromEnvironment('EXPORT_LAYOUT_EVIDENCE');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
