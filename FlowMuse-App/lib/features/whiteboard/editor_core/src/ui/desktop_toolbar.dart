library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../markdraw.dart' hide TextAlign;

/// Desktop top toolbar with tool buttons and tool lock.
class DesktopToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onImportImage;
  final bool showMarkdownButton;

  const DesktopToolbar({
    super.key,
    required this.controller,
    this.onImportImage,
    this.showMarkdownButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    return FocusTraversalGroup(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _toolbarButton(
              cs: cs,
              icon: controller.toolLocked ? Icons.lock : Icons.lock_open,
              tooltip: '保持工具激活 (Q)',
              onPressed: controller.toggleToolLocked,
              isActive: controller.toolLocked,
            ),
            _toolbarDivider(context),
            for (final type in ToolType.values)
              if (type != ToolType.frame) ...[
                if (type == ToolType.eraser && onImportImage != null)
                  _toolbarButton(
                    cs: cs,
                    iconWidget: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.add_photo_alternate,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        Positioned(
                          right: -6,
                          bottom: -3,
                          child: Text(
                            '9',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    tooltip: '导入图片 (9)',
                    onPressed: onImportImage!,
                  ),
                _ToolButton(
                  type: type,
                  activeType: activeType,
                  colorScheme: cs,
                  onPressed: () => controller.switchTool(type),
                ),
              ],
            if (showMarkdownButton) ...[
              _toolbarDivider(context),
              _toolbarButton(
                cs: cs,
                icon: Symbols.markdown,
                tooltip: 'Markdown 面板',
                onPressed: controller.toggleMarkdownPanel,
                isActive: controller.showMarkdownPanel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
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
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child:
                    iconWidget ??
                    Icon(
                      icon,
                      size: 20,
                      color: isActive ? cs.primary : cs.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbarDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 20,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).dividerColor,
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.type,
    required this.activeType,
    required this.colorScheme,
    required this.onPressed,
  });

  final ToolType type;
  final ToolType activeType;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final shortcut = shortcutForToolType(type);
    final label = labelForToolType(type);
    final active = activeType == type;
    final tooltip = shortcut == null ? label : '$label ($shortcut)';
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    iconWidgetFor(
                      type,
                      color: active
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      size: 20,
                      isActive: active,
                    ),
                    if (shortcut != null)
                      Positioned(
                        right: -6,
                        bottom: -3,
                        child: Text(
                          shortcut,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: active
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
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
