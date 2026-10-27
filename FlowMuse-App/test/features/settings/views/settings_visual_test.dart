import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/settings/views/settings_page.dart';
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flow_muse/features/whiteboard/view_models/editor_preferences_view_model.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flow_muse/shared/widgets/right_page.dart';
import 'package:flow_muse/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends EditorPreferencesViewModel {
  @override
  Future<EditorPreferences> build() async => EditorPreferences();
}

class _Library extends LibraryIndexNotifier {
  @override
  Future<LibraryIndex> build() async => const LibraryIndex();
}

class _Account extends AccountViewModel {
  @override
  AccountState build() => const AccountState(status: AccountStatus.guest);
}

class _Shell extends ShellLayoutViewModel {
  @override
  bool build() => false;
}

class _Theme extends ThemeViewModel {
  @override
  Future<void> changePreset(AppThemePreset preset) async => state = preset;
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
  double scale = 1,
  AppThemeId themeId = AppThemeId.day,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialThemePresetProvider.overrideWithValue(
          appThemePresetById(themeId),
        ),
        themeViewModelProvider.overrideWith(_Theme.new),
        editorPreferencesProvider.overrideWith(_Preferences.new),
        libraryIndexProvider.overrideWith(_Library.new),
        accountViewModelProvider.overrideWith(_Account.new),
        shellLayoutViewModelProvider.overrideWith(_Shell.new),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: AppTheme.fromPreset(ref.watch(themeViewModelProvider)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const SettingsPage(initialSection: 'theme'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _bodyList() => find.descendant(
  of: find.byType(RightPageScaffold),
  matching: find.byType(ListView),
);

void main() {
  testWidgets('六张主题卡支持点击和键盘选择，并反馈选中状态', (tester) async {
    await _pump(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    for (final preset in appThemePresets) {
      expect(find.text(preset.label), findsOneWidget);
    }
    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(container.read(themeViewModelProvider).id, AppThemeId.night);
    final selected = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == '夜间',
      ),
    );
    expect(selected.properties.selected, isTrue);
    Focus.of(tester.element(find.text('日间'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(themeViewModelProvider).id, AppThemeId.day);
    expect(tester.takeException(), isNull);
  });

  for (final themeId in [AppThemeId.day, AppThemeId.night]) {
    testWidgets('${themeId.name} 窄屏双倍字号主题预览可完整滚动且不溢出', (tester) async {
      await _pump(
        tester,
        size: const Size(360, 800),
        scale: 2,
        themeId: themeId,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('绿霞'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.text('绿霞'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('窄屏同排主题卡在说明换行时仍然等高', (tester) async {
    await _pump(tester, size: const Size(600, 900));
    final heights = [
      for (final label in ['日间', '夜间', '系统'])
        tester
            .getSize(
              find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == label,
              ),
            )
            .height,
    ];
    expect(
      heights.every((height) => (height - heights.first).abs() < 0.01),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('滚动主题后切换分类回到顶部，长设置页仍可继续滚动', (tester) async {
    await _pump(tester, size: const Size(1280, 420));
    await tester.drag(_bodyList(), const Offset(0, -600));
    await tester.pumpAndSettle();
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(of: _bodyList(), matching: find.byType(Scrollable))
              .first,
        )
        .position;
    expect(position().pixels, greaterThan(0));
    final tools = find.byWidgetPredicate(
      (w) => w is SharedSidebarItem && w.label == '工具设置',
    );
    await tester.scrollUntilVisible(
      tools,
      100,
      scrollable: find
          .descendant(
            of: find.byType(SharedSidebar),
            matching: find.byType(Scrollable),
          )
          .hitTestable(),
    );
    await tester.tap(tools);
    await tester.pumpAndSettle();
    expect(position().maxScrollExtent, greaterThan(0));
    expect(position().pixels, 0);
    expect(find.text('默认工具与每种笔形的颜色、粗细'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
