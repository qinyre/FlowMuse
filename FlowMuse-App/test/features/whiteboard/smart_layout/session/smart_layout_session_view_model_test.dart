import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/ink_recognition/native_http_client.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/analysis/smart_layout_analysis_repository.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_http_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/protocol/smart_layout_v3_request.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_view_model.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';

const _okBody = '''
{"protocolVersion":3,"requestId":"req-1","regions":[
 {"id":"g1","role":"title","sourceIds":["s1"],"readingOrder":0,"confidence":0.9,"relations":[]}
],"warnings":[]}''';

/// 可编程 fake 传输步骤：ok / 指定状态码 / 挂起等待外部门。
class _TransportStep {
  const _TransportStep.ok() : _body = _okBody, _status = 200, _gate = null;
  const _TransportStep.gated(Completer<void> this._gate)
    : _body = '',
      _status = 0;
  const _TransportStep.error() : _body = '', _status = 500, _gate = null;

  final String _body;
  final int _status;
  final Completer<void>? _gate;

  Future<NativeHttpResponse> run() async {
    final gate = _gate;
    if (gate != null) await gate.future;
    return NativeHttpResponse(statusCode: _status, body: _body);
  }
}

class _TransportScript {
  _TransportScript(this.steps);
  final List<_TransportStep> steps;
  int call = 0;

  Future<NativeHttpResponse> invoke({
    String? url,
    Map<String, String>? headers,
    String? body,
    int? connectTimeoutMs,
    int? readTimeoutMs,
    Object? cancelToken,
  }) => steps[call++].run();
}

SmartLayoutV3Request _buildRequest() => SmartLayoutV3Request.fromJson(const {
  'protocolVersion': 3,
  'pageId': 'page-1',
  'sceneRevision': {
    'epoch': 0,
    'revision': 1,
    'fingerprint': '0123456789abcdef',
  },
  'assets': [
    {'key': 'clean|page', 'kind': 'clean', 'fingerprint': '0123456789abcdef'},
  ],
  'marks': [],
  'exactTexts': [],
  'sourceRefs': ['s1'],
});

