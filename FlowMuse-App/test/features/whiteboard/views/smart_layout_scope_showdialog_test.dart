
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 回归：智能排版范围选择框经真实 showDialog 路由渲染（AlertDialog 带 IntrinsicWidth），
/// 不得出现 "RenderViewport/RenderShrinkWrappingViewport does not support returning
/// intrinsic dimensions" 导致的空白对话框（此前 ListView 触发，测试直泵组件无法复现）。
void main() {
  testWidgets('范围选择框经真实 showDialog 打开且内容可见（多页+小窗口）', (tester) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<SmartLayoutScopeSelection>(
                  context: context,
                  builder: (_) => SmartLayoutScopeDialog(
                    pages: [
                      for (var i = 0; i < 6; i++)
                        CanvasPage(
                          id: 'p-$i',
                          index: i,
                          bounds: Rect.fromLTWH(0, i * 896.0, 800, 800),
                          template: CanvasPageTemplate.blank,
                        ),
                    ],
                    currentPageId: 'p-1',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('当前页'), findsOneWidget);
    await tester.tap(find.text('选页'));
    await tester.pumpAndSettle();
    // 内容与勾选列表可见、无布局异常
    expect(find.text('第 1 页'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });
}
