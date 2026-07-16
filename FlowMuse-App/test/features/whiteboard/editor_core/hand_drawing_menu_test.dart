import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('手指绘制开关位于已保存状态右侧', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final values = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdrawEditor(
            saveStatusLabel: '已保存',
            fingerDrawingEnabled: false,
            onFingerDrawingEnabledChanged: values.add,
          ),
        ),
      ),
    );

    expect(find.byTooltip('手指绘制'), findsOneWidget);
    expect(
      tester.getCenter(find.byTooltip('手指绘制')).dx,
      greaterThan(tester.getCenter(find.text('已保存')).dx),
    );
    await tester.tap(find.byTooltip('手指绘制'));
    expect(values, [true]);
  });

  testWidgets('紧凑顶部导航栏也显示手指绘制开关', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdrawEditor(onFingerDrawingEnabledChanged: (_) {}),
        ),
      ),
    );

    expect(find.byTooltip('手指绘制'), findsOneWidget);
  });
}
