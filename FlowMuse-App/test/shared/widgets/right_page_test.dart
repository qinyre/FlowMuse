import 'package:flow_muse/shared/widgets/right_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('减少动画时标题替换不残留旧页面标题', (tester) async {
    Widget page(String title) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: RightPageScaffold(title: title, body: const SizedBox.shrink()),
      ),
    );
    await tester.pumpWidget(page('全部笔记'));
    await tester.pumpWidget(page('回收站'));
    await tester.pump();
    expect(find.text('全部笔记'), findsNothing);
    expect(find.text('回收站'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360px 页头在 $scale 倍字号下保留标题与全部操作', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: RightPageScaffold(
              title: '全部笔记',
              leadingActions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.menu)),
                IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
              ],
              actions: [
                IconButton(
                  onPressed: () => taps++,
                  icon: const Icon(Icons.grid_view),
                ),
                IconButton(
                  onPressed: () => taps++,
                  icon: const Icon(Icons.sort),
                ),
                IconButton(
                  onPressed: () => taps++,
                  icon: const Icon(Icons.check_box),
                ),
              ],
              body: const SizedBox.shrink(),
            ),
          ),
        ),
      );

      final title = tester.getRect(find.text('全部笔记'));
      expect(title.left, 20);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('全部笔记'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        title.top,
        greaterThanOrEqualTo(
          tester.getBottomRight(find.byType(IconButton).last).dy,
        ),
      );
      for (final icon in [Icons.grid_view, Icons.sort, Icons.check_box]) {
        final button = find.widgetWithIcon(IconButton, icon);
        expect(tester.getSize(button), const Size(48, 48));
        await tester.tapAt(tester.getCenter(button) + const Offset(20, 0));
      }
      expect(taps, 3);
      expect(tester.takeException(), isNull);
    });
  }
}
