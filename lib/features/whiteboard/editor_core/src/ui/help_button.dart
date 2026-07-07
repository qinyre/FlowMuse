library;

import 'package:flutter/material.dart';

import 'help_dialog.dart';

/// Help button (bottom-right on desktop).
class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.help_outline, size: 18),
        onPressed: () => showHelpDialog(context),
        tooltip: 'Help (?)',
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        iconSize: 18,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
