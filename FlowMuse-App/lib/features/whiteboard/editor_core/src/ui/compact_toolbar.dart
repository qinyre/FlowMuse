library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';

/// Compact bottom toolbar for mobile layout.
class CompactToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final bool showHistory;
  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;
  final VoidCallback? onCollapse;

  const CompactToolbar({
    super.key,
    required this.controller,
    this.showHistory = true,
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
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
              if (showHistory) ...[
                _compactButton(
                  cs: cs,
                  icon: Icons.undo,
                  tooltip: '撤销',
                  onPressed: controller.undo,
                ),
                _compactButton(
                  cs: cs,
                  icon: Icons.redo,
                  tooltip: '重做',
                  onPressed: controller.redo,
                ),
                Padding(
                  padding: vertical
                      ? const EdgeInsets.symmetric(vertical: 6)
                      : const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: vertical ? 20 : 2,
                    height: vertical ? 2 : 20,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
              _compactToolButton(
                cs: cs,
                type: ToolType.hand,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.select,
                activeType: activeType,
              ),
              _CompactBrushMenuButton(controller: controller),
              _CompactShapeMenuButton(
                controller: controller,
                activeType: activeType,
                colorScheme: cs,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.freedraw,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.text,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.eraser,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.laser,
                activeType: activeType,
              ),
              // 压感灵敏度滑块：仅在手写(freedraw)工具激活时显示
              if (showPressureSlider) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CompactPressureSlider(controller: controller),
                ),
              ],
              _compactButton(
                cs: cs,
                icon: Icons.text_fields,
                tooltip: '文字识别模式',
                onPressed: controller.toggleInkRecognitionMode,
                isActive: controller.inkRecognitionMode,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.auto_fix_high,
                tooltip: '智能排布模式',
                onPressed: controller.toggleSmartInkLayoutMode,
                isActive: controller.smartInkLayoutMode,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.document_scanner_outlined,
                tooltip: '全局识别排版',
                onPressed: () {
                  _runGlobalSmartLayout(context);
                },
              ),
              _compactButton(
                cs: cs,
                iconWidget: _dockIcon(dock),
                tooltip: '工具栏位置',
                onPressed: () => _showDockMenu(context),
              ),
              if (onCollapse != null)
                _compactButton(
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

  Widget _compactToolButton({
    required ColorScheme cs,
    required ToolType type,
    required ToolType activeType,
  }) {
    final active = activeType == type;
    return _compactButton(
      cs: cs,
      iconWidget: iconWidgetFor(
        type,
        color: active ? cs.primary : cs.onSurfaceVariant,
        size: 22,
        isActive: active,
      ),
      tooltip: labelForToolType(type),
      onPressed: () => controller.switchTool(type),
      isActive: active,
      isEmphasized: active,
    );
  }

  Widget _dockIcon(ToolbarDock value) => switch (value) {
    ToolbarDock.top => const Icon(Icons.vertical_align_top, size: 22),
    ToolbarDock.left => const Icon(Icons.vertical_align_center, size: 22),
    ToolbarDock.right => Transform.flip(
      flipX: true,
      child: const Icon(Icons.vertical_align_center, size: 22),
    ),
  };

  Future<void> _showDockMenu(BuildContext context) async {
    final selected = await showAnchoredPopupMenu<ToolbarDock>(
      context: context,
      items: [
        for (final option in ToolbarDock.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == ToolbarDock.top
                      ? Icons.vertical_align_top
                      : Icons.vertical_align_center,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    switch (option) {
                      ToolbarDock.top => '顶部',
                      ToolbarDock.left => '靠左',
                      ToolbarDock.right => '靠右',
                    },
                  ),
                ),
                if (option == dock) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
    if (selected != null) {
      onDockChanged?.call(selected);
    }
  }

  Widget _compactButton({
    required ColorScheme cs,
    IconData? icon,
    Widget? iconWidget,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
    bool isEmphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: isActive,
        emphasized: isEmphasized,
        size: 44,
        onPressed: onPressed,
        child: iconWidget ?? Icon(icon, size: 22),
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

class _CompactBrushMenuButton extends StatelessWidget {
  const _CompactBrushMenuButton({required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    return StudioRailIconButton(
      tooltip: _labelForBrush(controller.activeBrushType),
      size: 44,
      selected: controller.editorState.activeToolType == ToolType.freedraw,
      onPressed: () => _showBrushMenu(context),
      child: Icon(_iconForBrush(controller.activeBrushType), size: 19),
    );
  }

  Future<void> _showBrushMenu(BuildContext context) async {
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
  }
}

class _CompactShapeMenuButton extends StatelessWidget {
  const _CompactShapeMenuButton({
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
      size: 44,
      selected: active,
      emphasized: active,
      onPressed: () => _showShapeMenu(context),
      child: iconWidgetFor(
        iconType,
        color: active ? colorScheme.primary : colorScheme.onSurfaceVariant,
        size: 22,
        isActive: active,
      ),
    );
  }

  Future<void> _showShapeMenu(BuildContext context) async {
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
  }
}

/// Compact 布局的压感灵敏度弹出式滑块。
class _CompactPressureSlider extends StatelessWidget {
  final MarkdrawController controller;
  const _CompactPressureSlider({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return GestureDetector(
          onTap: () => _showSliderPopup(context),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.line_weight,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '压感',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSliderPopup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: controller,
          builder: (ctx, _) {
            final value = controller.pressureSensitivity;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('压感强度', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('均匀', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: value,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            controller.pressureSensitivity = v;
                          },
                        ),
                      ),
                      const Text('极强', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
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
