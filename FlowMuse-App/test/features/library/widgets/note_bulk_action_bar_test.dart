import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/models/library_collection.dart';
import 'package:flow_muse/features/library/widgets/note_bulk_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('零选择禁用操作，选择后移动与标签菜单仍调用原回调', (tester) async {
    String? moved;
    List<String>? tags;
    final now = DateTime(2026, 10, 26);
    final index = LibraryIndex(
      tags: [
        LibraryTag(
          id: 'tag',
          name: '待整理',
          coverColor: Colors.blue,
          createdAt: now,
          updatedAt: now,
          sortOrder: 0,
        ),
      ],
    );
    Widget subject(int count) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: NoteBulkActionBar.active(
            selectedCount: count,
            libraryIndex: index,
            onClearSelection: () {},
            onDeleteSelected: () async {},
            onMoveSelectedToNotebook: (id) async => moved = id ?? 'unfiled',
            onAddTagsToSelected: (value) async => tags = value,
          ),
        ),
      ),
    );
    await tester.pumpWidget(subject(0));
    expect(find.text('选择笔记'), findsOneWidget);
    for (final label in ['移动到', '添加标签', '删除']) {
      final button = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
    }
    await tester.pumpWidget(subject(1));
    await tester.tap(find.text('移动到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未归入笔记本'));
    await tester.pumpAndSettle();
    expect(moved, 'unfiled');
    await tester.tap(find.text('添加标签'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待整理'));
    await tester.pumpAndSettle();
    expect(tags, ['tag']);
    expect(tester.takeException(), isNull);
  });

  for (final trash in [false, true]) {
    testWidgets('${trash ? '回收站' : '资料库'}批量栏在窄屏大字号换行，操作仍可用', (tester) async {
      var cancelled = false;
      var acted = false;
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final bar = trash
          ? NoteBulkActionBar.trash(
              selectedCount: 123,
              onClearSelection: () => cancelled = true,
              onRestoreSelected: () async => acted = true,
              onDeleteSelectedForever: () async {},
            )
          : NoteBulkActionBar.active(
              selectedCount: 123,
              libraryIndex: const LibraryIndex(),
              onClearSelection: () => cancelled = true,
              onDeleteSelected: () async => acted = true,
              onMoveSelectedToNotebook: (_) async {},
              onAddTagsToSelected: (_) async {},
            );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.fromPreset(appThemePresetById(AppThemeId.night)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(alignment: Alignment.topCenter, child: bar),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(trash ? '恢复' : '删除'));
      await tester.tap(find.text('取消'));
      expect(acted, isTrue);
      expect(cancelled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
