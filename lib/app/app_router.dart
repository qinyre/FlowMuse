import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/views/library_home_page.dart';
import '../features/search/views/search_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/folders/views/folders_page.dart';
import '../features/whiteboard/views/whiteboard_page.dart';
import '../shared/widgets/app_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const library = '/library';
  static const search = '/search';
  static const folders = '/folders';
  static const settings = '/settings';
  static const whiteboard = '/whiteboard/:title';

  static String whiteboardPath(String title) {
    return '/whiteboard/${Uri.encodeComponent(title)}';
  }
}

GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.library,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(
            section: _sectionForPath(state.uri.path),
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: AppRoutes.library,
            pageBuilder: (context, state) {
              return _contentPage(state, const LibraryHomePage());
            },
          ),
          GoRoute(
            path: AppRoutes.search,
            pageBuilder: (context, state) {
              return _contentPage(state, const SearchPage());
            },
          ),
          GoRoute(
            path: AppRoutes.folders,
            pageBuilder: (context, state) {
              return _contentPage(state, const FoldersPage());
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: AppRoutes.whiteboard,
        pageBuilder: (context, state) {
          final title = state.pathParameters['title'] ?? '未命名白板';
          return MaterialPage<void>(
            key: state.pageKey,
            child: WhiteboardPage(title: title),
          );
        },
      ),
    ],
  );
}

ShellSection _sectionForPath(String path) {
  return switch (path) {
    AppRoutes.search => ShellSection.search,
    AppRoutes.folders => ShellSection.folders,
    _ => ShellSection.library,
  };
}

CustomTransitionPage<void> _contentPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}
