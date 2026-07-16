import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/widgets/collection_note_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final note = NoteItem(
    id: 'note-1',
    title: '测试笔记',
    updatedAt: DateTime(2026, 7, 16),
    kind: LibraryFilter.notes,
    coverColor: Colors.blue,
  );

  Widget buildSubject() {
    return MaterialApp(
      home: CollectionNoteContent(
        title: '测试集合',
        libraryIndex: const LibraryIndex(),
        notes: [note],
        onBack: () {},
        onCreate: () {},
        onOpenNote: (_) {},
        onRenameNote: (_, _) async {},
        onMoveNotesToNotebook: (_, _) async {},
        onSetNoteTags: (_, _) async {},
        onAddTagsToNotes: (_, _) async {},
        onDeleteNotes: (_) async {},
      ),
    );
  }

  testWidgets('支持切换列表视图并多选集合内笔记', (tester) async {
    await tester.pumpWidget(buildSubject());

    expect(find.byKey(const ValueKey('note-card-note-1')), findsOneWidget);

    await tester.tap(find.byTooltip('网格视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表视图'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsWidgets);

    await tester.tap(find.byTooltip('多选'));
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);

    await tester.tap(find.text('测试笔记'));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
  });
}
