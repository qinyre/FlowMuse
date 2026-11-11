import 'package:flow_muse/features/guide/view_models/guide_welcome_view_model.dart';
import 'support/test_local_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/view_models/library_home_view_model.dart';
import 'package:flow_muse/features/library/widgets/note_card.dart';

import 'support/test_library_index_notifier.dart';

Widget _testApp({AppThemePreset? initialPreset}) {
  return ProviderScope(
    overrides: [
      guideSettingsRepositoryProvider.overrideWithValue(
        TestLocalSettingsRepository(),
      ),
      libraryIndexProvider.overrideWith(TestLibraryIndexNotifier.new),
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
    await tester.pump();
    await tester.pump();

    expect(find.text('全部笔记'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is NoteCard && widget.item.title == '操作系统',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is NoteCard && widget.item.title == 'LectureNotes',
      ),
      findsOneWidget,
    );
  });

  testWidgets('filters PDF notebooks through the library view model', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    final cards = tester.widgetList<NoteCard>(find.byType(NoteCard));
    expect(cards.map((card) => card.item.title), ['LectureNotes']);
    final container = ProviderScope.containerOf(
      tester.element(find.text('全部笔记').first),
    );
    expect(
      container.read(libraryHomeViewModelProvider).selectedFilter.name,
      'pdf',
    );
  });

  testWidgets('opens the note setup route from the create card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('create-notebook-card')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('新建笔记'), findsOneWidget);
  });

  testWidgets('applies the selected theme to the library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(initialPreset: appThemePresetById(AppThemeId.night)),
    );
    await tester.pump();
    await tester.pump();

    expect(
      Theme.of(tester.element(find.text('全部笔记').first)).scaffoldBackgroundColor,
      isNot(AppTheme.fromPreset(defaultThemePreset).scaffoldBackgroundColor),
    );
  });

  testWidgets('opens search from navigation', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(initialPreset: appThemePresetById(AppThemeId.starryBlue)),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('搜索').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('请输入关键字搜索笔记'), findsOneWidget);
  });
}
