import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/models/library_special_view.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/view_models/library_home_view_model.dart';
import 'package:flow_muse/features/library/widgets/library_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
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
