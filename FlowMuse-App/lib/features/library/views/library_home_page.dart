import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../models/notebook_item.dart';
import '../view_models/library_home_view_model.dart';
import '../widgets/library_content.dart';

class LibraryHomePage extends ConsumerWidget {
  const LibraryHomePage({super.key});

  void _openWhiteboard(BuildContext context, {required String notebookId}) {
    context.push(AppRoutes.whiteboardPath(notebookId: notebookId));
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
            final notebook = await viewModel.createNotebook();
            if (context.mounted) {
              _openWhiteboard(context, notebookId: notebook.id);
            }
          },
          onOpenNotebook: (NotebookItem item) {
            _openWhiteboard(context, notebookId: item.id);
          },
        );
      },
    );
  }
}
