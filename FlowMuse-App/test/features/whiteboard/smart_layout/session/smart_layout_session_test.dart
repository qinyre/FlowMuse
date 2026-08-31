import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_operation_guard.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/session/smart_layout_session_state.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_revision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  RectangleElement rect(String id, {double x = 10, int version = 1}) =>
      RectangleElement(
        id: ElementId(id),
        x: x,
        y: 10,
        width: 40,
        height: 30,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
      );

  AddElementResult resultOf(String id) => AddElementResult(rect(id));

  (SmartLayoutSession, MarkdrawController, SceneRevisionTracker)
  setUpSession([String pageId = 'page-1']) {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    final editor = SmartLayoutEditorGateway(controller);
    final tracker = SceneRevisionTracker(editor: editor);
    addTearDown(tracker.dispose);
    final session = SmartLayoutSession(
      editor: editor,
      revisions: tracker,
      pageId: pageId,
    );
    return (session, controller, tracker);
  }

  group('reducer 合法迁移表', () {
    const reducer = SmartLayoutSessionReducer();

    test('合法全链：idle→analyzing→reviewing→applying→applied→reset', () {
      var state = reducer.reduce(
        const SessionIdle(),
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisStarted,
          operationId: 'op-1',
        ),
      );
      state = reducer.reduce(
        state,
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: 3,
        ),
      );
      state = reducer.reduce(
        state,
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.candidateChosen,
          candidateId: 'c-1',
        ),
      );
      state = reducer.reduce(
        state,
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.applySucceeded,
          candidateId: 'c-1',
        ),
      );
      expect(state.phase, SmartLayoutSessionPhase.applied);
      state = reducer.reduce(
        state,
        const SmartLayoutSessionEvent(SmartLayoutSessionEventKind.sessionReset),
      );
      expect(state.phase, SmartLayoutSessionPhase.idle);
    });

    test('非法迁移抛异常且不改状态（副作用前失败）', () {
      const reducer = SmartLayoutSessionReducer();
      const idle = SessionIdle();
      for (final kind in [
        SmartLayoutSessionEventKind.analysisSucceeded,
        SmartLayoutSessionEventKind.candidateChosen,
        SmartLayoutSessionEventKind.applySucceeded,
        SmartLayoutSessionEventKind.cancelRequested,
        SmartLayoutSessionEventKind.sessionReset,
      ]) {
        expect(
          () => reducer.reduce(idle, SmartLayoutSessionEvent(kind)),
          throwsA(isA<SmartLayoutSessionInvalidTransition>()),
          reason: 'idle 不接受 $kind',
        );
      }
      // applied 后不可再取消
      const applied = SessionApplied(operationId: 'op-1', candidateId: 'c');
      expect(
        () => reducer.reduce(
          applied,
          const SmartLayoutSessionEvent(
            SmartLayoutSessionEventKind.cancelRequested,
          ),
        ),
        throwsA(isA<SmartLayoutSessionInvalidTransition>()),
      );
    });

    test('analysisStarted 必带 operationId', () {
      expect(
        () => reducer.reduce(
          const SessionIdle(),
          const SmartLayoutSessionEvent(
            SmartLayoutSessionEventKind.analysisStarted,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('四检守卫', () {
    test('通过路径 allow', () {
      final (session, controller, tracker) = setUpSession();
      controller.applyResult(resultOf('a'));
      final ticket = session.beginOperation();
      expect(
        session.checkContinuation(ticket),
        isA<SmartLayoutGuardAllowed>(),
      );
    });

    test('编辑器释放 → disposed', () {
      // 独立控制器（显式释放，避免与共享 tearDown 双重 dispose）
      final controller = MarkdrawController();
      final editor = SmartLayoutEditorGateway(controller);
      final tracker = SceneRevisionTracker(editor: editor);
      final session = SmartLayoutSession(
        editor: editor,
        revisions: tracker,
        pageId: 'page-1',
      );
      final ticket = session.beginOperation();
      controller.dispose();
      expect(
        session.checkContinuation(ticket),
        isA<SmartLayoutGuardRejected>().having(
          (d) => d.reason,
          'reason',
          'disposed',
        ),
      );
    });

    test('迟到回调（旧操作票据）→ operation-mismatch', () {
      final (session, controller, tracker) = setUpSession();
      final staleTicket = session.beginOperation();
      session.advance(
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisFailed,
          reason: 'x',
        ),
      );
      session.reset();
      final freshTicket = session.beginOperation();
      expect(
        session.checkContinuation(staleTicket).toString(),
        contains('operation-mismatch'),
      );
      expect(
        session.checkContinuation(freshTicket),
        isA<SmartLayoutGuardAllowed>(),
        reason: '新操作不受旧票据影响',
      );
    });

    test('取消 → cancelled；新操作不受污染', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      session.cancelOperation(reason: 'user');
      expect(
        session.checkContinuation(ticket).toString(),
        contains('cancelled'),
      );
      session.reset();
      final ticket2 = session.beginOperation();
      expect(session.checkContinuation(ticket2),
          isA<SmartLayoutGuardAllowed>());
    });

    test('离页 → page-changed', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      session.setActivePage('page-2');
      expect(
        session.checkContinuation(ticket).toString(),
        contains('page-changed'),
      );
    });

    test('远端内容变化 → revision-changed', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      controller.applyRemoteElements([
      rect('remote-1', x: 500, version: 2),
      ]);
      expect(
        session.checkContinuation(ticket).toString(),
        contains('revision-changed'),
      );
    });

    test('视口/选择变化不触发 revision 失配', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      controller.applyResult(
        UpdateViewportResult(
          const ViewportState(offset: Offset(999, 999), zoom: 3),
        ),
      );
      controller.applyResult(SetSelectionResult({const ElementId('x')}));
      expect(
        session.checkContinuation(ticket),
        isA<SmartLayoutGuardAllowed>(),
      );
    });
  });

  group('唯一提交入口 completeApply', () {
    test('合法提交：四检通过→Scene 落地→applied', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      session.advance(
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: 2,
        ),
      );
      final decision = session.completeApply(
        ticket,
        candidateId: 'c-1',
        result: resultOf('committed'),
      );
      expect(decision, isA<SmartLayoutGuardAllowed>());
      expect(session.state.phase, SmartLayoutSessionPhase.applied);
      expect(
        controller.currentScene.elements.map((e) => e.id.value),
        contains('committed'),
      );
    });

    test('门禁失败：Scene 零副作用且状态回 failed', () {
      final (session, controller, tracker) = setUpSession();
      final ticket = session.beginOperation();
      session.advance(
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: 2,
        ),
      );
      controller.applyRemoteElements([
        rect('intruder', x: 900, version: 3),
      ]);
      final decision = session.completeApply(
        ticket,
        candidateId: 'c-1',
        result: resultOf('must-not-land'),
      );
      expect(decision, isA<SmartLayoutGuardRejected>());
      expect(
        controller.currentScene.elements.map((e) => e.id.value),
        isNot(contains('must-not-land')),
        reason: '被拒提交不得产生任何 Scene 副作用',
      );
      expect(session.state.phase, SmartLayoutSessionPhase.failed);
    });

    test('非法相位提交 → session-not-applying，无 Scene 副作用', () {
      final (session, controller, tracker) = setUpSession();
      session.beginOperation();
      final decision = session.completeApply(
        SmartLayoutOperationTicket(
          operationId: 'op-1',
          pageId: 'page-1',
          baseRevision: tracker.current,
        ),
        candidateId: 'c',
        result: resultOf('nope'),
      );
      expect(decision.toString(), contains('session-not-applying'));
      expect(
        controller.currentScene.elements.map((e) => e.id.value),
        isNot(contains('nope')),
      );
    });

    test('非法 advance 不污染当前状态', () {
      final (session, controller, tracker) = setUpSession();
      session.beginOperation();
      expect(
        () => session.advance(
          const SmartLayoutSessionEvent(
            SmartLayoutSessionEventKind.applySucceeded,
          ),
        ),
        throwsA(isA<SmartLayoutSessionInvalidTransition>()),
      );
      expect(session.state.phase, SmartLayoutSessionPhase.analyzing);
    });

    test('取消后迟到 apply 不落地（迟到回调不污染新 session）', () {
      final (session, controller, tracker) = setUpSession();
      final ticket1 = session.beginOperation();
      session.advance(
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: 1,
        ),
      );
      session.cancelOperation();
      expect(
        session.completeApply(
          ticket1,
          candidateId: 'c',
          result: resultOf('late'),
        ),
        isA<SmartLayoutGuardRejected>(),
      );
      // 新会话
      session.reset();
      final ticket2 = session.beginOperation();
      session.advance(
        const SmartLayoutSessionEvent(
          SmartLayoutSessionEventKind.analysisSucceeded,
          candidateCount: 1,
        ),
      );
      expect(
        session.completeApply(
          ticket2,
          candidateId: 'c',
          result: resultOf('fresh'),
        ),
        isA<SmartLayoutGuardAllowed>(),
      );
      expect(
        controller.currentScene.elements.map((e) => e.id.value),
        contains('fresh'),
      );
      expect(
        controller.currentScene.elements.map((e) => e.id.value),
        isNot(contains('late')),
      );
    });
  });
}
