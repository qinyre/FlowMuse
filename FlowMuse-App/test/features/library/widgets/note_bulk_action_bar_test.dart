import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/widgets/note_bulk_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
