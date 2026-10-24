import 'dart:async';

import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/views/create_note_page.dart';
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flow_muse/features/whiteboard/view_models/editor_preferences_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends EditorPreferencesViewModel {
  @override
  Future<EditorPreferences> build() async => EditorPreferences();
}

class _PendingCreation implements LibraryRepository {
  final pending = Completer<NoteItem>();
  var calls = 0;

  @override
  Future<NoteItem> createNote({
    LibraryFilter kind = LibraryFilter.notes,
    NoteType noteType = NoteType.unbounded,
    PageTemplate pageTemplate = PageTemplate.blank,
    PageFlow pageFlow = PageFlow.topToBottom,
    String? title,
    String? subtitle,
    String? notebookId,
    List<String> tagIds = const [],
  }) {
    calls++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _page({
  double scale = 1,
  AppThemeId theme = AppThemeId.day,
  bool reduceMotion = false,
  LibraryRepository? repository,
}) => ProviderScope(
  overrides: [
    editorPreferencesProvider.overrideWith(_Preferences.new),
    if (repository != null)
      libraryRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(
    theme: AppTheme.fromPreset(appThemePresetById(theme)),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: child!,
    ),
    home: const CreateNotePage(),
  ),
);

void main() {
  testWidgets('跨断点缩放窗口保留标题输入连接和焦点', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '课堂');
    final inputState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    await tester.binding.setSurfaceSize(const Size(360, 900));
    await tester.pumpAndSettle();
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(inputState),
    );
    expect(inputState.widget.focusNode.hasFocus, isTrue);
    tester.testTextInput.enterText('课堂笔记');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '课堂笔记',
    );
    expect(tester.takeException(), isNull);
  });

  for (final (width, scale, theme) in [
    (360.0, 1.0, AppThemeId.day),
    (360.0, 2.0, AppThemeId.night),
    (1280.0, 1.0, AppThemeId.day),
  ]) {
    testWidgets('新建笔记 ${width}px / ${scale}x 可输入并选择模板，无布局溢出', (tester) async {
      // Given: 新建页使用真实组件，偏好来源隔离为内存。
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_page(scale: scale, theme: theme));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final input = find.byType(TextField);
      expect(tester.getRect(input).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(input).right, lessThanOrEqualTo(width));
      expect(find.text('导入 PDF'), findsOneWidget);
      await tester.enterText(input, '课堂笔记');

      // When: 滚动到模板并选择，随后回到输入区。
      final grid = find.text(PageTemplate.grid.displayName).last;
      await tester.ensureVisible(grid);
      await tester.tap(grid);
      await tester.pumpAndSettle();
      expect(find.text(PageTemplate.grid.displayName), findsNWidgets(2));
      await tester.ensureVisible(find.text('无界'));
      await tester.tap(find.text('无界'));
      await tester.pumpAndSettle();

      // Then: 原标题保留，排列选项按无界画布规则禁用。
      expect(tester.widget<TextField>(input).controller!.text, '课堂笔记');
      expect(find.text('无界画布，可向四周自由延展。'), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<PageFlow>>(
              find.byType(SegmentedButton<PageFlow>),
            )
            .onSelectionChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动画时模板选择直接完成', (tester) async {
    await tester.pumpWidget(_page(reduceMotion: true));
    await tester.pumpAndSettle();
    final grid = find.text(PageTemplate.grid.displayName).last;
    await tester.ensureVisible(grid);
    await tester.tap(grid);
    await tester.pump();
    expect(find.text(PageTemplate.grid.displayName), findsNWidgets(2));
    final surface = find.ancestor(
      of: grid,
      matching: find.byType(AnimatedContainer),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: surface,
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.color,
      Theme.of(tester.element(grid)).colorScheme.primaryContainer,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('创建中禁用重复操作，失败后恢复输入和创建入口', (tester) async {
    final repository = _PendingCreation();
    await tester.pumpWidget(_page(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pump();
    expect(find.text('处理中…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '导入 PDF'))
          .onPressed,
      isNull,
    );
    expect(repository.calls, 1);
    repository.pending.completeError(StateError('测试创建失败'));
    await tester.pumpAndSettle();
    expect(find.text('创建'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(find.textContaining('创建失败：'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
