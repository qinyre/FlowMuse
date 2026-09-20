// 诊断复现（2026-09-18 平板真机事故）：真实笔记场景 + 真实识别响应，
// 验证 read 成功结果在哪一层丢失。fixture = 平板 SQLite 导出的原样场景。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/smart_layout_design_tokens.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/design/text_measure_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/semantic_adapter.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_real_wiring.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/layout_page_snapshot.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/snapshot_extractor.dart';

import 'fake_recognition_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture =
      jsonDecode(
            File(
              'test/features/whiteboard/smart_layout/recognition/fixtures/'
              'tablet_note_20260918.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final elements = (fixture['elements'] as List).cast<Map<String, Object?>>();

  Scene sceneOf() {
    var scene = Scene();
    for (var i = 0; i < elements.length; i++) {
      final raw = elements[i];
      final element = ExcalidrawJsonCodec.parseElement(
        raw,
        raw['type'] as String,
        i,
        [],
      );
      if (element != null) {
        scene = scene.addElement(element);
      }
    }
    return scene;
  }

  RecognitionCapture captureOf(Scene scene) => RecognitionCapture(
    scene: scene,
    sceneRevision: const RecognitionSceneRevision(
      epoch: 0,
      revision: 0,
      fingerprint: 'c13a083ffcbaf3a8',
    ),
    contentFingerprint: 'c13a083ffcbaf3a8',
    operationId: 'rec-op-1',
    generation: 1,
    pageId: 'page-1',
  );

  test('平板场景 + 真实响应：read 成功结果应进 outcomes 并被消费', () async {
    // 与真实服务器行为一致：把请求中的 regionId 全部识别为
    // 「你好\n我是你爸爸」conf 0.99（真实 RESP 原样语义）。
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        final regions = (request['regions'] as List)
            .cast<Map<String, Object?>>();
        return (
          200,
          jsonEncode({
            'schemaVersion': request['schemaVersion'],
            'stage': request['stage'],
            'operationId': request['operationId'],
            'requestId': request['requestId'],
            'pageId': request['pageId'],
            'sceneRevision': request['sceneRevision'],
            'contentFingerprint': request['contentFingerprint'],
            'generation': request['generation'],
            'regions': [
              for (final r in regions)
                if ((r['regionId'] as String).contains('0e2835e7'))
                  {
                    'regionId': r['regionId'],
                    'status': 'recognized',
                    'text': '你好\n我是你爸爸',
                    'confidence': 0.99,
                    'diagnostics': ['文字清晰可辨，识别结果准确'],
                  },
            ],
            'missingRegionIds': const <String>[],
          }),
        );
      },
    );
    final pipeline = RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('https://server.test'),
          post: transport.post,
        ),
      ),
      structureRecoverer: const StructureRecovery(),
    );
    final scene = sceneOf();
    // ignore: avoid_print
    print('scene elements: ${scene.activeElements.length}');
    final result = await pipeline.run(captureOf(scene));

    // ignore: avoid_print
    print('regionRecords: ${result.regionRecords.length}');
    for (final record in result.regionRecords) {
      // ignore: avoid_print
      print(
        '  ${record.regionId} sources=${record.targetSourceIds.length} '
        'lineHeight=${record.localLineHeight}',
      );
    }
    // ignore: avoid_print
    print('regionOutcomes: ${result.regionOutcomes.length}');
    for (final entry in result.regionOutcomes.entries) {
      // ignore: avoid_print
      print(
        '  ${entry.key} status=${entry.value.status} '
        'conf=${entry.value.confidence} text=${entry.value.text}',
      );
    }
    // ignore: avoid_print
    print(
      'ledger preserved=${result.ledger.preservedCount} '
      'consumed=${result.ledger.consumedCount} '
      'pending=${result.ledger.pendingCount}',
    );
    // ignore: avoid_print
    print('partial=${result.partial} notes=${result.partialNotes}');

    final adapter = const RecognitionSemanticAdapter();
    final settled = adapter.settle(result);
    final assembly = adapter.assemble(
      settled,
      measure: TextMeasureAdapter(),
      tokens: SmartLayoutDesignTokens.v1,
    );
    // ignore: avoid_print
    print(
      'settled: outcomes=${settled.regionOutcomes.length} '
      'preserved=${settled.ledger.preservedCount} '
      'consumed=${settled.ledger.consumedCount}',
    );
    final document = assembly.document;
    // ignore: avoid_print
    print(
      'document blocks=${document.blocks.length} '
      'consumed=${document.consumedSourceIds.length} '
      'preserved=${document.preservedSourceIds.length}',
    );
    for (final block in document.blocks) {
      // ignore: avoid_print
      print(
        '  block id=${block.id} sources=${block.sourceIds.length} '
        'role=${block.role} text=${block.text?.substring(0, block.text!.length.clamp(0, 40))}',
      );
    }
    // 候选链入口的三方一致断言（§6.4-1）——真机在此抛
    // semantic-contract-broken。
    try {
      RecognitionLedgerAssertions.assertThreeWayConsistency(
        capturedNonBackgroundSourceIds: {
          for (final element in scene.activeElements)
            if (!element.isCanvasPage && !element.isPdfBackground)
              element.id.value,
        },
        recognition: settled.ledger,
        assembly: assembly,
      );
      // ignore: avoid_print
      print('三方一致断言：通过');
    } on StateError catch (error) {
      // ignore: avoid_print
      print('三方一致断言：FAIL ${error.message}');
      fail('真实平板 fixture 三方账本必须一致');
    }
    expect(result.regionOutcomes, isNotEmpty, reason: '读成功的区域必须产生 outcome');
    expect(settled.ledger.consumedCount, greaterThan(0), reason: '识别正文应被消费');

    // 端到端：真机在此链路抛 generation/semantic-contract-broken。
    // 用 SnapshotExtractor 构造与 wiring 同源的完整快照后走候选链入口。
    final snapshot = const SnapshotExtractor().extract(
      scene: scene,
      pageId: 'page-1',
      sceneRevision: SceneRevision(
        epoch: 0,
        revision: 0,
        fingerprint: SceneFingerprint.of(scene),
      ),
    );
    // ignore: avoid_print
    print(
      'snapshot: objects=${snapshot.objects.length} '
      'strokes=${snapshot.inkStrokes.length} '
      'background=${snapshot.objects.where((o) => o.mobility == SnapshotMobility.background).length}',
    );
    final outcome = await SmartLayoutRealCandidateChain.runFromSemanticAssembly(
      baseScene: scene,
      snapshot: snapshot,
      semantic: assembly,
      recognition: settled,
      measure: TextMeasureAdapter(),
      tokens: SmartLayoutDesignTokens.v1,
    );
    // ignore: avoid_print
    print('candidate chain outcome: ${outcome.runtimeType}');
    if (outcome is RealGenerationFailed) {
      // ignore: avoid_print
      print('  reason=${outcome.reason} retryable=${outcome.retryable}');
      // ignore: avoid_print
      print('  detail=${outcome.detail}');
    }
    expect(outcome, isA<RealGenerationSucceeded>());
    final candidates = (outcome as RealGenerationSucceeded).candidates;
    addTearDown(() {
      for (final candidate in candidates) {
        candidate.dispose();
      }
    });
    expect(candidates, isNotEmpty, reason: '不能只有中间层通过而默认结果为空');
    final best = candidates.first;
    expect(best.hardReport.passed, isTrue);
    expect(
      best.reduced.scene.activeElements.whereType<TextElement>().map(
        (e) => e.text,
      ),
      contains('你好\n我是你爸爸'),
    );
    expect(best.patch.sourceCoverage.preservedCount, greaterThanOrEqualTo(2));
  });
}
