import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../models/note_item.dart';
import '../view_models/library_home_view_model.dart';
import '../widgets/library_content.dart';

class LibraryHomePage extends ConsumerWidget {
  const LibraryHomePage({super.key});

  void _openWhiteboard(BuildContext context, {required String noteId}) {
    context.push(AppRoutes.whiteboardPath(noteId: noteId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryHomeViewModelProvider);
    final viewModel = ref.read(libraryHomeViewModelProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return LibraryContent(
          compact: compact,
          state: state,
          onFilterChanged: viewModel.selectFilter,
          onViewModeChanged: viewModel.changeViewMode,
          onSortDirectionChanged: viewModel.toggleSortDirection,
          onSelectionModeChanged: viewModel.toggleSelectionMode,
          onCreate: () async {
            final note = await viewModel.createNote();
            if (context.mounted) {
              _openWhiteboard(context, noteId: note.id);
            }
          },
          onOpenNote: (NoteItem item) {
            _openWhiteboard(context, noteId: item.id);
          },
        );
      },
    );
  }
}
