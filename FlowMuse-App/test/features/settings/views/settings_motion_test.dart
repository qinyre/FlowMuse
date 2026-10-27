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

Future<void> _pumpSettings(
  WidgetTester tester, {
  double scale = 1,
  bool reduced = false,
  ValueNotifier<bool>? reducedMotion,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
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
        builder: (context, child) {
          Widget media(bool disabled) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: disabled,
            ),
            child: child!,
          );
          return reducedMotion == null
              ? media(reduced)
              : ValueListenableBuilder<bool>(
                  valueListenable: reducedMotion,
                  builder: (context, value, _) => media(value),
                );
        },
        home: const SettingsPage(initialSection: 'theme'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _nav(String label) => find.byWidgetPredicate(
  (widget) => widget is SharedSidebarItem && widget.label == label,
);

List<String?> _titles(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(RightPageHeader),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

State<StatefulWidget> _bodyState(WidgetTester tester) {
  final list = find
      .descendant(
        of: find.byType(RightPageScaffold),
        matching: find.byType(ListView),
      )
      .first;
  State<StatefulWidget>? result;
  tester.element(list).visitAncestorElements((element) {
    if (element is StatefulElement && element.state is ConsumerState) {
      result = element.state;
      return false;
    }
    return true;
  });
  return result!;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('设置侧栏标题在 $scale 倍字号下居中，返回按钮独立对齐', (tester) async {
      await _pumpSettings(tester, scale: scale);
      expect(
        tester.getCenter(find.text('设置')).dx,
        closeTo(sharedSidebarWidth / 2, 0.5),
      );
      expect(
        tester.getCenter(find.byTooltip('返回')).dx,
        lessThan(sharedSidebarWidth / 3),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('分类先退出再进入，整页保持一个标题且有淡入淡出', (tester) async {
    await _pumpSettings(tester);
    final body = _bodyState(tester);
    await tester.tap(_nav('文档设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_titles(tester), ['主题设置']);
    final fade = find
        .ancestor(
          of: find.byType(RightPageScaffold),
          matching: find.byType(FadeTransition),
        )
        .first;
    final outgoingOpacity = tester.widget<FadeTransition>(fade).opacity.value;
    expect(outgoingOpacity, allOf(greaterThan(0), lessThan(1)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(_titles(tester), ['文档设置']);
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(_bodyState(tester), same(body));
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速切换只落到最新分类，标题不堆叠，设置状态不销毁', (tester) async {
    await _pumpSettings(tester);
    final body = _bodyState(tester);
    for (final label in ['文档设置', '手写笔设置', '手势设置', '隐私设置']) {
      await tester.tap(_nav(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(_titles(tester), hasLength(1));
      expect(body.mounted, isTrue);
    }
    await tester.pumpAndSettle();
    expect(_titles(tester), ['隐私设置']);
    expect(_bodyState(tester), same(body));
    expect(find.text('自动保存与新建文档默认值'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('离场未完成即回到原分类，取消切换并保留状态', (tester) async {
    await _pumpSettings(tester);
    final body = _bodyState(tester);
    await tester.tap(_nav('文档设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(_nav('主题设置'));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['主题设置']);
    expect(_bodyState(tester), same(body));
    expect(tester.takeException(), isNull);
  });

  testWidgets('入场途中重新选择分类，也只保留最新标题', (tester) async {
    await _pumpSettings(tester);
    await tester.tap(_nav('文档设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(_titles(tester), ['文档设置']);
    await tester.tap(_nav('隐私设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(_titles(tester), hasLength(1));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['隐私设置']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('过渡中开启减少动画立即落到最新分类', (tester) async {
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await _pumpSettings(tester, reducedMotion: reduced);
    await tester.tap(_nav('文档设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    reduced.value = true;
    await tester.pump();
    expect(_titles(tester), ['文档设置']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画时分类立即替换，切换途中关闭不遗留 ticker', (tester) async {
    await _pumpSettings(tester, reduced: true);
    await tester.tap(_nav('文档设置'));
    await tester.pump();
    expect(_titles(tester), ['文档设置']);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _pumpSettings(tester);
    await tester.tap(_nav('隐私设置'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
