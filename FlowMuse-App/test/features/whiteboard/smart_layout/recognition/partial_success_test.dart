import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/semantics/semantic_document.dart';

import 'fake_recognition_transport.dart';
import 'structure_test_helpers.dart';

/// §11 R6 部分成功语义：区域保留的会话 partial=true + 原因留档；
/// 适配层在混合（消费+保留）会话上仍产出守恒文档，保留区成障碍块。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adapter = RecognitionSemanticAdapter();
  const tokens = SmartLayoutDesignTokens.v1;

  FreedrawElement stroke(String id, double x, double y) {
    return FreedrawElement(
      id: ElementId(id),
      x: x,
      y: y,
      width: 60,
      height: 8,
      points: const [Point(0, 4), Point(30, 4), Point(60, 4)],
      strokeColor: '#1e1e1e',
      strokeWidth: 2,
      isComplete: true,
      seed: 7,
      versionNonce: 11,
      updated: 1000,
    );
  }

  RecognitionCapture captureOf(Scene scene) => RecognitionCapture(
    scene: scene,
    sceneRevision: const RecognitionSceneRevision(
      epoch: 0,
      revision: 5,
      fingerprint: '0123456789abcdef',
    ),
    contentFingerprint: 'fedcba9876543210',
    operationId: 'op-partial',
    generation: 0,
    pageId: 'page-1',
  );

  test('管线：漏答区域保留 → partial=true + 原因留档 + 状态 done', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return buildBatchResponseBody(request, missingRegionIds: {'r:s1'});
      },
    );
    final pipeline = RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('https://server.test'),
          post: transport.post,
        ),
      ),
    );
    final scene = Scene()
        .addElement(stroke('s1', 10, 20))
        .addElement(stroke('s2', 10, 120));
    final result = await pipeline.run(captureOf(scene));

    expect(
      pipeline.state,
      RecognitionPipelineState.done,
      reason: '部分完成也是 done 终态',
    );
    expect(result.partial, isTrue);
    expect(result.partialNotes, isNotEmpty);
    expect(result.partialNotes.join('\n'), contains('r:s1'));
    expect(result.ledger.preservedCount, 1);
    expect(
      result.ledger.projection.preservedReasons['s1'],
      SourcePreserveReason.missingResponse,
    );
  });

  test('适配：混合会话（1 消费 + 1 漏答保留）产出守恒文档，保留区成障碍', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:ok', top: 0, left: 0, text: '识别成功'),
      RegionSpec(regionId: 'r:miss', top: 60, left: 0),
    ]);
    final settled = adapter.settle(result);
    final assembly = adapter.assemble(
      settled,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    final document = assembly.document;
    expect(document.ledgerConserved, isTrue);
    expect(document.consumedSourceIds, ['s-ok']);
    expect(document.preservedSourceIds, ['s-miss']);
    final obstacle = document.blocks.firstWhere(
      (block) => block.id == 'native:s-miss',
      orElse: () => throw StateError('漏答区域必须生成带 bounds 的保留块'),
    );
    expect(obstacle.role, SemanticRole.unknown);
    expect(
      obstacle.extras['bounds'],
      isA<Map<String, Object?>>(),
      reason: '障碍物身份（原始 bounds）',
    );
    expect(assembly.ledger.isFinalized, isTrue);
  });

  test('适配：全部保留（空文档流）不抛错', () async {
    final result = await sessionOf(const [
      RegionSpec(regionId: 'r:m1', top: 0, left: 0),
      RegionSpec(regionId: 'r:m2', top: 60, left: 0),
    ]);
    final assembly = adapter.assemble(
      result,
      measure: TextMeasureAdapter(),
      tokens: tokens,
    );
    expect(assembly.document.consumedSourceIds, isEmpty);
    expect(assembly.document.preservedSourceIds, containsAll(['s-m1', 's-m2']));
    expect(
      assembly.document.readingOrder.orderedBlockIds,
      isNotEmpty,
      reason: '保留块仍进阅读序（障碍物可追溯）',
    );
  });
}
