import 'dart:ui' show Size;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/config/writing_feature_flags.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final layered in [false, true]) {
    for (final v2 in [false, true]) {
      testWidgets('重压临时擦除不改工具栏、不留墨点，分层=$layered V2=$v2', (tester) async {
        final c = _controller(layered: layered);
        addTearDown(c.dispose);
        c.shouldUseLiveInkV2 = () => v2;
        var cancelled = 0;
        c.onLiveInkCancelled = (_) => cancelled++;
        c.applyStyleChange(
          const ElementStyle(strokeColor: '#228be6', strokeWidth: 5),
        );
        c.pressureSensitivity = .42;
        _down(c);
        await tester.pump(const Duration(milliseconds: 500));
        expect(c.currentScene.activeElements, hasLength(1));
        expect(c.eraserCursorPosition, isNull);
        await tester.pump(const Duration(milliseconds: 100));
        expect(c.editorState.activeToolType, ToolType.freedraw);
        expect(c.eraserCursorPosition, const Offset(5, 5));
        expect(c.currentScene.activeElements, isEmpty);
        expect(cancelled, v2 ? 1 : 0);
        _up(c);
        expect(c.eraserCursorPosition, isNull);
        expect(c.currentScene.elements.whereType<FreedrawElement>(), isEmpty);
        expect(c.defaultStyle.strokeColor, '#228be6');
        expect(c.defaultStyle.strokeWidth, 5);
        expect(c.pressureSensitivity, .42);
        expect(c.historyManager.undoCount, 1);
        c.undo();
        expect(c.currentScene.activeElements, hasLength(1));
        c.redo();
        expect(c.currentScene.activeElements, isEmpty);
        _down(c, pointer: 2, position: const Offset(50, 50), pressure: .5);
        _move(c, pointer: 2, position: const Offset(70, 50), pressure: .5);
        _up(c, pointer: 2, position: const Offset(70, 50));
        expect(c.currentScene.activeElements.single, isA<FreedrawElement>());
      });
    }
  }

  for (final brush in BrushType.values) {
    testWidgets('$brush 重压后保留原笔型', (tester) async {
      final c = _controller()..selectBrush(brush);
      addTearDown(c.dispose);
      _down(c);
      await tester.pump(const Duration(milliseconds: 600));
      _up(c);
      expect(c.editorState.activeToolType, ToolType.freedraw);
      expect(c.activeBrushType, brush);
      expect(c.currentScene.activeElements, isEmpty);
    });
  }

  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.invertedStylus,
  ]) {
    testWidgets('$kind 不触发笔尖重压擦除', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      _down(c, kind: kind);
      await tester.pump(const Duration(seconds: 1));
      expect(c.eraserCursorPosition, isNull);
      expect(
        c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
        isFalse,
      );
      _up(c, kind: kind);
    });
  }

  for (final pressure in [.5, 1.0, double.nan, double.infinity, -1.0, 2.0]) {
    testWidgets('低压、恒定满压或非法压感 $pressure 不擦除', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      _down(c, pressure: pressure);
      await tester.pump(const Duration(seconds: 1));
      expect(c.eraserCursorPosition, isNull);
      expect(
        c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
        isFalse,
      );
      c.onPointerCancel(
        const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
      );
    });
  }

  testWidgets('压力下降重新计时，移动超限后本笔顿笔不触发', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    _down(c);
    await tester.pump(const Duration(milliseconds: 300));
    _move(c, pressure: .5);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.eraserCursorPosition, isNull);
    _move(c, pressure: .9);
    await tester.pump(const Duration(milliseconds: 300));
    _move(c, position: const Offset(20, 5));
    await tester.pump(const Duration(seconds: 1));
    expect(c.eraserCursorPosition, isNull);
    _up(c, position: const Offset(20, 5));
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isFalse,
    );
  });

  testWidgets('微抖允许触发，位置使用最新原始输入', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    _down(c);
    _move(c, position: const Offset(6, 6));
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.eraserCursorPosition, const Offset(6, 6));
    _up(c, position: const Offset(6, 6));
  });

  testWidgets('未到时间抬笔只提交正常笔迹，不迟到擦除', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    _down(c);
    await tester.pump(const Duration(milliseconds: 300));
    _up(c);
    await tester.pump(const Duration(seconds: 1));
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isFalse,
    );
    expect(
      c.currentScene.activeElements.whereType<FreedrawElement>(),
      hasLength(1),
    );
  });

  for (final active in [false, true]) {
    for (final interruption in [
      'cancel',
      'switch',
      'scene',
      'viewport',
      'resize',
      'layout',
      'host',
      'undo',
      'dispose',
    ]) {
      testWidgets('${active ? '擦除中' : '等待中'} $interruption 不留下迟到手势或丢失撤销', (
        tester,
      ) async {
        final c = _controller();
        if (interruption != 'dispose') addTearDown(c.dispose);
        _down(c);
        await tester.pump(Duration(milliseconds: active ? 600 : 200));
        if (interruption == 'cancel') {
          c.onPointerCancel(
            const PointerCancelEvent(
              pointer: 1,
              kind: PointerDeviceKind.stylus,
            ),
          );
        } else if (interruption == 'switch') {
          c.switchTool(ToolType.select);
        } else if (interruption == 'scene') {
          c.loadScene(Scene().addElement(_rect('new')));
        } else if (interruption == 'viewport') {
          c.applyResult(UpdateViewportResult(const ViewportState(zoom: 2)));
        } else if (interruption == 'resize') {
          c.canvasSize = const Size(800, 600);
        } else if (interruption == 'layout') {
          c.setLayout(const CanvasLayout(type: CanvasLayoutType.unbounded));
        } else if (interruption == 'host') {
          c.cancelStylusInteractions();
        } else if (interruption == 'undo') {
          c.undo();
        } else {
          c.dispose();
        }
        await tester.pump(const Duration(seconds: 1));
        expect(c.eraserCursorPosition, isNull);
        if (interruption == 'dispose') return;
        if (interruption == 'scene') {
          expect(c.currentScene.activeElements.map((e) => e.id.value), ['new']);
        } else if (active && interruption != 'undo') {
          expect(c.historyManager.undoCount, 1);
          c.undo();
          expect(
            c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
            isFalse,
          );
        } else {
          expect(
            c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
            isFalse,
          );
        }
      });
    }
  }

  testWidgets('其他指针不能触发、结束或偷走当前临时擦除', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    _down(c);
    _down(c, pointer: 2);
    _move(c, pointer: 2, position: const Offset(50, 5));
    c.onPointerCancel(
      const PointerCancelEvent(pointer: 2, kind: PointerDeviceKind.stylus),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.eraserCursorPosition, const Offset(5, 5));
    _up(c, pointer: 2);
    expect(c.eraserCursorPosition, const Offset(5, 5));
    _up(c);
    expect(c.eraserCursorPosition, isNull);
  });

  testWidgets('笔身双击取消待重压手势，临时擦除中双击不积累切换', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    _down(c);
    c.toggleStylusEraser();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isFalse,
    );
    _up(c);
    expect(c.editorState.activeToolType, ToolType.eraser);
    c.selectBrush(BrushType.fountainPen);
    _down(c, pointer: 2);
    await tester.pump(const Duration(milliseconds: 600));
    c.toggleStylusEraser();
    _up(c, pointer: 2);
    expect(c.editorState.activeToolType, ToolType.freedraw);
  });

  testWidgets('路由或后台 guard 拒绝时不擦除，活动擦除中被拒绝仍可撤销', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    var allowed = false;
    c.canUseStylusGesture = () => allowed;
    _down(c);
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.eraserCursorPosition, isNull);
    c.onPointerCancel(
      const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
    );
    allowed = true;
    _down(c, pointer: 2);
    await tester.pump(const Duration(milliseconds: 600));
    allowed = false;
    _move(c, pointer: 2);
    await tester.pump();
    expect(c.eraserCursorPosition, isNull);
    expect(c.historyManager.undoCount, 1);
  });

  testWidgets('临时擦除继承分组和锁定保护，撤销保留远端新增内容', (tester) async {
    final c = _controller()
      ..loadScene(
        Scene()
            .addElement(_rect('old').copyWith(groupIds: ['group']))
            .addElement(_rect('member').copyWith(x: 50, groupIds: ['group']))
            .addElement(
              _rect(
                'locked',
              ).copyWith(x: 100, locked: true, groupIds: ['group']),
            ),
      );
    addTearDown(c.dispose);
    _down(c);
    await tester.pump(const Duration(milliseconds: 600));
    c.applyRemoteElements([_rect('remote').copyWith(x: 150)]);
    _up(c);
    expect(
      c.currentScene.activeElements.map((e) => e.id.value),
      containsAll(['locked', 'remote']),
    );
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isTrue,
    );
    expect(
      c.currentScene.getElementById(const ElementId('member'))!.isDeleted,
      isTrue,
    );
    c.undo();
    expect(c.currentScene.activeElements, hasLength(4));
    c.redo();
    expect(
      c.currentScene.activeElements.map((e) => e.id.value),
      containsAll(['locked', 'remote']),
    );
  });

  testWidgets('自定义压力范围归一化且屏幕位移阈值不随缩放改变', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.applyResult(UpdateViewportResult(const ViewportState(zoom: .5)));
    c.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(5, 5),
        pressure: 19,
        pressureMin: 10,
        pressureMax: 20,
      ),
    );
    c.onPointerMove(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(6, 5),
        pressure: 19,
        pressureMin: 10,
        pressureMax: 20,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.eraserCursorPosition, const Offset(6, 5));
    _up(c, position: const Offset(6, 5));
  });

  testWidgets('设备缺省压力范围时复用原有 0..1 取值回退', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(5, 5),
        pressure: .9,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(c.eraserCursorPosition, isNotNull);
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isTrue,
    );
    _up(c);
  });

  testWidgets('缺省范围与恒定默认压力不被当作真实重压', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.onPointerDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(5, 5),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(c.eraserCursorPosition, isNull);
    expect(
      c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
      isFalse,
    );
    _up(c);
  });

  for (final active in [false, true]) {
    testWidgets('远端全场景更新不打断${active ? '临时擦除' : '待重压笔迹'}', (tester) async {
      final c = _controller();
      addTearDown(c.dispose);
      _down(c);
      await tester.pump(Duration(milliseconds: active ? 600 : 200));
      c.applyRemoteScene(
        c.currentScene.addElement(_rect('remote').copyWith(x: 100)),
      );
      if (!active) await tester.pump(const Duration(milliseconds: 400));
      expect(c.eraserCursorPosition, isNotNull);
      _up(c);
      expect(
        c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
        isTrue,
      );
      c.undo();
      expect(
        c.currentScene.getElementById(const ElementId('old'))!.isDeleted,
        isFalse,
      );
      expect(
        c.currentScene.getElementById(const ElementId('remote'))!.isDeleted,
        isFalse,
      );
    });
  }
}

