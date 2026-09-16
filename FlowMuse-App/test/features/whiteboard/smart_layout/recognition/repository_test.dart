import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';

import 'fake_recognition_transport.dart';

/// 仓库层（spec §2/§3.5）：错误映射、readTimeout、主动取消、回填校验。
void main() {
  const sceneRevision = RecognitionSceneRevision(
    epoch: 0,
    revision: 5,
    fingerprint: '0123456789abcdef',
  );

  RecognitionReadRequest requestOf({String operationId = 'op-1'}) =>
      RecognitionReadRequest(
        operationId: operationId,
        requestId: 'req-1',
        pageId: 'page-1',
        sceneRevision: sceneRevision,
        contentFingerprint: 'fedcba9876543210',
        generation: 0,
        regions: const [
          RecognitionRegionImage(
            regionId: 'r:a',
            imagePngBase64:
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
                'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
            imageScale: 2,
          ),
        ],
      );

  Map<String, Object?> requestBodyOf(String body) =>
      jsonDecode(body) as Map<String, Object?>;

  test('成功路径：回填外壳响应解析为 batch 响应；readTimeout=min(45s,剩余)', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          buildBatchResponseBody(requestBodyOf(body), confidence: 0.95),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    final response = await repository.send(
      requestOf(),
      remainingBudget: const Duration(seconds: 120),
    );
    expect(response, isA<RecognitionBatchResponse>());
    final batch = response as RecognitionBatchResponse;
    expect(batch.regions.single.status, RecognitionRegionStatus.recognized);
    expect(batch.missingRegionIds, isEmpty);
    final recorded = transport.requests.single;
    expect(recorded.readTimeoutMs, 45000, reason: '剩余 120s > 45s → 取 45s');
    expect(
      recorded.url,
      'https://server.test/api/ink/smart-layout/recognize/v3',
    );
    expect(recorded.headers['content-type'], 'application/json');
  });

  test('剩余预算收紧 readTimeout', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async => buildBatchResponseBody(requestBodyOf(body)),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await repository.send(
      requestOf(),
      remainingBudget: const Duration(seconds: 3),
    );
    expect(transport.requests.single.readTimeoutMs, 3000);
  });

  test('剩余预算为零：不发出请求', () async {
    final transport = FakeRecognitionTransport();
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(requestOf(), remainingBudget: Duration.zero),
      throwsA(
        isA<RecognitionException>()
            .having(
              (e) => e.kind,
              'kind',
              RecognitionExceptionKind.budgetExhausted,
            )
            .having((e) => e.retryable, 'retryable', false),
      ),
    );
    expect(transport.requests, isEmpty);
  });

  test('错误 envelope 映射：providerError retryable=true', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          (502, errorEnvelopeJson('providerError', '上游 5xx', true)),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>()
            .having((e) => e.kind, 'kind', RecognitionExceptionKind.serverCode)
            .having((e) => e.code, 'code', 'providerError')
            .having((e) => e.retryable, 'retryable', true),
      ),
    );
  });

  test('错误 envelope 映射：invalidProviderResponse 不重试；busy 可重试', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          (502, errorEnvelopeJson('invalidProviderResponse', '结构校验失败', false)),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>().having(
          (e) => e.retryable,
          'retryable',
          false,
        ),
      ),
    );

    final busyTransport = FakeRecognitionTransport(
      responder: (body) async => (429, errorEnvelopeJson('busy', '满', true)),
    );
    final busyRepository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: busyTransport.post,
      ),
    );
    await expectLater(
      busyRepository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>()
            .having((e) => e.code, 'code', 'busy')
            .having((e) => e.retryable, 'retryable', true),
      ),
    );
  });

  test('网络故障映射 network retryable', () async {
    final transport = FakeRecognitionTransport(
      errorFactory: (body) async => Exception('socket closed'),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>()
            .having((e) => e.kind, 'kind', RecognitionExceptionKind.network)
            .having((e) => e.retryable, 'retryable', true),
      ),
    );
  });

  test('响应体非法 JSON → invalidResponse 不重试', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async => (200, '这不是 JSON'),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>()
            .having(
              (e) => e.kind,
              'kind',
              RecognitionExceptionKind.invalidResponse,
            )
            .having((e) => e.retryable, 'retryable', false),
      ),
    );
  });

  test('回填外壳不一致（R-12）→ invalidResponse（过期响应丢弃）', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async {
        final request = requestBodyOf(body);
        final tampered = Map<String, Object?>.from(request);
        tampered['operationId'] = 'other-operation';
        return buildBatchResponseBody(tampered);
      },
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    await expectLater(
      repository.send(
        requestOf(),
        remainingBudget: const Duration(seconds: 30),
      ),
      throwsA(
        isA<RecognitionException>().having(
          (e) => e.kind,
          'kind',
          RecognitionExceptionKind.invalidResponse,
        ),
      ),
    );
  });

  test('missingRegionIds 部分批次合法（200 + missing 显式声明）', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async => buildBatchResponseBody(
        requestBodyOf(body),
        missingRegionIds: {'r:a'},
      ),
    );
    final repository = RecognitionRepository(
      gateway: SmartLayoutHttpGateway(
        serverUri: Uri.parse('https://server.test'),
        post: transport.post,
      ),
    );
    final response = await repository.send(
      requestOf(),
      remainingBudget: const Duration(seconds: 30),
    );
    final batch = response as RecognitionBatchResponse;
    expect(batch.regions, isEmpty);
    expect(batch.missingRegionIds, ['r:a']);
  });
}
