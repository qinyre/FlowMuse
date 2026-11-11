import 'package:flow_muse/features/guide/view_models/guide_welcome_view_model.dart';
import '../../support/test_local_settings_repository.dart';
import 'package:flow_muse/app/flow_muse_app.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/library/models/note_item.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/library/widgets/library_content.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Account extends AccountViewModel {
  @override
  AccountState build() => const AccountState(status: AccountStatus.guest);
}

class _Shell extends ShellLayoutViewModel {
  @override
  bool build() => false;
  @override
  Future<void> collapseSidebar() async => state = true;
  @override
  Future<void> expandSidebar() async => state = false;
}

class _Index extends LibraryIndexNotifier {
  @override
  Future<LibraryIndex> build() async => LibraryIndex(
    notes: List.generate(
      24,
      (i) => NoteItem(
        id: 'motion-$i',
        title: '合成笔记 $i',
        updatedAt: DateTime(2026, 10, 26).subtract(Duration(minutes: i)),
        kind: LibraryFilter.notes,
        coverColor: Colors.teal,
      ),
    ),
  );
}

Future<ProviderContainer> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        guideSettingsRepositoryProvider.overrideWithValue(
          TestLocalSettingsRepository(),
        ),
        accountViewModelProvider.overrideWith(_Account.new),
        libraryIndexProvider.overrideWith(_Index.new),
        shellLayoutViewModelProvider.overrideWith(_Shell.new),
      ],
      child: FlowMuseApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

void main() {
  testWidgets('侧栏开合不逐帧重建首页内容', (tester) async {
    final container = await _pumpHome(tester);
    var builds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is LibraryContent) builds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await container
        .read(shellLayoutViewModelProvider.notifier)
        .collapseSidebar();
    await tester.pump();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint('[SidebarMotion] contentBuilds=$builds');
    expect(builds, lessThanOrEqualTo(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏换列时笔记经过中间位置，不一帧跨越整行', (tester) async {
    final container = await _pumpHome(tester);
    final card = find.byKey(const ValueKey('note-card-motion-3'));
    var previous = tester.getCenter(card);
    final start = previous;
    var maxVerticalStep = 0.0;
    await container
        .read(shellLayoutViewModelProvider.notifier)
        .collapseSidebar();
    await tester.pump();
    for (var i = 0; i < 36; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final position = tester.getCenter(card);
      final step = (position.dy - previous.dy).abs();
      if (step > maxVerticalStep) maxVerticalStep = step;
      previous = position;
    }
    debugPrint('[SidebarMotion] maxVerticalStep=$maxVerticalStep');
    expect((previous.dy - start.dy).abs(), greaterThan(200));
    expect(maxVerticalStep, lessThan(140));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏仍用抽屉，开合后笔记和侧栏按钮正常', (tester) async {
    await _pumpHome(tester);
    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开侧边栏'));
    await tester.pumpAndSettle();
    final scaffold = tester.state<ScaffoldState>(
      find
          .descendant(
            of: find.byType(AppShell),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(scaffold.isDrawerOpen, isTrue);
    await tester.tap(find.byTooltip('收起侧边栏').hitTestable());
    await tester.pumpAndSettle();
    expect(scaffold.isDrawerOpen, isFalse);
    expect(find.byKey(const ValueKey('note-card-motion-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
