import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/search/view_models/search_view_model.dart';
import 'package:flow_muse/features/search/views/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _longName = '决赛项目讨论与设计方案归档笔记本名称很长';

class _Index extends LibraryIndexNotifier {
  @override
  Future<LibraryIndex> build() async {
    final now = DateTime(2026, 10, 26);
    return LibraryIndex(
      notebooks: [
        LibraryNotebook(
          id: 'book',
          name: _longName,
          coverColor: Colors.blue,
          createdAt: now,
          updatedAt: now,
          sortOrder: 0,
        ),
      ],
      tags: [
        LibraryTag(
          id: 'tag',
          name: '待整理',
          coverColor: Colors.green,
          createdAt: now,
          updatedAt: now,
          sortOrder: 0,
        ),
      ],
      notes: [
        NoteItem(
          id: 'a',
          title: '复习计划',
          updatedAt: now,
          kind: LibraryFilter.notes,
          coverColor: Colors.blue,
          notebookId: 'book',
        ),
        NoteItem(
          id: 'b',
          title: '复习提纲',
          updatedAt: now,
          kind: LibraryFilter.notes,
          coverColor: Colors.green,
          tagIds: const ['tag'],
        ),
      ],
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  double scale = 1,
  bool dark = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [libraryIndexProvider.overrideWith(_Index.new)],
      child: MaterialApp(
        theme: AppTheme.fromPreset(
          appThemePresetById(dark ? AppThemeId.night : AppThemeId.mistBlue),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: SearchPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('重建搜索页后保留查询文字，输入框与结果一致', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '复习');
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(SearchPage)));
    navigator.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '复习',
    );
    expect(find.text('找到 2 条笔记'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索数量随输入及笔记本、标签范围同步，空输入回到说明', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), '复习');
    await tester.pumpAndSettle();
    expect(find.text('找到 2 条笔记'), findsOneWidget);
    await tester.tap(find.byTooltip('选择笔记本范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_longName).last);
    await tester.pumpAndSettle();
    expect(find.text('找到 1 条笔记'), findsOneWidget);
    await tester.tap(find.byTooltip('选择标签范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待整理').last);
    await tester.pumpAndSettle();
    expect(find.text('找到 0 条笔记'), findsOneWidget);
    expect(find.text('没有匹配笔记'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pumpAndSettle();
    expect(find.text('本地搜索 · 标题与副标题'), findsOneWidget);
    expect(find.text('输入标题关键字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? '深色' : '浅色'}搜索在窄屏双倍字号及长筛选名称下不溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pump(tester, scale: 2, dark: dark);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SearchPage)),
      );
      container
          .read(searchViewModelProvider.notifier)
          .selectNotebookScope('book');
      await tester.pumpAndSettle();
      expect(find.text(_longName), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '不匹配的长搜索词不会把状态说明撑出屏幕');
      await tester.pumpAndSettle();
      expect(find.text('找到 0 条笔记'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
