import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_budget.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/source_ledger.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/structure_recovery.dart';

import 'fake_recognition_transport.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/region_assets.dart';

/// 状态机全迁移（spec §6.1）：含 regrouping 先于 verifying、部分批次、
/// 预算耗尽、重试仅一次、结构 seam。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    operationId: 'op-test',
    generation: 0,
    pageId: 'page-1',
  );

  RecognitionPipeline pipelineOf(FakeRecognitionTransport transport) {
    return RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('https://server.test'),
          post: transport.post,
        ),
      ),
    );
  }

  Scene twoRegionScene() => Scene()
      .addElement(stroke('s1', 10, 20))
      .addElement(stroke('s2', 10, 120));

  test('总预算在渲染前耗尽：不出图、不发请求、全部源保留', () async {
    final transport = FakeRecognitionTransport();
    final result = await pipelineOf(transport).run(
      captureOf(twoRegionScene()),
      budget: const RecognitionBudget(totalTimeout: Duration.zero),
    );
    expect(transport.requests, isEmpty);
    expect(result.assetIndex.assetCount, 0);
    expect(result.failure?.code, 'operationTimeout');
    expect(result.ledger.preservedCount, 2);
    expect(
      result.ledger.entryOf('s1').reason,
      SourcePreserveReason.budgetExceeded,
    );
  });

  test('疑难初读的复核请求失败：不能沿用 recognized 状态获得转换许可', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final req = jsonDecode(body) as Map<String, Object?>;
        if (req['stage'] == 'verify') return (502, '{}');
        return buildBatchResponseBody(req, confidence: 0.2);
      },
    );
    final result = await pipelineOf(transport).run(captureOf(twoRegionScene()));
    expect(result.ledger.preservedCount, 2);
    expect(result.ledger.entryOf('s1').reason, SourcePreserveReason.uncertain);
  });

  for (final missing in [false, true]) {
    test('自动重分组重新出图与替换成员；复核漏答=$missing', () async {
      final a = stroke('a', 10, 20);
      final b = stroke('b', 73, 20);
      final scene = Scene().addElement(a).addElement(b);
      final transport = FakeRecognitionTransport(
        responder: (body) async {
          final req = jsonDecode(body) as Map<String, Object?>;
          return buildBatchResponseBody(
            req,
            confidence: req['stage'] == 'read' ? 0.2 : 0.95,
            missingRegionIds: missing && req['stage'] == 'verify'
                ? {'r:a'}
                : null,
          );
        },
      );
      final result = await pipelineOf(transport).run(
        captureOf(scene),
        correctedPartitions: [
          for (final s in [a, b])
            RegionPartition(
              strokes: [s],
              record: RegionRecord(
                regionId: 'r:${s.id.value}',
                targetSourceIds: [s.id.value],
                localLineHeight: 8,
                bounds: RecognitionBounds(
                  left: s.x,
                  top: s.y,
                  width: s.width,
                  height: s.height,
                ),
              ),
            ),
        ],
      );
      final reads = transport.decodedBodies('read').single['regions'] as List;
      final verified =
          transport.decodedBodies('verify').single['regions'] as List;
      expect(reads, hasLength(2));
      expect(verified, hasLength(1));
      expect(
        verified.single['imagePngBase64'],
        isNot(reads.first['imagePngBase64']),
      );
      expect(result.regionRecords.single.targetSourceIds, ['a', 'b']);
      expect(result.regionOutcomes.keys, ['r:a']);
      expect(
        result.assetIndex.assetIdsOf('a'),
        result.assetIndex.assetIdsOf('b'),
      );
      if (missing) {
        expect(result.ledger.preservedCount, 2);
        expect(
          result.regionOutcomes['r:a']!.status,
          isNot(RecognitionRegionStatus.recognized),
        );
      } else {
        expect(result.regionOutcomes['r:a']!.verified, isTrue);
      }
    });
  }

  test('全流程：capturing→…→done，识别入账、零保留、非部分完成', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return buildBatchResponseBody(request, confidence: 0.9);
      },
    );
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(captureOf(twoRegionScene()));

    expect(
      pipeline.stateHistory,
      containsAllInOrder([
        RecognitionPipelineState.capturing,
        RecognitionPipelineState.proposing,
        RecognitionPipelineState.rendering,
        RecognitionPipelineState.reading,
        RecognitionPipelineState.assembling,
        RecognitionPipelineState.done,
      ]),
    );
    expect(pipeline.state, RecognitionPipelineState.done);
    expect(
      pipeline.stateHistory,
      isNot(contains(RecognitionPipelineState.verifying)),
      reason: '高置信不应触发复核',
    );
    expect(result.regionOutcomes.length, 2);
    for (final outcome in result.regionOutcomes.values) {
      expect(outcome.status, RecognitionRegionStatus.recognized);
      expect(outcome.text, isNotEmpty);
      expect(outcome.targetSourceIds, hasLength(1));
    }
    expect(result.ledger.preservedCount, 0);
    expect(result.partial, isFalse);
    expect(
      result.regionRecords.map((r) => r.regionId),
      containsAll(['r:s1', 'r:s2']),
    );
  });

  test('regrouping 先于 verifying；复核覆盖初读（verified=true）', () async {
    var call = 0;
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        call++;
        // 初读低置信 → 触发复核；复核给高置信。
        return buildBatchResponseBody(
          request,
          confidence: call == 1 ? 0.3 : 0.92,
        );
      },
    );
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(captureOf(twoRegionScene()));

    final history = pipeline.stateHistory;
    expect(history, contains(RecognitionPipelineState.regrouping));
    expect(history, contains(RecognitionPipelineState.verifying));
    expect(
      history.indexOf(RecognitionPipelineState.regrouping),
      lessThan(history.indexOf(RecognitionPipelineState.verifying)),
      reason: '计划书 §3.4：先重分组得到最终复核区域，再发复核请求',
    );
    // 不相邻区域不合并，但仍可共享一个网络批次。
    expect(call, 2);
    final verifyBodies = transport.decodedBodies('verify').toList();
    expect(verifyBodies, hasLength(1), reason: '分区身份与网络分批互不混淆');
    final verifyRegions = [
      for (final body in verifyBodies)
        ...(body['regions'] as List).cast<Map<String, Object?>>(),
    ];
    for (final region in verifyRegions) {
      expect(region['reason'], 'lowConfidence');
      expect(region['originalText'], isNotNull);
      expect(region['originalConfidence'], 0.3);
    }
    for (final outcome in result.regionOutcomes.values) {
      expect(outcome.verified, isTrue);
      expect(outcome.confidence, 0.92);
    }
  });

  test('nonText 复核后才结算：确认正文可准入，仍为非文字只保留一次', () async {
    for (final reviewedStatus in ['recognized', 'nonText']) {
      final transport = FakeRecognitionTransport(
        responder: (body) async {
          final request = jsonDecode(body) as Map<String, Object?>;
          return buildBatchResponseBody(
            request,
            confidence: request['stage'] == 'read' ? 0.3 : 0.9,
            statusOf: (_) =>
                request['stage'] == 'read' ? 'nonText' : reviewedStatus,
          );
        },
      );
      final result = await pipelineOf(
        transport,
      ).run(captureOf(twoRegionScene()));
      expect(transport.decodedBodies('verify'), isNotEmpty);
      expect(result.regionOutcomes.values.every((r) => r.verified), isTrue);
      expect(
        result.ledger.preservedCount,
        reviewedStatus == 'recognized' ? 0 : 2,
      );
    }
  });

  test('部分批次：missingRegionIds 区域按 preserve(missingResponse)', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return buildBatchResponseBody(request, missingRegionIds: {'r:s1'});
      },
    );
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(captureOf(twoRegionScene()));

    expect(result.partial, isTrue);
    expect(result.ledger.preservedCount, 1);
    expect(result.failure, isNull, reason: '区域漏答不是网络故障');
    expect(
      result.ledger.projection.preservedReasons['s1'],
      SourcePreserveReason.missingResponse,
    );
    expect(
      result.regionOutcomes['r:s2']!.status,
      RecognitionRegionStatus.recognized,
    );
  });

  test('预算耗尽：不发请求，区域保留 budgetExceeded', () async {
    final transport = FakeRecognitionTransport();
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(
      captureOf(twoRegionScene()),
      budget: const RecognitionBudget(modelCallBudget: 0),
    );

    expect(transport.requests, isEmpty);
    expect(result.ledger.preservedCount, 2);
    expect(result.ledger.projection.preservedReasons.values.toSet(), {
      SourcePreserveReason.budgetExceeded,
    });
    expect(result.partial, isTrue);
    expect(result.regionOutcomes, isEmpty, reason: '无响应不产生 outcome（不是模型输出）');
  });

  test('重试仅一次：retryable 失败一次后成功；连续失败不再重试', () async {
    var failCount = 0;
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        failCount++;
        if (failCount == 1) {
          return (502, errorEnvelopeJson('providerError', '上游 5xx', true));
        }
        return buildBatchResponseBody(request, confidence: 0.9);
      },
    );
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(captureOf(twoRegionScene()));
    expect(transport.requests, hasLength(2), reason: '初次 + 重试一次');
    expect(result.regionOutcomes.length, 2);
    expect(result.ledger.preservedCount, 0);
    expect(result.failure, isNull, reason: '自动重试成功不挂过期故障');

    var alwaysFail = 0;
    final failingTransport = FakeRecognitionTransport(
      responder: (body) async {
        alwaysFail++;
        return (502, errorEnvelopeJson('providerError', '上游 5xx', true));
      },
    );
    final failingPipeline = pipelineOf(failingTransport);
    final failedResult = await failingPipeline.run(captureOf(twoRegionScene()));
    expect(alwaysFail, 2, reason: '初次 + 至多一次重试，之后放弃');
    expect(failedResult.failure?.code, 'providerError');
    expect(failedResult.failure?.detail, '上游 5xx');
    expect(failedResult.copyWith().failure, same(failedResult.failure));
    expect(failedResult.ledger.preservedCount, 2);
    expect(failedResult.ledger.projection.preservedReasons.values.toSet(), {
      SourcePreserveReason.missingResponse,
    });
  });

  for (final stage in ['read', 'verify', 'structure']) {
    test('$stage 超时不重试，三个阶段使用同一注入超时预算', () async {
      final transport = FakeRecognitionTransport(
        responder: (body) async {
          final req = jsonDecode(body) as Map<String, Object?>;
          if (req['stage'] == stage) {
            return (504, errorEnvelopeJson('providerTimeout', '超时', true));
          }
          return buildBatchResponseBody(
            req,
            confidence: stage == 'verify' ? 0.2 : 0.95,
            textOf: (_) => '图1',
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
        structureRecoverer: stage == 'structure'
            ? const StructureRecovery()
            : null,
      );
      final result = await pipeline.run(
        captureOf(twoRegionScene()),
        budget: const RecognitionBudget(
          perRequestTimeout: Duration(seconds: 75),
        ),
      );
      expect(transport.decodedBodies(stage), hasLength(1));
      expect(result.failure?.code, 'providerTimeout');
      expect(transport.requests.every((r) => r.readTimeoutMs == 75000), isTrue);
      if (stage == 'structure') {
        expect(
          (result.structureResult as StructureResult).modelRejected,
          isTrue,
        );
      } else {
        expect(result.ledger.preservedCount, 2, reason: '失败仍保留所有原笔迹');
      }
    });
  }

  test('客户端 TimeoutException 不重复派发模型', () async {
    final transport = FakeRecognitionTransport(
      errorFactory: (_) async => TimeoutException('read timeout'),
    );
    final result = await pipelineOf(transport).run(captureOf(twoRegionScene()));
    expect(transport.requests, hasLength(1));
    expect(result.failure?.code, 'requestTimeout');
    expect(result.ledger.preservedCount, 2);
  });

  test('无 envelope 的 504 也不重试', () async {
    final transport = FakeRecognitionTransport(
      responder: (_) async => (504, 'Gateway Timeout'),
    );
    final result = await pipelineOf(transport).run(captureOf(twoRegionScene()));
    expect(transport.requests, hasLength(1));
    expect(result.ledger.preservedCount, 2);
  });

  test('剩余总预算不足单次时限：快速错误也不启动注定截断的重试', () async {
    final transport = FakeRecognitionTransport(
      errorFactory: (_) async => Exception('connection refused'),
    );
    final result = await pipelineOf(transport).run(
      captureOf(twoRegionScene()),
      budget: const RecognitionBudget(
        totalTimeout: Duration(seconds: 5),
        perRequestTimeout: Duration(seconds: 10),
      ),
    );
    expect(transport.requests, hasLength(1));
    expect(result.failure?.kind, RecognitionExceptionKind.network);
    expect(result.ledger.preservedCount, 2);
  });

  test('解析失败类不重试：invalidProviderResponse 单次调用', () async {
    var calls = 0;
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        calls++;
        return (
          502,
          errorEnvelopeJson('invalidProviderResponse', '结构校验失败', false),
        );
      },
    );
    final pipeline = pipelineOf(transport);
    final result = await pipeline.run(captureOf(twoRegionScene()));
    expect(calls, 1, reason: '解析失败不得重试');
    expect(result.ledger.preservedCount, 2);
    expect(result.partial, isTrue);
  });

  test('结构 seam：structuring 阶段调用 recoverer 并携带产物', () async {
    final marker = Object();
    RecognitionStructureInput? seenInput;
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = jsonDecode(body) as Map<String, Object?>;
        return buildBatchResponseBody(request, confidence: 0.9);
      },
    );
    final pipeline = RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('https://server.test'),
          post: transport.post,
        ),
      ),
      structureRecoverer: _MarkerRecoverer(marker, (input) {
        seenInput = input;
      }),
    );
    final result = await pipeline.run(captureOf(twoRegionScene()));

    expect(
      pipeline.stateHistory,
      contains(RecognitionPipelineState.structuring),
    );
    expect(result.structureResult, same(marker));
    expect(seenInput, isNotNull);
    expect(seenInput!.regionOutcomes, isNotEmpty);
    expect(seenInput!.regionRecords, isNotEmpty);
  });
}

class _MarkerRecoverer implements RecognitionStructureRecoverer {
  _MarkerRecoverer(this.marker, this.onCalled);

  final Object marker;
  final void Function(RecognitionStructureInput) onCalled;

  @override
  Future<Object?> recover(RecognitionStructureInput input) async {
    onCalled(input);
    return marker;
  }
}
