library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../markdraw.dart' hide TextAlign;

/// Desktop top toolbar with tool buttons and tool lock.
class DesktopToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onImportImage;

  const DesktopToolbar({
    super.key,
    required this.controller,
    this.onImportImage,
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
              color: cs.shadow.withValues(alpha: 0.17),
              blurRadius: 1,
            ),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
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
                  _ToolButton(
                    type: type,
                    activeType: activeType,
                    colorScheme: cs,
                    onPressed: () => controller.switchTool(type),
                  ),
                ],
              // 压感灵敏度滑块：仅在手写(freedraw)工具激活时显示
              if (showPressureSlider) ...[
                _toolbarDivider(context),
                _BrushSelector(controller: controller),
                _toolbarDivider(context),
                _PressureSensitivitySlider(controller: controller),
              ],
              _toolbarDivider(context),
              _toolbarButton(
                cs: cs,
                icon: Icons.text_fields,
                tooltip: '文字识别模式',
                onPressed: controller.toggleInkRecognitionMode,
                isActive: controller.inkRecognitionMode,
              ),
              _toolbarButton(
                cs: cs,
                icon: Icons.auto_fix_high,
                tooltip: '智能排布模式',
                onPressed: controller.toggleSmartInkLayoutMode,
                isActive: controller.smartInkLayoutMode,
              ),
              _toolbarButton(
                cs: cs,
                icon: Icons.document_scanner_outlined,
                tooltip: '全局识别排版',
                onPressed: () {
                  _runGlobalSmartLayout(context);
                },
              ),
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

  Future<void> _runGlobalSmartLayout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final changed = await controller.runGlobalSmartLayout();
    messenger.showSnackBar(
      SnackBar(content: Text(changed ? '智能排版已应用' : '智能排版失败，场景未修改')),
    );
  }
}

class _BrushSelector extends StatelessWidget {
  const _BrushSelector({required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final brushType in BrushType.values)
          Tooltip(
            message: _labelForBrush(brushType),
            child: Material(
              color: controller.activeBrushType == brushType
                  ? cs.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => controller.activeBrushType = brushType,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: Icon(
                      _iconForBrush(brushType),
                      size: 19,
                      color: controller.activeBrushType == brushType
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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

String _labelForBrush(BrushType brushType) {
  return switch (brushType) {
    BrushType.pencil => '铅笔',
    BrushType.ballpoint => '圆珠笔',
    BrushType.fountainPen => '钢笔',
    BrushType.brushPen => '毛笔',
    BrushType.highlighter => '荧光笔',
  };
}

IconData _iconForBrush(BrushType brushType) {
  return switch (brushType) {
    BrushType.pencil => Icons.edit_outlined,
    BrushType.ballpoint => Icons.mode_edit_outline,
    BrushType.fountainPen => Icons.draw,
    BrushType.brushPen => Icons.brush,
    BrushType.highlighter => Symbols.ink_highlighter,
  };
}
