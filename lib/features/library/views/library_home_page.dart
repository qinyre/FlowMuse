import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../models/notebook_item.dart';
import '../view_models/library_home_view_model.dart';
import '../widgets/library_content.dart';
import '../widgets/library_sidebar.dart';

class LibraryHomePage extends ConsumerWidget {
  const LibraryHomePage({super.key});

  void _openWhiteboard(BuildContext context, {String title = '未命名白板'}) {
    context.push(AppRoutes.whiteboardPath(title));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryHomeViewModelProvider);
    final viewModel = ref.read(libraryHomeViewModelProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 820;
            return Row(
              children: [
                if (!compact) const LibrarySidebar(),
                Expanded(
                  child: LibraryContent(
                    compact: compact,
                    state: state,
                    onFilterChanged: viewModel.selectFilter,
                    onCreate: () => _openWhiteboard(context),
                    onOpenNotebook: (NotebookItem item) {
                      _openWhiteboard(context, title: item.title);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
