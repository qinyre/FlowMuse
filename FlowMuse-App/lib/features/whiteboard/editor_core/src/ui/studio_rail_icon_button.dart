library;

import 'package:flutter/material.dart';
import 'hover_tooltip.dart';
import 'toolbar_input_diagnostics.dart';

class StudioRailIconButton extends StatelessWidget {
  const StudioRailIconButton({
    super.key,
    required this.tooltip,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.emphasized = false,
    this.size = 32,
    this.useFlatBackground = false,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final bool emphasized;
  final double size;
  final bool useFlatBackground;

  static const _diagnosticControlId = 'studio_rail_icon_button';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    final callback = onPressed;
    return Semantics(
      label: tooltip,
      button: true,
      enabled: callback != null,
      child: ToolbarInputDiagnosticsTarget(
        controlId: _diagnosticControlId,
        child: HoverTooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                color: emphasized
                    ? (useFlatBackground ? colors.primaryContainer : null)
                    : selected
                    ? colors.primaryContainer
                    : Colors.transparent,
                gradient: emphasized && !useFlatBackground
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
                onTapDown: callback == null
                    ? null
                    : (_) => ToolbarInputDiagnostics.recordTap(
                        controlId: _diagnosticControlId,
                        stage: 'tapDown',
                      ),
                onTapUp: callback == null
                    ? null
                    : (_) => ToolbarInputDiagnostics.recordTap(
                        controlId: _diagnosticControlId,
                        stage: 'tapUp',
                      ),
                onTapCancel: callback == null
                    ? null
                    : () => ToolbarInputDiagnostics.recordTap(
                        controlId: _diagnosticControlId,
                        stage: 'tapCancel',
                      ),
                onTap: callback == null
                    ? null
                    : () {
                        ToolbarInputDiagnostics.recordTap(
                          controlId: _diagnosticControlId,
                          stage: 'tap',
                        );
                        callback();
                      },
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
      ),
    );
  }
}
