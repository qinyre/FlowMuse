import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/library/views/library_home_page.dart';
import '../features/search/views/search_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/folders/views/folders_page.dart';
import '../features/tags/views/tags_page.dart';
import '../features/whiteboard/views/whiteboard_page.dart';
import '../shared/widgets/app_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const library = '/library';
  static const search = '/search';
  static const folders = '/folders';
  static const folderDetail = '/folders/:folderId';
  static const tags = '/tags';
  static const tagDetail = '/tags/:tagId';
  static const settings = '/settings';
  static const whiteboard = '/whiteboard/:notebookId';

  static String folderPath(String folderId) {
    return '/folders/${Uri.encodeComponent(folderId)}';
  }

  static String tagPath(String tagId) {
    return '/tags/${Uri.encodeComponent(tagId)}';
  }

  static String whiteboardPath({required String notebookId}) {
    return '/whiteboard/${Uri.encodeComponent(notebookId)}';
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
          GoRoute(
            path: AppRoutes.folderDetail,
            pageBuilder: (context, state) {
              final folderId = state.pathParameters['folderId'] ?? '';
              return _contentPage(state, FolderDetailPage(folderId: folderId));
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
          final notebookId =
              state.pathParameters['notebookId'] ?? 'whiteboard-untitled';
          return MaterialPage<void>(
            key: state.pageKey,
            child: WhiteboardPage(notebookId: notebookId),
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
  if (path == AppRoutes.folders || path.startsWith('${AppRoutes.folders}/')) {
    return ShellSection.folders;
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
