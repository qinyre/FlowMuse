import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/models/library_special_view.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/view_models/library_home_view_model.dart';
import 'package:flow_muse/features/library/widgets/library_content.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  for (final mode in LibraryViewMode.values) {
    testWidgets('夜间 ${mode.name} 视图加载完成后显示可用的空态入口', (tester) async {
      final theme = AppTheme.fromPreset(appThemePresetById(AppThemeId.night));
      var created = 0;
      var joined = 0;
      var loading = true;
      var filter = LibraryFilter.all;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return LibraryContent(
                compact: false,
                state: LibraryHomeState(
                  loading: loading,
                  viewMode: mode,
                  selectedFilter: filter,
                ),
                title: '全部笔记',
                notes: const [],
                libraryIndex: const LibraryIndex(),
                specialView: LibrarySpecialView.none,
                onFilterChanged: (value) => update(() => filter = value),
                onViewModeChanged: (_) {},
                onSortDirectionChanged: () {},
                onSelectionModeChanged: () {},
                onSelectionChanged: (_) {},
                onClearSelection: () {},
                onDeleteSelected: () async {},
                onRestoreSelected: () async {},
                onRestoreNote: (_) async {},
                onDeleteNoteForever: (_) async {},
                onDeleteSelectedForever: () async {},
                onMoveSelectedToNotebook: (_) async {},
                onAddTagsToSelected: (_) async {},
                onCreate: () => created++,
                onJoinRoom: () => joined++,
                onOpenNote: (_) {},
              );
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('从第一笔，开始'), findsNothing);
      update(() => loading = false);
      await tester.pumpAndSettle();
      final unselected = tester.widget<Text>(find.text('PDF'));
      expect(unselected.style?.color, theme.colorScheme.onSurfaceVariant);
      expect(find.text('从第一笔，开始'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
      await tester.tap(find.byKey(const ValueKey('join-room-card')));
      expect(created, 1);
      expect(joined, 1);
      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();
      expect(find.text('还没有 PDF 笔记'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  final deletedNote = NoteItem(
    id: 'note-1',
    title: '测试笔记',
    updatedAt: DateTime(2026, 7, 16),
    deletedAt: DateTime(2026, 7, 16),
    kind: LibraryFilter.notes,
    coverColor: Colors.blue,
  );

  testWidgets('回收站菜单可永久删除单条笔记', (tester) async {
    String? deletedNoteId;

    await tester.pumpWidget(
      MaterialApp(
        home: LibraryContent(
          compact: false,
          state: const LibraryHomeState(),
          title: '回收站',
          notes: [deletedNote],
          libraryIndex: const LibraryIndex(),
          specialView: LibrarySpecialView.trash,
          onFilterChanged: (_) {},
          onViewModeChanged: (_) {},
          onSortDirectionChanged: () {},
          onSelectionModeChanged: () {},
          onSelectionChanged: (_) {},
          onClearSelection: () {},
          onDeleteSelected: () async {},
          onRestoreSelected: () async {},
          onRestoreNote: (_) async {},
          onDeleteNoteForever: (noteId) async {
            deletedNoteId = noteId;
          },
          onDeleteSelectedForever: () async {},
          onMoveSelectedToNotebook: (_) async {},
          onAddTagsToSelected: (_) async {},
          onCreate: () {},
          onJoinRoom: () {},
          onOpenNote: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();

    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();

    expect(deletedNoteId, deletedNote.id);
  });
}
