library;

import 'package:flutter/material.dart';

class StudioRailIconButton extends StatelessWidget {
  const StudioRailIconButton({
    super.key,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.size = 32,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: colors.surfaceContainerHighest,
            focusColor: colors.surfaceContainerHighest,
            highlightColor: colors.surfaceContainerHighest,
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: foreground),
                  child: DefaultTextStyle(
                    style: TextStyle(color: foreground),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
