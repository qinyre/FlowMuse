import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/account/views/reset_password_page.dart';
import '../features/account/views/verify_email_page.dart';
import '../features/library/models/library_special_view.dart';
import '../features/library/views/create_note_page.dart';
import '../features/library/views/library_home_page.dart';
import '../features/library/widgets/create_collection_dialog.dart';
import '../features/library/widgets/edit_collection_page.dart';
import '../features/search/views/search_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/notebooks/views/notebooks_page.dart';
import '../features/tags/views/tags_page.dart';
import '../features/whiteboard/collaboration/models/collaboration_room.dart';
import '../features/whiteboard/views/whiteboard_page.dart';
import '../shared/widgets/app_shell.dart';

class AppRoutes {
  const AppRoutes._();

  static const library = '/library';
  static const createNote = '/create-note';
  static const createCollection = '/create-collection';
  static const editCollection = '/edit-collection';
  static const search = '/search';
  static const notebooks = '/notebooks';
  static const notebookDetail = '/notebooks/:notebookId';
  static const tags = '/tags';
  static const tagDetail = '/tags/:tagId';
  static const settings = '/settings';
  static const accountSettings = '/settings?section=account';
  static const verifyEmail = '/auth/verify-email';
  static const resetPassword = '/auth/reset-password';
  static const unnotebooked = '/library/unnotebooked';
  static const untagged = '/library/untagged';
  static const trash = '/library/trash';
  static const whiteboard = '/whiteboard/:noteId';
  static const collaborationWhiteboard = '/whiteboard/collaboration';

  static String notebookPath(String notebookId) {
    return '/notebooks/${Uri.encodeComponent(notebookId)}';
  }

  static String tagPath(String tagId) {
    return '/tags/${Uri.encodeComponent(tagId)}';
  }

  static String whiteboardPath({
    required String noteId,
    bool discardIfUnchanged = true,
  }) {
    final encodedNoteId = Uri.encodeComponent(noteId);
    if (!discardIfUnchanged) {
      return '/whiteboard/$encodedNoteId';
    }
    return '/whiteboard/$encodedNoteId?discardIfUnchanged=true';
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
            path: AppRoutes.unnotebooked,
            pageBuilder: (context, state) {
              return _contentPage(
                state,
                const LibraryHomePage(
                  specialView: LibrarySpecialView.unnotebooked,
                ),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.untagged,
            pageBuilder: (context, state) {
              return _contentPage(
                state,
                const LibraryHomePage(specialView: LibrarySpecialView.untagged),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.trash,
            pageBuilder: (context, state) {
              return _contentPage(
                state,
                const LibraryHomePage(specialView: LibrarySpecialView.trash),
              );
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
              return _detailPage(
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
              return _detailPage(state, TagDetailPage(tagId: tagId));
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.createNote,
        pageBuilder: (context, state) {
          return _modalPage(state, const CreateNotePage());
        },
      ),
      GoRoute(
        path: AppRoutes.createCollection,
        pageBuilder: (context, state) {
          final params = state.extra! as CreateCollectionParams;
          return _modalPage(state, CreateCollectionPage(params: params));
        },
      ),
      GoRoute(
        path: AppRoutes.editCollection,
        pageBuilder: (context, state) {
          final params = state.extra! as EditCollectionParams;
          return _modalPage(state, EditCollectionPage(params: params));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) {
          return _modalPage(state, const SettingsPage());
        },
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        pageBuilder: (context, state) {
          return _standalonePage(
            state,
            VerifyEmailPage(token: state.uri.queryParameters['token'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        pageBuilder: (context, state) {
          return _standalonePage(
            state,
            ResetPasswordPage(token: state.uri.queryParameters['token'] ?? ''),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.collaborationWhiteboard,
        pageBuilder: (context, state) {
          final room = state.extra is CollaborationRoom
              ? state.extra! as CollaborationRoom
              : CollaborationRoom.parse(state.uri.toString()).room;
          return _workspacePage(
            state,
            child: room == null
                ? const WhiteboardPage.collaboration()
                : WhiteboardPage.collaborationRoom(initialRoom: room),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.whiteboard,
        pageBuilder: (context, state) {
          final noteId = state.pathParameters['noteId'] ?? 'note-untitled';
          return _workspacePage(
            state,
            child: WhiteboardPage(
              noteId: noteId,
              discardIfUnchanged:
                  state.uri.queryParameters['discardIfUnchanged'] == 'true',
            ),
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
  if (path == AppRoutes.trash) {
    return ShellSection.trash;
  }
  if (path == AppRoutes.unnotebooked || path == AppRoutes.untagged) {
    return ShellSection.library;
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

Page<void> _contentPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(key: state.pageKey, child: child);
}

Page<void> _detailPage(GoRouterState state, Widget child) {
  return _motionPage(
    state,
    child,
    enterDuration: const Duration(milliseconds: 360),
    exitDuration: const Duration(milliseconds: 280),
    offset: const Offset(0.035, 0),
  );
}

Page<void> _modalPage(GoRouterState state, Widget child) {
  return _motionPage(
    state,
    child,
    enterDuration: const Duration(milliseconds: 380),
    exitDuration: const Duration(milliseconds: 300),
    offset: const Offset(0.035, 0),
  );
}

Page<void> _workspacePage(GoRouterState state, {required Widget child}) {
  return _motionPage(
    state,
    child,
    enterDuration: const Duration(milliseconds: 300),
    exitDuration: const Duration(milliseconds: 240),
    offset: Offset.zero,
  );
}

Page<void> _standalonePage(GoRouterState state, Widget child) {
  return _motionPage(
    state,
    child,
    enterDuration: const Duration(milliseconds: 320),
    exitDuration: const Duration(milliseconds: 260),
    offset: const Offset(0.035, 0),
  );
}

Page<void> _motionPage(
  GoRouterState state,
  Widget child, {
  required Duration enterDuration,
  required Duration exitDuration,
  required Offset offset,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: enterDuration,
    reverseTransitionDuration: exitDuration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return child;
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: offset,
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
