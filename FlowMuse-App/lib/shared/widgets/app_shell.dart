import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_theme_preset.dart';
import '../../app/view_models/theme_view_model.dart';
import '../../features/library/widgets/library_sidebar.dart';
import '../storage/local_settings_repository.dart';

enum ShellSection { library, search, notebooks, tags, trash, settings }

const sharedSidebarWidth = 268.0;
const shellCompactBreakpoint = 820.0;

class ShellLayoutViewModel extends Notifier<bool> {
  static const _sidebarCollapsedKey = 'shell_sidebar_collapsed';

  @override
  bool build() {
    _restore();
    return false;
  }

  Future<void> _restore() async {
    state =
        await defaultLocalSettingsRepository.readBool(_sidebarCollapsedKey) ??
        false;
  }

  Future<void> collapseSidebar() {
    return _setSidebarCollapsed(true);
  }

  Future<void> expandSidebar() {
    return _setSidebarCollapsed(false);
  }

  Future<void> _setSidebarCollapsed(bool collapsed) async {
    state = collapsed;
    await defaultLocalSettingsRepository.writeBool(
      _sidebarCollapsedKey,
      collapsed,
    );
  }
}

final shellLayoutViewModelProvider =
    NotifierProvider<ShellLayoutViewModel, bool>(ShellLayoutViewModel.new);

class AppShellChrome {
  const AppShellChrome({
    required this.compact,
    required this.sidebarCollapsed,
    required this.showSidebarControls,
    required this.openSidebar,
    required this.collapseSidebar,
  });

  final bool compact;
  final bool sidebarCollapsed;
  final bool showSidebarControls;
  final VoidCallback openSidebar;
  final VoidCallback collapseSidebar;

  bool get contentFullWidth => compact || sidebarCollapsed;
}

class AppShellScope extends InheritedWidget {
  const AppShellScope({super.key, required this.chrome, required super.child});

  final AppShellChrome chrome;

  static AppShellChrome? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShellScope>()?.chrome;
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) {
    return oldWidget.chrome.compact != chrome.compact ||
        oldWidget.chrome.sidebarCollapsed != chrome.sidebarCollapsed ||
        oldWidget.chrome.showSidebarControls != chrome.showSidebarControls;
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.child,
    this.showSidebar = true,
  });

  final ShellSection section;
  final Widget child;
  final bool showSidebar;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final themePreset = ref.watch(themeViewModelProvider);
    final sidebarCollapsed = ref.watch(shellLayoutViewModelProvider);
    final layoutViewModel = ref.read(shellLayoutViewModelProvider.notifier);
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectivePreset = effectiveAppThemePreset(
      themePreset,
      platformBrightness,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: widget.showSidebar
          ? Drawer(
              width: sharedSidebarWidth,
              child: SafeArea(
                child: LibrarySidebar(
                  section: widget.section,
                  onCollapse: () => Navigator.of(context).pop(),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: effectivePreset.usesMonochromeBackground
                ? effectivePreset.backgroundEnd
                : null,
            gradient: effectivePreset.usesMonochromeBackground
                ? null
                : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                effectivePreset.backgroundStart,
                effectivePreset.backgroundMiddle,
                effectivePreset.backgroundEnd,
              ],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < shellCompactBreakpoint;
              final showDockedSidebar =
                  widget.showSidebar && !compact && !sidebarCollapsed;
              final chrome = AppShellChrome(
                compact: compact,
                sidebarCollapsed: sidebarCollapsed,
                showSidebarControls:
                    widget.showSidebar && (compact || sidebarCollapsed),
                openSidebar: () {
                  if (compact) {
                    _scaffoldKey.currentState?.openDrawer();
                    return;
                  }
                  layoutViewModel.expandSidebar();
                },
                collapseSidebar: layoutViewModel.collapseSidebar,
              );

              return AppShellScope(
                chrome: chrome,
                child: Row(
                  children: [
                    ClipRect(
                      child: AnimatedContainer(
                        width: showDockedSidebar ? sharedSidebarWidth : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: showDockedSidebar ? 1 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: sharedSidebarWidth,
                            maxWidth: sharedSidebarWidth,
                            child: IgnorePointer(
                              ignoring: !showDockedSidebar,
                              child: LibrarySidebar(
                                section: widget.section,
                                onCollapse: layoutViewModel.collapseSidebar,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
