import 'package:flow_muse/app/app_theme.dart';
import 'package:flow_muse/app/app_theme_preset.dart';
import 'package:flow_muse/app/view_models/theme_view_model.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/settings/views/settings_page.dart';
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    show CanvasLayoutType;
import 'package:flow_muse/features/whiteboard/models/editor_preferences.dart';
import 'package:flow_muse/features/whiteboard/view_models/editor_preferences_view_model.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flow_muse/shared/widgets/right_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Preferences extends EditorPreferencesViewModel {
  @override
  Future<EditorPreferences> build() async => EditorPreferences();

  @override
  Future<void> setDefaultLayoutType(CanvasLayoutType value) async {
    state = AsyncData(state.value!.copyWith(defaultLayoutType: value));
  }
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

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final (width, scale) in [(360.0, 1.0), (360.0, 2.0), (1280.0, 1.0)]) {
    testWidgets('设置 ${width}px / ${scale}x 分类导航可用且内容不被侧栏挤压', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preset = appThemePresetById(AppThemeId.night);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialThemePresetProvider.overrideWithValue(preset),
            editorPreferencesProvider.overrideWith(_Preferences.new),
            libraryIndexProvider.overrideWith(_Library.new),
            accountViewModelProvider.overrideWith(_Account.new),
            shellLayoutViewModelProvider.overrideWith(_Shell.new),
          ],
          child: MaterialApp(
            theme: AppTheme.fromPreset(preset),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const SettingsPage(initialSection: 'theme'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(RightPageScaffold));
      if (width < shellCompactBreakpoint) {
        expect(rect.width, width);
        await tester.tap(find.byTooltip('设置分类'));
        await tester.pumpAndSettle();
        final document = find
            .ancestor(of: find.text('文档设置'), matching: find.byType(InkWell))
            .last;
        await tester.ensureVisible(document);
        await tester.tap(document);
        await tester.pumpAndSettle();
        expect(find.text('自动保存与新建文档默认值'), findsOneWidget);
        final layout = find.widgetWithText(OutlinedButton, '分页');
        await tester.ensureVisible(layout);
        expect(
          tester.getRect(layout).top,
          greaterThan(tester.getRect(find.text('默认文档类型')).bottom),
        );
        await tester.tap(layout);
        await tester.pumpAndSettle();
        final unbounded = find
            .ancestor(of: find.text('无限画布'), matching: find.byType(InkWell))
            .last;
        await tester.ensureVisible(unbounded);
        await tester.tap(unbounded);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(OutlinedButton, '无限画布'), findsOneWidget);
        await tester.tap(find.byTooltip('设置分类'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('隐私设置'), findsNothing);
        expect(find.widgetWithText(OutlinedButton, '无限画布'), findsOneWidget);
      } else {
        expect(rect.left, greaterThanOrEqualTo(sharedSidebarWidth));
        expect(find.byTooltip('设置分类'), findsNothing);
        await tester.tap(find.text('文档设置'));
        await tester.pumpAndSettle();
        expect(find.text('自动保存与新建文档默认值'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
