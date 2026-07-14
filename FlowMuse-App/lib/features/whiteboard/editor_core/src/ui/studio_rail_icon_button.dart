library;

import 'package:flutter/material.dart';

class StudioRailIconButton extends StatelessWidget {
  const StudioRailIconButton({
    super.key,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.emphasized = false,
    this.size = 32,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback onPressed;
  final bool selected;
  final bool emphasized;
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
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: emphasized
                  ? null
                  : selected
                  ? colors.primaryContainer
                  : Colors.transparent,
              gradient: emphasized
                  ? LinearGradient(
                      colors: [
                        colors.primaryContainer,
                        colors.secondaryContainer,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              hoverColor: colors.surfaceContainerHighest,
              focusColor: colors.surfaceContainerHighest,
              highlightColor: colors.surfaceContainerHighest,
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    IconTheme(
                      data: IconThemeData(color: foreground),
                      child: DefaultTextStyle(
                        style: TextStyle(color: foreground),
                        child: child,
                      ),
                    ),
                    if (emphasized)
                      Positioned(
                        bottom: 4,
                        child: Container(
                          width: 14,
                          height: 2,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
