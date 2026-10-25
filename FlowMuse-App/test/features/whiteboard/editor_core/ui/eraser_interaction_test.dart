import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/editor_core/src/input/input_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show SystemMouseCursors;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final cancelled in [false, true]) {
      test('原生 $platform 落笔立即定位，${cancelled ? '取消' : '抬笔'}后隐藏光标', () {
        final c = _controller(platform: platform)..switchTool(ToolType.eraser);
        addTearDown(c.dispose);
        c.onPointerHover(const Offset(100, 100));
        expect(c.eraserCursorPosition, isNull);
        _down(c);
        expect(c.eraserCursorPosition, const Offset(5, 5));
        if (cancelled) {
          c.onPointerCancel(
            const PointerCancelEvent(
              pointer: 1,
              kind: PointerDeviceKind.stylus,
            ),
          );
        } else {
          _up(c);
        }
        expect(c.eraserCursorPosition, isNull);
        c.onPointerHover(const Offset(8, 8));
        expect(c.eraserCursorPosition, isNull);
      });
    }
  }
  for (final web in [false, true]) {
    test('${web ? 'Web（移动系统）' : '桌面'}悬停可见，离开画布隐藏', () {
      final c = _controller(
        platform: web ? TargetPlatform.android : TargetPlatform.windows,
        web: web,
      )..switchTool(ToolType.eraser);
      addTearDown(c.dispose);
      c.onPointerHover(const Offset(20, 20));
      expect(c.eraserCursorPosition, const Offset(20, 20));
      _down(c);
      _up(c);
      expect(c.eraserCursorPosition, isNotNull);
      c.onPointerExit();
      expect(c.eraserCursorPosition, isNull);
    });
  }
  test('移动端外接鼠标保留可见系统指针', () {
    final c = _controller(platform: TargetPlatform.android)
      ..switchTool(ToolType.eraser);
    addTearDown(c.dispose);
    expect(c.cursorForTool, isNot(SystemMouseCursors.none));
  });
  for (final interruption in ['cancel', 'switch', 'viewport']) {
    test('擦除后 $interruption 保留单次撤销且不回退远端新增内容', () {
      final c = _controller()
        ..loadScene(Scene().addElement(_rect('old')))
        ..switchTool(ToolType.eraser);
      addTearDown(c.dispose);
      _down(c);
      expect(c.currentScene.activeElements, isEmpty);
      c.applyRemoteElements([_rect('remote', x: 50)]);
      if (interruption == 'cancel') {
        c.onPointerCancel(
          const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus),
        );
      } else if (interruption == 'switch') {
        c.switchTool(ToolType.freedraw);
      } else {
        c.onScaleStart(ScaleStartDetails(focalPoint: const Offset(50, 50)));
        c.onScaleUpdate(
          ScaleUpdateDetails(
            pointerCount: 2,
            scale: 1.2,
            focalPoint: const Offset(50, 50),
          ),
        );
      }
      expect(c.historyManager.undoCount, 1);
      c.undo();
      expect(
        c.currentScene.activeElements.map((e) => e.id.value),
        containsAll(['old', 'remote']),
      );
      c.redo();
      expect(c.currentScene.activeElements.map((e) => e.id.value), ['remote']);
    });
  }
  test('非所有者抬笔或取消不结束当前橡皮交互', () {
    final c = _controller(platform: TargetPlatform.android)
      ..switchTool(ToolType.eraser);
    addTearDown(c.dispose);
    _down(c);
    c.onPointerUp(
      const PointerUpEvent(pointer: 2, kind: PointerDeviceKind.stylus),
    );
    c.onPointerCancel(
      const PointerCancelEvent(pointer: 2, kind: PointerDeviceKind.stylus),
    );
    expect(c.eraserCursorPosition, const Offset(5, 5));
    _up(c);
    expect(c.eraserCursorPosition, isNull);
  });
}

MarkdrawController _controller({
  TargetPlatform platform = TargetPlatform.windows,
  bool web = false,
}) => MarkdrawController(
  inputPolicySelector: InputPolicySelector(platform: platform, isWeb: web),
);
RectangleElement _rect(String id, {double x = 0}) =>
    RectangleElement(id: ElementId(id), x: x, y: 0, width: 10, height: 10);
void _down(MarkdrawController c) => c.onPointerDown(
  const PointerDownEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: Offset(5, 5),
    pressure: .5,
  ),
);
void _up(MarkdrawController c) => c.onPointerUp(
  const PointerUpEvent(
    pointer: 1,
    kind: PointerDeviceKind.stylus,
    position: Offset(5, 5),
  ),
);
