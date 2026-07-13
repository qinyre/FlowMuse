import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';

Widget _testApp({AppThemePreset? initialPreset}) {
  return ProviderScope(
    overrides: [
      initialThemePresetProvider.overrideWithValue(
        initialPreset ?? defaultThemePreset,
      ),
    ],
    child: FlowMuseApp(),
  );
}

void main() {
  testWidgets('shows the componentized library shell with sample notebooks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    expect(find.text('全部笔记'), findsWidgets);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);
    expect(find.text('LectureNotes'), findsOneWidget);
  });

  testWidgets('filters PDF notebooks through the library view model', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('library-filter-tabs')),
        matching: find.text('PDF'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LectureNotes'), findsOneWidget);
    expect(find.text('操作系统'), findsNothing);
  });

  testWidgets('opens the whiteboard route from the create card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());

    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pumpAndSettle();

    expect(find.text('未命名白板'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('flowmuse-markdraw-editor')),
      findsOneWidget,
    );
  });

  testWidgets('opens an existing notebook with its stable id', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(initialPreset: appThemePresetById(AppThemeId.night)),
    );

    await tester.tap(find.byKey(const ValueKey('notebook-card-whiteboard-os')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('whiteboard-os')), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);
    final editor = find.byKey(const ValueKey('flowmuse-markdraw-editor'));
    expect(editor, findsOneWidget);
    expect(
      Theme.of(tester.element(editor)).scaffoldBackgroundColor,
      isNot(AppTheme.fromPreset(defaultThemePreset).scaffoldBackgroundColor),
    );
  });

  testWidgets('opens search, folders, and settings pages from navigation', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(initialPreset: appThemePresetById(AppThemeId.starryBlue)),
    );

    await tester.tap(find.text('搜索').first);
    await tester.pumpAndSettle();
    expect(find.text('请输入关键字搜索笔记'), findsOneWidget);

    await tester.tap(find.text('文件夹').first);
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹'), findsWidgets);

    await tester.tap(find.byTooltip('新建文件夹').first);
    await tester.pumpAndSettle();
    expect(find.text('新建文件夹 1'), findsWidgets);

    await tester.tap(find.byTooltip('设置').first);
    await tester.pumpAndSettle();
    expect(find.text('本地备份'), findsWidgets);
    expect(find.text('主题设置'), findsWidgets);

    await tester.tap(find.text('主题设置').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-hero-wallpaper')), findsOneWidget);
  });
}
