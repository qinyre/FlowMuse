import 'package:flow_muse/features/library/widgets/note_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ValueNotifier<double>> pumpGrid(
    WidgetTester tester, {
    bool reduced = false,
    int count = 80,
    TextDirection direction = TextDirection.ltr,
    ValueChanged<int>? onBuild,
  }) async {
    final width = ValueNotifier(500.0);
    addTearDown(width.dispose);
    Widget item(BuildContext context, int index) {
      onBuild?.call(index);
      return ColoredBox(
        key: ValueKey('tile-$index'),
        color: Colors.teal,
        child: Text('$index'),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Directionality(
            textDirection: direction,
            child: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (context, value, _) => SizedBox(
                  width: value,
                  height: 400,
                  child: NoteGrid(itemCount: count, itemBuilder: item),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return width;
  }

  for (final direction in TextDirection.values) {
    testWidgets('$direction 换列移动连续，已有卡片不逐帧重建', (tester) async {
      final builds = <int, int>{};
      final width = await pumpGrid(
        tester,
        direction: direction,
        onBuild: (index) =>
            builds.update(index, (n) => n + 1, ifAbsent: () => 1),
      );
      final tile = find.byKey(const ValueKey('tile-3'));
      final before = tester.getCenter(tile);
      width.value = 700;
      await tester.pump();
      expect(tester.getCenter(tile).dy, before.dy);
      await tester.pump(const Duration(milliseconds: 80));
      final middle = tester.getCenter(tile);
      expect(middle.dy, lessThan(before.dy));
      await tester.pumpAndSettle();
      final after = tester.getCenter(tile);
      expect(middle.dy, greaterThan(after.dy));
      expect(builds[3], 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动画立即使用最终布局', (tester) async {
    final width = await pumpGrid(tester, reduced: true);
    width.value = 700;
    await tester.pump();
    final tile = find.byKey(const ValueKey('tile-3'));
    expect(tester.getTopLeft(tile).dy, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续反向改宽和销毁不跳回旧布局或遗留 ticker', (tester) async {
    final width = await pumpGrid(tester);
    for (final value in [700.0, 500.0, 750.0, 450.0, 700.0]) {
      width.value = value;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('tile-3'))).dy, 0);
    width.value = 500;
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('十万条笔记深滚动换列仍按需构建，几何边界正确', (tester) async {
    var built = 0;
    final width = await pumpGrid(
      tester,
      count: 100000,
      onBuild: (_) => built++,
    );
    tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position
        .jumpTo(2000000);
    await tester.pump();
    width.value = 700;
    await tester.pump();
    for (var frame = 0; frame < 13; frame++) {
      built = 0;
      await tester.pump(const Duration(milliseconds: 16));
      expect(built, lessThan(80));
      final grid = tester.widget<GridView>(find.byType(GridView));
      final sliver = tester.renderObject<RenderSliverGrid>(
        find.byType(SliverGrid),
      );
      final layout = grid.gridDelegate.getLayout(sliver.constraints);
      for (final offset in [0.0, 15.0, 260.0, 10000.0, 2000000.0]) {
        final first = layout.getMinChildIndexForScrollOffset(offset);
        final last = layout.getMaxChildIndexForScrollOffset(offset);
        // The SDK's regular layout may include the preceding row in a gap.
        if (layout is! SliverGridRegularTileLayout) {
          expect(
            layout.getGeometryForChildIndex(first).trailingScrollOffset,
            greaterThan(offset),
          );
        }
        if (first > 0) {
          expect(
            layout.getGeometryForChildIndex(first - 1).trailingScrollOffset,
            lessThanOrEqualTo(offset),
          );
        }
        if (offset > 0) {
          expect(
            layout.getGeometryForChildIndex(last).scrollOffset,
            lessThan(offset),
          );
          expect(
            layout.getGeometryForChildIndex(last + 1).scrollOffset,
            greaterThanOrEqualTo(offset),
          );
        }
      }
    }
    expect(tester.takeException(), isNull);
  });
}
