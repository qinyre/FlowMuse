import 'package:flutter/material.dart';

import '../../features/library/widgets/library_sidebar.dart';

enum ShellSection { library, search, folders, settings }

const sharedSidebarWidth = 268.0;

class AppShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withValues(alpha: 0.16),
                colorScheme.primary.withValues(alpha: 0.055),
                colorScheme.surface,
              ],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 820;
              return Row(
                children: [
                  if (showSidebar && !compact) LibrarySidebar(section: section),
                  Expanded(child: child),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
