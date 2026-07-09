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
    final showPressureSlider = activeType == ToolType.freedraw;
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
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
                  _toolbarButton(
                    cs: cs,
                    iconWidget: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        iconWidgetFor(
                          type,
                          color: activeType == type
                              ? cs.primary
                              : cs.onSurfaceVariant,
                          size: 20,
                          isActive: activeType == type,
                        ),
                        if (shortcutForToolType(type) != null)
                          Positioned(
                            right: -6,
                            bottom: -3,
                            child: Text(
                              shortcutForToolType(type)!,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: activeType == type
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    tooltip:
                        '${labelForToolType(type)} (${shortcutForToolType(type)})',
                    onPressed: () => controller.switchTool(type),
                    isActive: activeType == type,
                  ),
                ],
              // 压感灵敏度滑块：仅在手写(freedraw)工具激活时显示
              if (showPressureSlider) ...[
                _toolbarDivider(context),
                _PressureSensitivitySlider(controller: controller),
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

/// 压感灵敏度滑块：仅在手写工具激活时显示。
///
/// 控制压力对线条粗细的影响：左边=均匀粗细, 右边=压感最大影响。
class _PressureSensitivitySlider extends StatelessWidget {
  final MarkdrawController controller;
  const _PressureSensitivitySlider({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final value = controller.pressureSensitivity;
        final label = _sensitivityLabel(value);
        return Tooltip(
          message: '压感强度: $label',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 80,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    activeTrackColor: Theme.of(context).colorScheme.primary,
                    inactiveTrackColor: Theme.of(
                      context,
                    ).colorScheme.outlineVariant,
                  ),
                  child: Slider(
                    value: value,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      controller.pressureSensitivity = v;
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _sensitivityLabel(double value) {
    if (value <= 0.15) return '均匀';
    if (value <= 0.4) return '弱';
    if (value <= 0.65) return '中';
    if (value <= 0.85) return '强';
    return '极强';
  }
}
