import 'dart:typed_data';

import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/widgets/note_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final note = NoteItem(
    id: 'placeholder',
    title: '春日随想',
    updatedAt: DateTime(2026, 10, 23),
    kind: LibraryFilter.notes,
    coverColor: const Color(0xFF8CBDB5),
  );

  for (final invalid in [false, true]) {
    testWidgets('缩略图${invalid ? '损坏' : '缺失'}时显示彩色封面与标题', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 132,
              height: 176,
              child: NoteCover(
                item: invalid
                    ? note.copyWith(
                        coverThumbnailBytes: Uint8List.fromList([0, 1, 2]),
                      )
                    : note,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cover = find.byKey(
        const ValueKey('note-cover-placeholder-placeholder'),
      );
      expect(cover, findsOneWidget);
      expect(
        (tester.widget<DecoratedBox>(cover).decoration as BoxDecoration).color,
        note.coverColor,
      );
      expect(find.text('春日随想'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [0.8, 1.0, 2.0]) {
    testWidgets('$scale倍字号的下拉按钮位于笔记名旁且可从边缘点击', (tester) async {
      var tapped = false;
      var opened = false;
      final item = note.copyWith(title: '长标题的笔记也应完整保持布局与操作');
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 160,
                  height: NoteCard.gridHeight(context),
                  child: NoteCard(
                    item: item,
                    onTap: () => opened = true,
                    onActionsTap: (_) => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final action = find.byKey(
        const ValueKey('note-card-actions-placeholder'),
      );
      expect(tester.getSize(action), const Size(48, 48));
      final actionRect = tester.getRect(action);
      final titleRect = tester.getRect(find.text(item.title).last);
      final coverRect = tester.getRect(
        find.byKey(const ValueKey('note-card-placeholder')),
      );
      expect(actionRect.left, greaterThanOrEqualTo(titleRect.right));
      expect(actionRect.center.dy, closeTo(titleRect.center.dy, 0.01));
      expect(actionRect.top, greaterThanOrEqualTo(coverRect.bottom + 12));
      await tester.tapAt(tester.getCenter(action) + const Offset(20, 0));
      expect(tapped, isTrue);
      expect(opened, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
