import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/views/library_home_page.dart';
import '../features/search/views/search_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/notebooks/views/notebooks_page.dart';
import '../features/tags/views/tags_page.dart';
import '../features/whiteboard/views/whiteboard_page.dart';
import '../shared/widgets/app_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const library = '/library';
  static const search = '/search';
  static const notebooks = '/notebooks';
  static const notebookDetail = '/notebooks/:notebookId';
  static const tags = '/tags';
  static const tagDetail = '/tags/:tagId';
  static const settings = '/settings';
  static const whiteboard = '/whiteboard/:noteId';

  static String notebookPath(String notebookId) {
    return '/notebooks/${Uri.encodeComponent(notebookId)}';
  }

  static String tagPath(String tagId) {
    return '/tags/${Uri.encodeComponent(tagId)}';
  }

  static String whiteboardPath({required String noteId}) {
    return '/whiteboard/${Uri.encodeComponent(noteId)}';
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
            path: AppRoutes.notebooks,
            pageBuilder: (context, state) {
              return _contentPage(state, const NotebooksPage());
            },
          ),
          GoRoute(
            path: AppRoutes.notebookDetail,
            pageBuilder: (context, state) {
              final notebookId = state.pathParameters['notebookId'] ?? '';
              return _contentPage(
                state,
                NotebookDetailPage(notebookId: notebookId),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.tags,
            pageBuilder: (context, state) {
              return _contentPage(state, const TagsPage());
            },
          ),
          GoRoute(
            path: AppRoutes.tagDetail,
            pageBuilder: (context, state) {
              final tagId = state.pathParameters['tagId'] ?? '';
              return _contentPage(state, TagDetailPage(tagId: tagId));
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
          final noteId = state.pathParameters['noteId'] ?? 'note-untitled';
          return MaterialPage<void>(
            key: state.pageKey,
            child: WhiteboardPage(noteId: noteId),
          );
        },
      ),
    ],
  );
}

ShellSection _sectionForPath(String path) {
  if (path == AppRoutes.search) {
    return ShellSection.search;
  }
  if (path == AppRoutes.notebooks ||
      path.startsWith('${AppRoutes.notebooks}/')) {
    return ShellSection.notebooks;
  }
  if (path == AppRoutes.tags || path.startsWith('${AppRoutes.tags}/')) {
    return ShellSection.tags;
  }
  return ShellSection.library;
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