MarkdrawController _controller({bool layered = true}) =>
    MarkdrawController(
        inputPolicySelector: const InputPolicySelector(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        writingFlags: WritingFeatureFlags(layeredWetInk: layered),
      )
      ..loadScene(Scene().addElement(_rect('old')))
      ..selectBrush(BrushType.fountainPen);
RectangleElement _rect(String id) =>
    RectangleElement(id: ElementId(id), x: 0, y: 0, width: 20, height: 20);
void _down(
  MarkdrawController c, {
  int pointer = 1,
  Offset position = const Offset(5, 5),
  double pressure = .9,
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => c.onPointerDown(
  PointerDownEvent(
    pointer: pointer,
    kind: kind,
    position: position,
    pressure: pressure,
    pressureMin: 0,
    pressureMax: 1,
  ),
);
void _move(
  MarkdrawController c, {
  int pointer = 1,
  Offset position = const Offset(5, 5),
  double pressure = .9,
}) => c.onPointerMove(
  PointerMoveEvent(
    pointer: pointer,
    kind: PointerDeviceKind.stylus,
    position: position,
    pressure: pressure,
    pressureMin: 0,
    pressureMax: 1,
  ),
);
void _up(
  MarkdrawController c, {
  int pointer = 1,
  Offset position = const Offset(5, 5),
  PointerDeviceKind kind = PointerDeviceKind.stylus,
}) => c.onPointerUp(
  PointerUpEvent(pointer: pointer, kind: kind, position: position),
);
