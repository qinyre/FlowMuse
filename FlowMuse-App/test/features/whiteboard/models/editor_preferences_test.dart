import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('编辑器偏好 JSON 往返保留工具、手势和每支笔状态', () {
    final preferences = EditorPreferences(
      defaultTool: ToolType.freedraw,
      defaultBrush: BrushType.pencil,
      brushStates: {
        BrushType.pencil: BrushState.defaults[BrushType.pencil]!.copyWith(
          strokeColor: '#e03131',
          strokeWidth: 6,
          pressureSensitivity: 0.4,
        ),
      },
      pressureEnabled: false,
      pressureCurve: PressureCurvePreset.firm,
      palmRejectionEnabled: false,
      twoFingerZoomEnabled: false,
      singleFingerPanEnabled: false,
      fingerDrawingEnabled: true,
      autosaveInterval: AutosaveInterval.threeSeconds,
      defaultLayoutType: CanvasLayoutType.unbounded,
      defaultPageTemplate: CanvasPageTemplate.dotGrid,
      defaultPageFlow: CanvasPageFlow.rightToLeft,
    );

    final restored = EditorPreferences.fromJson(preferences.toJson());

    expect(restored.defaultTool, ToolType.freedraw);
    expect(restored.defaultBrush, BrushType.pencil);
    expect(restored.brushState(BrushType.pencil).strokeColor, '#e03131');
    expect(restored.brushState(BrushType.pencil).strokeWidth, 6);
    expect(restored.brushState(BrushType.pencil).pressureSensitivity, 0.4);
    expect(restored.pressureEnabled, isFalse);
    expect(restored.pressureCurve, PressureCurvePreset.firm);
    expect(restored.palmRejectionEnabled, isFalse);
    expect(restored.twoFingerZoomEnabled, isFalse);
    expect(restored.singleFingerPanEnabled, isFalse);
    expect(restored.fingerDrawingEnabled, isTrue);
    expect(restored.autosaveInterval, AutosaveInterval.threeSeconds);
    expect(restored.defaultLayoutType, CanvasLayoutType.unbounded);
    expect(restored.defaultPageTemplate, CanvasPageTemplate.dotGrid);
    expect(restored.defaultPageFlow, CanvasPageFlow.rightToLeft);
  });

  test('未知枚举和缺失字段回退到安全默认值', () {
    final restored = EditorPreferences.fromJson({
      'defaultTool': 'future-tool',
      'pressureCurve': 'future-curve',
      'autosaveInterval': 'future-interval',
      'defaultLayoutType': 'future-layout',
      'defaultPageTemplate': 'future-template',
      'defaultPageFlow': 'future-flow',
    });

    expect(restored.defaultTool, ToolType.select);
    expect(restored.defaultBrush, BrushType.fountainPen);
    expect(restored.fingerDrawingEnabled, isFalse);
    expect(restored.pressureCurve, PressureCurvePreset.standard);
    expect(restored.brushStates.keys, containsAll(BrushType.values));
    expect(restored.autosaveInterval, AutosaveInterval.halfSecond);
    expect(restored.defaultLayoutType, CanvasLayoutType.paged);
    expect(restored.defaultPageTemplate, CanvasPageTemplate.blank);
    expect(restored.defaultPageFlow, CanvasPageFlow.topToBottom);
  });

  test('关闭自动保存时不创建延迟计时', () {
    expect(AutosaveInterval.off.duration, isNull);
    expect(
      AutosaveInterval.halfSecond.duration,
      const Duration(milliseconds: 500),
    );
  });
}
