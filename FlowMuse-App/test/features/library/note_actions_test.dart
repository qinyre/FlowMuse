import 'package:flow_muse/features/library/models/library_collection.dart';
import 'package:flow_muse/features/library/models/library_index.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/widgets/note_actions.dart';
import 'package:flow_muse/features/library/widgets/note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  testWidgets('note card actions button stays tappable in grid card', (
    WidgetTester tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: NoteCard.coverWidth,
              child: NoteCard(
                item: _noteItem(),
                onTap: () {},
                onActionsTap: () => tapped++,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final buttonFinder = find.byKey(const ValueKey('note-card-actions-note-1'));
    final buttonCenter = tester.getCenter(buttonFinder);

    await tester.tapAt(buttonCenter + const Offset(10, 0));
    await tester.pump();

    expect(tapped, 1);
  });

  testWidgets('selecting a tag clears untagged automatically', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryIndexProvider.overrideWith(
            () => _FakeLibraryIndexNotifier(
              LibraryIndex(
                tags: [
                  LibraryTag(
                    id: 'tag-1',
                    name: 'Work',
                    coverColor: Color(0xFF8CBDB5),
                    createdAt: _now,
                    updatedAt: _now,
                    sortOrder: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SelectTagsDialog(currentTagIds: []),
          ),
        ),
      ),
    );
    await tester.pump();

    final checkboxTiles = find.byType(CheckboxListTile);
    expect(checkboxTiles, findsNWidgets(2));
    expect(tester.widget<CheckboxListTile>(checkboxTiles.at(0)).value, true);
    expect(tester.widget<CheckboxListTile>(checkboxTiles.at(1)).onChanged, isNotNull);

    await tester.tap(find.text('Work'));
    await tester.pump();

    expect(tester.widget<CheckboxListTile>(checkboxTiles.at(0)).value, false);
    expect(tester.widget<CheckboxListTile>(checkboxTiles.at(1)).value, true);
  });
}

class _FakeLibraryIndexNotifier extends LibraryIndexNotifier {
  _FakeLibraryIndexNotifier(this.value);

  final LibraryIndex value;

  @override
  Future<LibraryIndex> build() async => value;
}

final _now = DateTime(2026, 7, 11);

NoteItem _noteItem() {
  return NoteItem(
    id: 'note-1',
    title: 'Test note',
    updatedAt: _now,
    kind: LibraryFilter.notes,
    coverColor: Color(0xFF8DB6C9),
  );
}
