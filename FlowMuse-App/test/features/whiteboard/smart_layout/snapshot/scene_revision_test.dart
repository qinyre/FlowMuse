import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/gateways/smart_layout_editor_gateway.dart';
import 'package:flow_muse/features/whiteboard/smart_layout/snapshot/scene_fingerprint.dart';
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
        height: 40,
        seed: 7,
        versionNonce: 11,
        updated: 1000,
        version: version,
      );

  (SmartLayoutEditorGateway, MarkdrawController) setUpGateway() {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    return (SmartLayoutEditorGateway(controller), controller);
  }

  test('观察起点 revision=0/epoch=0 且指纹即当前场景', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);
    expect(tracker.current.revision, 0);
    expect(tracker.current.epoch, 0);
    expect(
      tracker.current.fingerprint,
      SceneFingerprint.of(controller.currentScene),
    );
  });

  test('本地编辑递增；视口/选择不递增', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);

    controller.applyResult(AddElementResult(rect('r1')));
    expect(tracker.current.revision, 1, reason: '本地编辑应递增');

    controller.applyResult(
      UpdateViewportResult(
        const ViewportState(offset: Offset(500, 500), zoom: 2.0),
      ),
    );
    expect(tracker.current.revision, 1, reason: '视口变化不应递增');

    controller.applyResult(SetSelectionResult({ElementId('r1')}));
    expect(tracker.current.revision, 1, reason: '选择变化不应递增');

    // 同内容重放（远端发来相同元素）不递增
    controller.applyRemoteElements([rect('r1')]);
    expect(tracker.current.revision, 1, reason: '内容未变的重放不应递增');
  });

  test('undo/redo 均递增（单调计数而非内容新颖度）', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);

    // 与 v2/commitValidated 语义一致：先压 undo 快照再应用
    gateway.commitValidated(AddElementResult(rect('r1')));
    controller.undo();
    expect(tracker.current.revision, 2);
    controller.redo();
    expect(tracker.current.revision, 3);
  });

  test('远端元素更新递增且 epoch 不变', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);

    controller.applyResult(AddElementResult(rect('r1')));
    controller.applyRemoteElements([rect('r1', x: 77, version: 2)]);
    expect(tracker.current.revision, 2);
    expect(tracker.current.epoch, 0);
  });

  test('reset 递增 epoch 与 revision；load/clear 走兜底只递增 revision', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);

    controller.applyResult(AddElementResult(rect('r1')));
    expect(tracker.current.revision, 1);
    controller.resetCanvas();
    expect(tracker.current.epoch, 1);
    expect(tracker.current.revision, 2);

    controller.loadScene(Scene().addElement(rect('loaded')));
    expect(tracker.current.revision, 3);
    expect(tracker.current.epoch, 1, reason: 'load 无源标签，按既定口径不递增 epoch');

    controller.clear();
    expect(tracker.current.revision, 4);
    expect(tracker.current.epoch, 1);
  });

  test('applyRemoteScene（远端整场景替换）递增且 epoch 不变', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    addTearDown(tracker.dispose);

    controller.applyRemoteScene(Scene().addElement(rect('remote')));
    expect(tracker.current.revision, 1);
    expect(tracker.current.epoch, 0);
  });

  test('两个 tracker 观察同一控制器时指纹一致', () {
    final (gateway, controller) = setUpGateway();
    final t1 = SceneRevisionTracker(editor: gateway);
    final t2 = SceneRevisionTracker(editor: gateway);
    addTearDown(t1.dispose);
    addTearDown(t2.dispose);
    controller.applyResult(AddElementResult(rect('r1')));
    controller.applyRemoteElements([rect('r1', x: 5, version: 2)]);
    expect(t1.current.fingerprint, t2.current.fingerprint);
    expect(t1.current.revision, t2.current.revision);
  });

  test('dispose 后冻结：后续编辑不再推进', () {
    final (gateway, controller) = setUpGateway();
    final tracker = SceneRevisionTracker(editor: gateway);
    controller.applyResult(AddElementResult(rect('r1')));
    final frozen = tracker.current;
    tracker.dispose();
    tracker.dispose();
    expect(tracker.isDisposed, isTrue);
    controller.applyResult(AddElementResult(rect('r2')));
    expect(tracker.current, frozen);
  });

  test('SceneRevision 值语义', () {
    final fingerprint = SceneFingerprint.of(Scene());
    final a = SceneRevision(epoch: 1, revision: 2, fingerprint: fingerprint);
    final same = SceneRevision(epoch: 1, revision: 2, fingerprint: fingerprint);
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a.isInitial, isFalse);
    expect(a.toString(), contains('epoch: 1'));
  });
}
