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
  });

  test('未知枚举和缺失字段回退到安全默认值', () {
    final restored = EditorPreferences.fromJson({
      'defaultTool': 'future-tool',
      'pressureCurve': 'future-curve',
    });

    expect(restored.defaultTool, ToolType.select);
    expect(restored.defaultBrush, BrushType.fountainPen);
    expect(restored.pressureCurve, PressureCurvePreset.standard);
    expect(restored.brushStates.keys, containsAll(BrushType.values));
  });
}
