import 'package:flutter/material.dart';

import '../../features/library/widgets/library_sidebar.dart';

enum ShellSection { library, search, folders, settings }

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
    return Scaffold(
      body: SafeArea(
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
    );
  }
}
