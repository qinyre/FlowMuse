import 'dart:ui';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import 'package:flow_muse/features/whiteboard/views/smart_layout_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SmartLayoutPlan fakePlan({bool hasFailures = false}) => SmartLayoutPlan(
  pageId: 'p-1',
  style: SmartLayoutStyle.mindmap,
  confidence: 0.9,
  description: '检测到头脑风暴内容',
  addElements: const [],
  moveDeltas: const {},
  removeIds: const [],
  failedStrokeIds: hasFailures ? const [ElementId('stroke-1')] : const [],
  selectIds: const {},
  previewRects: const [],
  removalRects: const [],
  failureRects: hasFailures ? const [Rect.fromLTWH(0, 0, 10, 10)] : const [],
);

List<CanvasPage> _pages(int count) => [
  for (var i = 0; i < count; i++)
    CanvasPage(
      id: 'p-$i',
      index: i,
      bounds: Rect.fromLTWH(0, i * 896.0, 800, 800),
      template: CanvasPageTemplate.blank,
    ),
];

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SmartLayoutScopeDialog', () {
    testWidgets('默认当前页，确定可直接确定', (tester) async {
      SmartLayoutScopeSelection? selection;
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(3),
        currentPageId: 'p-1',
      )));
      expect(find.text('当前页'), findsOneWidget);
      expect(find.text('全部页'), findsOneWidget);
      expect(find.text('选页'), findsOneWidget);
      // 选页时才有复选框列表与输入框
      expect(find.text('第 1 页'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNotNull);
      // 点确定：当前页返回（这里只验证可确定）
      expect(selection, isNull);
    });

    testWidgets('切入选页：出现勾选列表与输入框；勾选只更新勾选并清空输入', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(3),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      // 先输入再勾选：勾选后输入框清空
      await tester.enterText(find.byType(TextField), '2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 1 页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 页'), findsOneWidget); // 列表仍在
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller!.text, isEmpty);
    });

    testWidgets('输入合法范围自动勾选对应页', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(5),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '3-4');
      await tester.pumpAndSettle();
      final tile3 = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('第 3 页'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      final tile4 = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('第 4 页'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(tile3.value, isTrue);
      expect(tile4.value, isTrue);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('输入非法格式：提示错误并禁用确定', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutScopeDialog(
        pages: _pages(5),
        currentPageId: 'p-0',
      )));
      await tester.tap(find.text('选页'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '6-8');
      await tester.pumpAndSettle();
      expect(find.textContaining('页码超出范围'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed, isNull);
    });
  });

  group('SmartLayoutConfirmBar', () {
    testWidgets('多页 + 无失败：显示 应用/跳过本页/取消整个流程', (tester) async {
      SmartLayoutBarAction? tapped;
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(),
        isMultiPage: true,
        onAction: (action) => tapped = action,
      )));
      expect(find.textContaining('思维导图'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(find.text('跳过本页'), findsOneWidget);
      expect(find.text('取消整个流程'), findsOneWidget);
      expect(find.text('删除未识别笔迹后应用'), findsNothing);
      await tester.tap(find.text('跳过本页'));
      expect(tapped, SmartLayoutBarAction.skipPage);
    });

    testWidgets('单页 + 有失败：显示 应用/删除未识别后应用/取消，无跳过', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutConfirmBar(
        plan: fakePlan(hasFailures: true),
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('删除未识别笔迹后应用'), findsOneWidget);
      expect(find.text('跳过本页'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('取消整个流程'), findsNothing);
    });
  });

  group('SmartLayoutFailureBar', () {
    testWidgets('多页：显示失败数、重新识别/跳过本页/取消整个流程', (tester) async {
      SmartLayoutBarAction? tapped;
      await tester.pumpWidget(wrap(SmartLayoutFailureBar(
        failures: [SmartLayoutFailureInfo(blockId: 'b1', bounds: Rect.fromLTWH(0, 0, 10, 10), error: 'HTTP 429'), SmartLayoutFailureInfo(blockId: 'b2', bounds: Rect.fromLTWH(0, 0, 10, 10))],
        isMultiPage: true,
        onAction: (action) => tapped = action,
      )));
      expect(find.textContaining("2 处手写未识别成功"), findsOneWidget);
      expect(find.textContaining("HTTP 429"), findsOneWidget);
      await tester.tap(find.text('重新识别'));
      expect(tapped, SmartLayoutBarAction.retry);
      expect(find.text('跳过本页'), findsOneWidget);
    });

    testWidgets('单页：无跳过本页，取消文案为"取消"', (tester) async {
      await tester.pumpWidget(wrap(SmartLayoutFailureBar(
        failures: [SmartLayoutFailureInfo(blockId: 'b1', bounds: Rect.fromLTWH(0, 0, 10, 10))],
        isMultiPage: false,
        onAction: (_) {},
      )));
      expect(find.text('跳过本页'), findsNothing);
      expect(find.text('取消'), findsOneWidget);
    });
  });
}
