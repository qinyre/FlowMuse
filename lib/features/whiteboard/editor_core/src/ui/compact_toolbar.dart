library;

import 'package:flutter/material.dart';

import '../../markdraw.dart' hide TextAlign;

/// Compact bottom toolbar for mobile layout.
class CompactToolbar extends StatelessWidget {
  final MarkdrawController controller;

  const CompactToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    return FocusTraversalGroup(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.17),
              blurRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _compactButton(
                cs: cs,
                icon: Icons.undo,
                tooltip: 'Undo',
                onPressed: controller.undo,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.redo,
                tooltip: 'Redo',
                onPressed: controller.redo,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 20,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              for (final type in ToolType.values)
                if (type != ToolType.frame)
                  _compactButton(
                    cs: cs,
                    iconWidget: iconWidgetFor(
                      type,
                      color: activeType == type
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      size: 22,
                      isActive: activeType == type,
                    ),
                    tooltip: type.name,
                    onPressed: () => controller.switchTool(type),
                    isActive: activeType == type,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactButton({
    required ColorScheme cs,
    IconData? icon,
    Widget? iconWidget,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child:
                    iconWidget ??
                    Icon(
                      icon,
                      size: 22,
                      color: isActive ? cs.primary : cs.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
