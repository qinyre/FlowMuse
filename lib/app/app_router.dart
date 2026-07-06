import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/views/library_home_page.dart';
import '../features/search/views/search_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/folders/views/folders_page.dart';
import '../features/whiteboard/views/whiteboard_page.dart';

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
      GoRoute(
        path: AppRoutes.library,
        builder: (context, state) => const LibraryHomePage(),
      ),
      GoRoute(
        path: AppRoutes.search,
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: AppRoutes.folders,
        builder: (context, state) => const FoldersPage(),
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
