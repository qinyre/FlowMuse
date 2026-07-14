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
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: const Icon(Icons.help_outline, size: 18),
        onPressed: () => showHelpDialog(context),
        tooltip: '帮助 (?)',
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        iconSize: 18,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          hoverColor: cs.surfaceContainerHighest,
          focusColor: cs.surfaceContainerHighest,
        ),
      ),
    );
  }
}