/// 组装真实依赖链：MarkdrawController→gateway→tracker→session→
/// http(fake post)→repository；提交负载为真实可应用的 AddElementResult
///（成功提交在场景中可见，冲突零副作用可断言）。
(ProviderContainer, MarkdrawController, SmartLayoutSession) setUpContainer(
  SmartLayoutHttpPost post, {
  bool capabilityEnabled = true,
}) {
  final controller = MarkdrawController();
  final editor = SmartLayoutEditorGateway(controller);
  final tracker = SceneRevisionTracker(editor: editor);
  addTearDown(tracker.dispose);
  final session = SmartLayoutSession(
    editor: editor,
    revisions: tracker,
    pageId: 'page-1',
  );
  final repo = V3AnalysisRepository(
    http: SmartLayoutHttpGateway(
      serverUri: Uri.parse('http://127.0.0.1:48931'),
      post: post,
    ),
    session: session,
    capabilityEnabled: capabilityEnabled,
  );
  final container = ProviderContainer(
    overrides: [
      smartLayoutSessionDependenciesProvider.overrideWithValue(
        SmartLayoutSessionDependencies(
          session: session,
          repository: repo,
          requestBuilder: (ticket) async => _buildRequest(),
          commitResultBuilder: (candidateId) => AddElementResult(
            RectangleElement(
              id: ElementId('sl3-applied-$candidateId'),
              x: 1,
              y: 1,
              width: 5,
              height: 5,
              seed: 3,
              versionNonce: 4,
              updated: 5,
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(controller.dispose);
  return (container, controller, session);
}

SmartLayoutSessionViewModel vmOf(ProviderContainer c) =>
    c.read(smartLayoutSessionViewModelProvider.notifier);

SmartLayoutSessionUiState stateOf(ProviderContainer c) =>
    c.read(smartLayoutSessionViewModelProvider);

const _twoCandidates = [
  SmartLayoutCandidateSummary(candidateId: 'c1', structureLabel: '单栏'),
  SmartLayoutCandidateSummary(candidateId: 'c2', structureLabel: '双栏'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('初始状态确定；范围/保护操作保持排序与去重', () {
    final (container, _, _) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
    );
    expect(stateOf(container).phase, SmartLayoutSessionPhase.idle);
    expect(stateOf(container).canStartAnalysis, isFalse, reason: '空范围禁启');

    final vm = vmOf(container);
    vm
      ..addScopeSource('s2')
      ..addScopeSource('s1')
      ..addScopeSource('s1')
      ..toggleProtection('s1')
      ..toggleProtection('s3')
      ..toggleProtection('s3');
    final state = stateOf(container);
    expect(state.scopeSourceIds, ['s1', 's2'], reason: '排序且去重');
    expect(state.protectedSourceIds, {'s1'});
    expect(state.canStartAnalysis, isTrue);
  });

  test('全链：分析→生成→review→选择→应用（真实 session 提交路径）', () async {
    final (container, controller, session) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
    );
    final vm = vmOf(container)..addScopeSource('s1');
    await vm.startAnalysis();

    expect(stateOf(container).phase, SmartLayoutSessionPhase.analyzing);
    await Future<void>.delayed(Duration.zero);
    expect(stateOf(container).lastAnalysisResponse, isNotNull);
    expect(
      stateOf(container).phase,
      SmartLayoutSessionPhase.analyzing,
      reason: '分析成功停在 analyzing，等待生成链回调',
    );

    vm.completeGeneration(_twoCandidates);
    expect(stateOf(container).phase, SmartLayoutSessionPhase.reviewing);
    expect(stateOf(container).candidates, hasLength(2));
    expect(stateOf(container).selectedCandidateId, 'c1', reason: '默认选首候选（确定）');

    vm.chooseCandidate('c2');
    expect(stateOf(container).selectedCandidateId, 'c2');
    // 未知候选 id 为 no-op。
    vm.chooseCandidate('ghost');
    expect(stateOf(container).selectedCandidateId, 'c2');

    await vm.applySelectedCandidate();
    expect(stateOf(container).phase, SmartLayoutSessionPhase.applied);
    expect(session.state.phase, SmartLayoutSessionPhase.applied);
    expect(
      controller.currentScene.elements.where(
        (e) => e.id.value == 'sl3-applied-c2',
      ),
      isNotEmpty,
      reason: '真实 commit 经 gateway 落地（场景可见元素）',
    );
  });

  test('重复点击确定：在途 startAnalysis 第二次为 no-op（同票据同计数）', () async {
    final gate = Completer<void>();
    final script = _TransportScript([
      _TransportStep.gated(gate),
      const _TransportStep.ok(), // 重复入口若误发请求将消费此步并暴露
    ]);
    final (container, _, session) = setUpContainer(script.invoke);
    final vm = vmOf(container)..addScopeSource('s1');

    final first = vm.startAnalysis();
    await vm.startAnalysis(); // 第二次点击：no-op
    expect(stateOf(container).attemptCount, 1);
    final ticketBefore = session.activeOperationId;

    gate.complete();
    await first;
    expect(script.call, 1, reason: '只发出一次请求');
    expect(stateOf(container).attemptCount, 1);
    expect(session.activeOperationId, ticketBefore);
  });

  test('取消立即终止：同步推进 cancelled 并清 draft；迟到成功被丢弃', () async {
    final gate = Completer<void>();
    final script = _TransportScript([_TransportStep.gated(gate)]);
    final (container, _, session) = setUpContainer(script.invoke);
    final vm = vmOf(container)..addScopeSource('s1');

    final pending = vm.startAnalysis();
    vm.cancel(); // 同步取消：不等待在途 future
    expect(session.state.phase, SmartLayoutSessionPhase.cancelled);
    expect(stateOf(container).phase, SmartLayoutSessionPhase.cancelled);
    expect(stateOf(container).candidates, isEmpty);
    expect(stateOf(container).failure, isNull, reason: '取消不是失败');
    vm.cancel(); // 幂等
    expect(stateOf(container).phase, SmartLayoutSessionPhase.cancelled);

    gate.complete();
    await pending;
    await Future<void>.delayed(Duration.zero);
    expect(
      stateOf(container).phase,
      SmartLayoutSessionPhase.cancelled,
      reason: '迟到响应不改变已取消状态',
    );
    expect(
      stateOf(container).lastAnalysisResponse,
      isNull,
      reason: 'draft 已清理，迟到响应不回流',
    );
    expect(stateOf(container).failure, isNull);
  });

  test('重试确定：可重试失败→同 scope 重发→计数递增→成功', () async {
    // 首次 VM 分析：仓库内部按策略重试一次（共 2 个 500）后仍失败；
    // VM retry 后第三个响应成功。
    final script = _TransportScript([
      const _TransportStep.error(),
      const _TransportStep.error(),
      const _TransportStep.ok(),
    ]);
    final (container, _, _) = setUpContainer(script.invoke);
    final vm = vmOf(container)..addScopeSource('s1');
    await vm.startAnalysis();

    final failed = stateOf(container);
    expect(failed.phase, SmartLayoutSessionPhase.failed);
    expect(failed.failure, isNotNull);
    expect(failed.failure!.retryable, isTrue, reason: 'badStatus 可重试');
    expect(failed.failure!.attempt, 1);
    expect(failed.canRetry, isTrue);

    await vm.retry();
    await Future<void>.delayed(Duration.zero);
    final retried = stateOf(container);
    expect(retried.phase, SmartLayoutSessionPhase.analyzing);
    expect(retried.attemptCount, 2, reason: 'VM 尝试计数跨重试递增');
    expect(retried.scopeSourceIds, ['s1'], reason: '同 scope 重发');
    expect(script.call, 3, reason: '首次 VM 尝试耗尽仓库内部重试（2 请求），'
        '重试尝试成功（第 3 请求）');

    vm.completeGeneration(_twoCandidates);
    expect(stateOf(container).phase, SmartLayoutSessionPhase.reviewing);
  });

  test('不可重试失败（capabilityOff）与重复 retry no-op', () async {
    final (container, _, _) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
      capabilityEnabled: false,
    );
    final vm = vmOf(container)..addScopeSource('s1');
    await vm.startAnalysis();
    final state = stateOf(container);
    expect(state.phase, SmartLayoutSessionPhase.failed);
    expect(state.failure!.reason, 'capabilityOff');
    expect(state.failure!.retryable, isFalse);
    expect(state.canRetry, isFalse);
    await vm.retry(); // no-op
    expect(stateOf(container).attemptCount, 1);
  });

  test('apply 冲突：reviewing 后远端改写场景→四检拒绝→apply 失败零副作用', () async {
    final (container, controller, session) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
    );
    final vm = vmOf(container)..addScopeSource('s1');
    await vm.startAnalysis();
    await Future<void>.delayed(Duration.zero);
    vm.completeGeneration(_twoCandidates);

    // 权威场景被修改：revision 前进，票据过期。
    controller.applyResult(
      AddElementResult(
        RectangleElement(
          id: ElementId('remote-1'),
          x: 9,
          y: 9,
          width: 5,
          height: 5,
          seed: 3,
          versionNonce: 4,
          updated: 5,
        ),
      ),
    );
    await vm.applySelectedCandidate();

    final state = stateOf(container);
    expect(state.phase, SmartLayoutSessionPhase.failed);
    expect(state.failure!.stage, 'apply');
    expect(state.failure!.retryable, isFalse);
    expect(
      controller.currentScene.elements.where(
        (e) => e.id.value == 'sl3-applied-c1',
      ),
      isEmpty,
      reason: '冲突提交零 Scene 副作用',
    );
    expect(session.state.phase, SmartLayoutSessionPhase.failed);
  });

  test('复位：终态回 idle，scope/保护保留，计数清零；重建恢复确定', () async {
    final (container, _, _) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
    );
    final vm = vmOf(container)..addScopeSource('s1');
    await vm.startAnalysis();
    await Future<void>.delayed(Duration.zero);
    vm.completeGeneration(_twoCandidates);
    vm.cancel();

    vm.reset();
    final state = stateOf(container);
    expect(state.phase, SmartLayoutSessionPhase.idle);
    expect(state.scopeSourceIds, ['s1'], reason: '用户准备数据保留');
    expect(state.attemptCount, 0);
    expect(state.failure, isNull);
    expect(state.activeTicket, isNull);

    // 状态恢复确定：重建容器（模拟视图重建）回到 initial。
    final (fresh, _, _) = setUpContainer(
      _TransportScript(const [_TransportStep.ok()]).invoke,
    );
    expect(stateOf(fresh).phase, SmartLayoutSessionPhase.idle);
    expect(stateOf(fresh).attemptCount, 0);
    expect(stateOf(fresh).scopeSourceIds, isEmpty);
  });
}
