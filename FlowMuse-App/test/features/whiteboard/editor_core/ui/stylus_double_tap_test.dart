import 'dart:async';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/ui/stylus_double_tap_channel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brush in BrushType.values) {
    testWidgets('笔身双击保留 $brush 的颜色、粗细、压感且不写历史', (tester) async {
      final controller = MarkdrawController()..selectBrush(brush);
      addTearDown(controller.dispose);
      controller.applyStyleChange(
        const ElementStyle(strokeColor: '#e03131', strokeWidth: 5),
      );
      controller.pressureSensitivity = 0.42;
      final scene = controller.currentScene;
      var sceneChanges = 0;
      controller.onSceneChanged = (_, _) => sceneChanges++;
      controller.toggleStylusEraser();
      expect(controller.editorState.activeToolType, ToolType.eraser);
      controller.toggleStylusEraser();
      expect(controller.editorState.activeToolType, ToolType.freedraw);
      expect(controller.activeBrushType, brush);
      expect(controller.defaultStyle.strokeColor, '#e03131');
      expect(controller.defaultStyle.strokeWidth, 5);
      expect(controller.pressureSensitivity, 0.42);
      expect(controller.currentScene, same(scene));
      expect(controller.historyManager.undoCount, 0);
      expect(sceneChanges, 0);
      await tester.pump();
    });
  }

  for (final layered in [false, true]) {
    testWidgets('落笔双击等待终笔，不截断、不发送取消，湿墨分层=$layered', (tester) async {
      final controller = MarkdrawController(
        writingFlags: WritingFeatureFlags(layeredWetInk: layered),
      )..selectBrush(BrushType.fountainPen);
      addTearDown(controller.dispose);
      var cancellations = 0;
      controller.onLiveInkCancelled = (_) => cancellations++;
      controller.shouldUseLiveInkV2 = () => true;
      _down(controller);
      _move(controller);
      controller.toggleStylusEraser();
      expect(controller.editorState.activeToolType, ToolType.freedraw);
      _up(controller);
      expect(controller.editorState.activeToolType, ToolType.eraser);
      final ink = controller.currentScene.elements.single as FreedrawElement;
      expect(ink.points.length, greaterThan(1));
      expect(cancellations, 0);
      expect(controller.historyManager.undoCount, 1);
      controller.undo();
      expect(controller.currentScene.activeElements, isEmpty);
      await tester.pump();
    });
  }

  testWidgets('笔尖连续点画两次不会被识别为笔身双击', (tester) async {
    final controller = MarkdrawController()..selectBrush(BrushType.ballpoint);
    addTearDown(controller.dispose);
    for (var i = 0; i < 2; i++) {
      _down(controller);
      _move(controller);
      _up(controller);
    }
    expect(controller.editorState.activeToolType, ToolType.freedraw);
    expect(controller.currentScene.activeElements, hasLength(2));
    await tester.pump();
  });

  testWidgets('取消、手动切工具与后台清理不留下延迟切换', (tester) async {
    for (final interruption in ['cancel', 'manual', 'background']) {
      final controller = MarkdrawController()..selectBrush(BrushType.pencil);
      _down(controller);
      _move(controller);
      controller.toggleStylusEraser();
      if (interruption == 'manual') {
        controller.switchTool(ToolType.select);
      } else if (interruption == 'background') {
        controller.cancelPendingStylusEraserToggle();
        _up(controller);
      } else {
        controller.onPointerCancel(
          const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
        );
      }
      controller.selectBrush(BrushType.pencil);
      _down(controller);
      _move(controller);
      _up(controller);
      expect(controller.editorState.activeToolType, ToolType.freedraw);
      await tester.pump();
      controller.dispose();
    }
  });

  testWidgets('选择、文字和只读模式不被笔身双击改变', (tester) async {
    final controller = MarkdrawController();
    addTearDown(controller.dispose);
    for (final type in [ToolType.select, ToolType.text, ToolType.hand]) {
      controller.switchTool(type);
      controller.toggleStylusEraser();
      expect(controller.editorState.activeToolType, type);
    }
    controller.selectBrush(BrushType.pencil);
    controller.toggleViewMode();
    controller.toggleStylusEraser();
    expect(controller.editorState.activeToolType, ToolType.hand);
    controller.toggleViewMode();
    controller.startTextEditingExisting(
      TextElement(
        id: const ElementId('text'),
        x: 0,
        y: 0,
        width: 100,
        height: 20,
        text: 'test',
      ),
    );
    controller.toggleStylusEraser();
    expect(controller.editorState.activeToolType, ToolType.freedraw);
    expect(controller.editingTextElementId, isNotNull);
    await tester.pump();
  });

  group('原生笔身双击通道', () {
    const channel = MethodChannel('flow_muse/stylus_double_tap');
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<Map<Object?, Object?>> subscriptions;

    setUp(() {
      subscriptions = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        subscriptions.add(Map<Object?, Object?>.from(call.arguments as Map));
        return null;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> native(Object? args) async {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall('doubleTap', args)),
        (_) => done.complete(),
      );
      await done.future;
    }

    test('共享监听、事件去重、非法字段与旧会话隔离', () async {
      var first = 0;
      var second = 0;
      final a = StylusDoubleTapChannel.instance.events.listen((_) => first++);
      final b = StylusDoubleTapChannel.instance.events.listen((_) => second++);
      await Future<void>.delayed(Duration.zero);
      expect(subscriptions, hasLength(1));
      final generation = subscriptions.single['generation'];
      await native({'generation': generation, 'timestamp': 1000});
      await native({'generation': generation, 'timestamp': 1000});
      await native({'generation': generation, 'timestamp': 1100});
      await native({'generation': generation, 'timestamp': double.nan});
      await native({'generation': generation, 'timestamp': '2000'});
      await native({'generation': -1, 'timestamp': 2000});
      await native(null);
      expect(first, 1);
      expect(second, 1);
      await a.cancel();
      expect(subscriptions, hasLength(1));
      await native({'generation': generation, 'timestamp': 2000});
      expect(first, 1);
      expect(second, 2);
      await b.cancel();
      expect(subscriptions.last['enabled'], false);
      final c = StylusDoubleTapChannel.instance.events.listen((_) => first++);
      await Future<void>.delayed(Duration.zero);
      await native({'generation': generation, 'timestamp': 3000});
      expect(first, 1);
      await native({
        'generation': subscriptions.last['generation'],
        'timestamp': 3000,
      });
      expect(first, 2);
      await c.cancel();
    });

    test('缺失插件不阻塞编辑器或产生未处理异常', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw MissingPluginException();
      });
      final subscription = StylusDoubleTapChannel.instance.events.listen((_) {
        fail('unsupported platform must not emit a barrel gesture');
      });
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
    });
  });
}

void _down(MarkdrawController controller) => controller.onPointerDown(
  const PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus),
);
void _move(MarkdrawController controller) => controller.onPointerMove(
  const PointerMoveEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: Offset(30, 20),
    timeStamp: Duration(milliseconds: 10),
  ),
);
void _up(MarkdrawController controller) => controller.onPointerUp(
  const PointerUpEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: Offset(60, 35),
    timeStamp: Duration(milliseconds: 20),
  ),
);
