import 'package:flow_muse/features/whiteboard/collaboration/widgets/collaboration_view_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('位置邀请在窄屏大字号下可查看或忽略，不自动执行', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var viewed = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CollaborationViewNotice(
                label: '这是一个较长的协作者名字 邀请你看这里',
                actionLabel: '查看位置',
                onAction: () => viewed++,
                onDismiss: () => dismissed++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(viewed, 0);
    expect(dismissed, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('查看位置'));
    expect(viewed, 1);
    await tester.tap(find.text('忽略'));
    expect(dismissed, 1);
  });
}
