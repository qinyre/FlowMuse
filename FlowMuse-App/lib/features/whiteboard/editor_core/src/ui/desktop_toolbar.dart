library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';

/// Desktop top toolbar with tool buttons and tool lock.
class DesktopToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onImportImage;
  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;
  final VoidCallback? onCollapse;

  const DesktopToolbar({
    super.key,
    required this.controller,
    this.onImportImage,
    this.dock = ToolbarDock.top,
    this.onDockChanged,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    final showPressureSlider = activeType == ToolType.freedraw;
    final vertical = dock != ToolbarDock.top;
    return FocusTraversalGroup(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.surfaceContainerLow, cs.surface],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(color: cs.shadow.withValues(alpha: 0.17), blurRadius: 1),
            BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 3),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
          child: Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
                    _toolbarButton(
                      cs: cs,
                      icon: controller.toolLocked
                          ? Icons.lock
                          : Icons.lock_open,
                      tooltip: '保持工具激活 (Q)',
                      onPressed: controller.toggleToolLocked,
                      isActive: controller.toolLocked,
                    ),
                    _toolbarDivider(context, vertical),
                    _ToolButton(
                      type: ToolType.hand,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.hand),
                    ),
                    _ToolButton(
                      type: ToolType.select,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.select),
                    ),
                    _BrushMenuButton(controller: controller),
                    _ShapeMenuButton(
                      controller: controller,
                      activeType: activeType,
                      colorScheme: cs,
                    ),
                    _ToolButton(
                      type: ToolType.freedraw,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.freedraw),
                    ),
                    _ToolButton(
                      type: ToolType.text,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.text),
                    ),
                    if (onImportImage != null)
                      _toolbarButton(
                        cs: cs,
                        icon: Icons.add_photo_alternate,
                        tooltip: '导入图片 (9)',
                        onPressed: onImportImage!,
                      ),
                    _ToolButton(
                      type: ToolType.eraser,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.eraser),
                    ),
                    _ToolButton(
                      type: ToolType.laser,
                      activeType: activeType,
                      colorScheme: cs,
                      onPressed: () => controller.switchTool(ToolType.laser),
                    ),
                    // 压感灵敏度滑块：仅在手写(freedraw)工具激活时显示
                    if (showPressureSlider) ...[
                      _toolbarDivider(context, vertical),
                      _PressureSensitivitySlider(controller: controller),
                    ],
                    _toolbarDivider(context, vertical),
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
                    _toolbarDivider(context, vertical),
                    _DockMenuButton(
                      dock: dock,
                      onDockChanged: onDockChanged,
                    ),
                    if (onCollapse != null)
                      _toolbarButton(
                        cs: cs,
                        icon: switch (dock) {
                          ToolbarDock.top => Icons.keyboard_arrow_up,
                          ToolbarDock.left => Icons.keyboard_arrow_left,
                          ToolbarDock.right => Icons.keyboard_arrow_right,
                        },
                        tooltip: '收起工具栏',
                        onPressed: onCollapse!,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: isActive,
        onPressed: onPressed,
        child: iconWidget ?? Icon(icon, size: 20),
      ),
    );
  }

  Widget _toolbarDivider(BuildContext context, bool vertical) {
    return Padding(
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: vertical ? 20 : 2,
        height: vertical ? 2 : 20,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Future<void> _runGlobalSmartLayout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    bool changed;
    Object? error;
    try {
      changed = await controller.runGlobalSmartLayout();
    } catch (caught) {
      changed = false;
      error = caught;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _smartLayoutMessage(changed: changed, error: error),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _smartLayoutMessage({required bool changed, Object? error}) {
    if (changed) return '智能排版已应用';
    if (error == null) return '智能排版失败，场景未修改';
    return '智能排版失败：${_readableError(error)}';
  }

  String _readableError(Object error) {
    final text = error is StateError ? error.message : error.toString();
    return text
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
  }
}

class _BrushMenuButton extends StatelessWidget {
  const _BrushMenuButton({required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    return StudioRailIconButton(
      tooltip: _labelForBrush(controller.activeBrushType),
      selected: controller.editorState.activeToolType == ToolType.freedraw,
      onPressed: () async {
        final selected = await showAnchoredPopupMenu<BrushType>(
          context: context,
          items: [
            for (final brushType in BrushType.values)
              PopupMenuItem(
                value: brushType,
                child: Row(
                  children: [
                    Icon(_iconForBrush(brushType), size: 18),
                    const SizedBox(width: 10),
                    Text(_labelForBrush(brushType)),
                  ],
                ),
              ),
          ],
        );
        if (selected != null) {
          controller.activeBrushType = selected;
        }
      },
      child: Icon(_iconForBrush(controller.activeBrushType), size: 19),
    );
  }
}

class _ShapeMenuButton extends StatelessWidget {
  const _ShapeMenuButton({
    required this.controller,
    required this.activeType,
    required this.colorScheme,
  });

  static const _shapeTools = [
    ToolType.rectangle,
    ToolType.diamond,
    ToolType.ellipse,
    ToolType.arrow,
    ToolType.line,
  ];

  final MarkdrawController controller;
  final ToolType activeType;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final active = _shapeTools.contains(activeType);
    final iconType = active ? activeType : ToolType.rectangle;
    return StudioRailIconButton(
      tooltip: '绘制图形',
      selected: active,
      emphasized: active,
      onPressed: () async {
        final selected = await showAnchoredPopupMenu<ToolType>(
          context: context,
          items: [
            for (final type in _shapeTools)
              PopupMenuItem(
                value: type,
                child: Row(
                  children: [
                    iconWidgetFor(
                      type,
                      color: colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(labelForToolType(type)),
                  ],
                ),
              ),
          ],
        );
        if (selected != null) {
          controller.switchTool(selected);
        }
      },
      child: iconWidgetFor(
        iconType,
        color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 20,
        isActive: active,
      ),
    );
  }
}

class _DockMenuButton extends StatelessWidget {
  const _DockMenuButton({required this.dock, required this.onDockChanged});

  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;

  @override
  Widget build(BuildContext context) {
    final icon = switch (dock) {
      ToolbarDock.top => const Icon(Icons.vertical_align_top, size: 20),
      ToolbarDock.left => const Icon(Icons.vertical_align_center, size: 20),
      ToolbarDock.right => Transform.flip(
        flipX: true,
        child: const Icon(Icons.vertical_align_center, size: 20),
      ),
    };
    return StudioRailIconButton(
      tooltip: '工具栏位置',
      onPressed: () async {
        final selected = await showAnchoredPopupMenu<ToolbarDock>(
          context: context,
          items: [
            for (final option in ToolbarDock.values)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Icon(_dockIcon(option), size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_dockLabel(option))),
                    if (option == dock) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
          ],
        );
        if (selected != null) {
          onDockChanged?.call(selected);
        }
      },
      child: icon,
    );
  }

  IconData _dockIcon(ToolbarDock option) => switch (option) {
    ToolbarDock.top => Icons.vertical_align_top,
    ToolbarDock.left || ToolbarDock.right => Icons.vertical_align_center,
  };

  String _dockLabel(ToolbarDock option) => switch (option) {
    ToolbarDock.top => '顶部',
    ToolbarDock.left => '靠左',
    ToolbarDock.right => '靠右',
  };
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: active,
        emphasized: active,
        onPressed: onPressed,
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
