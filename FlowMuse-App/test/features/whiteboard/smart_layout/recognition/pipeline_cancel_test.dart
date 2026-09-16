import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_models.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_pipeline.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/recognition/recognition_repository.dart';

import 'fake_recognition_transport.dart';

/// 取消语义（spec §6.1）：取消检查点、在途请求取消映射、实例不可复用。
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
    operationId: 'op-cancel',
    generation: 0,
    pageId: 'page-1',
  );

  Scene oneRegionScene() => Scene().addElement(stroke('s1', 10, 20));

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

  test('run 前取消：首个检查点即抛 RecognitionCancelledException', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          buildBatchResponseBody(jsonDecode(body) as Map<String, Object?>),
    );
    final pipeline = pipelineOf(transport);
    pipeline.cancel();
    await expectLater(
      pipeline.run(captureOf(oneRegionScene())),
      throwsA(isA<RecognitionCancelledException>()),
    );
    expect(transport.requests, isEmpty);
  });

  test('在途请求取消：传输层取消映射为 RecognitionCancelledException', () async {
    late RecognitionPipeline pipeline;
    final transport = FakeRecognitionTransport(
      errorFactory: (body) async {
        // 请求已到达传输层：此刻用户取消 → 在途请求被主动取消。
        pipeline.cancel();
        return const NativeHttpCancelledException();
      },
    );
    pipeline = pipelineOf(transport);
    await expectLater(
      pipeline.run(captureOf(oneRegionScene())),
      throwsA(isA<RecognitionCancelledException>()),
    );
    expect(transport.requests, hasLength(1));
  });

  test('结构阶段取消：结构请求后检查点生效（初读请求已发生）', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          buildBatchResponseBody(jsonDecode(body) as Map<String, Object?>),
    );
    late RecognitionPipeline pipeline;
    pipeline = RecognitionPipeline(
      repository: RecognitionRepository(
        gateway: SmartLayoutHttpGateway(
          serverUri: Uri.parse('https://server.test'),
          post: transport.post,
        ),
      ),
      structureRecoverer: _CancellingRecoverer(() => pipeline.cancel()),
    );
    await expectLater(
      pipeline.run(captureOf(oneRegionScene())),
      throwsA(isA<RecognitionCancelledException>()),
    );
    expect(
      transport.requests,
      hasLength(1),
      reason: '初读已完成；取消在 structuring 检查点生效',
    );
    expect(
      pipeline.stateHistory,
      contains(RecognitionPipelineState.structuring),
    );
    expect(
      pipeline.stateHistory,
      isNot(contains(RecognitionPipelineState.assembling)),
      reason: '取消后不得进入装配',
    );
  });

  test('实例不可复用：第二次 run 抛 StateError（一个操作一个实例）', () async {
    final transport = FakeRecognitionTransport(
      responder: (body) async =>
          buildBatchResponseBody(jsonDecode(body) as Map<String, Object?>),
    );
    final pipeline = pipelineOf(transport);
    await pipeline.run(captureOf(oneRegionScene()));
    expect(
      () => pipeline.run(captureOf(oneRegionScene())),
      throwsStateError,
      reason: '显式纠错=新操作：新 pipeline 实例 + 新预算 + generation+1',
    );
  });
}

class _CancellingRecoverer implements RecognitionStructureRecoverer {
  _CancellingRecoverer(this.onRecover);

  final void Function() onRecover;

  @override
  Future<Object?> recover(RecognitionStructureInput input) async {
    onRecover();
    return null;
  }
}
