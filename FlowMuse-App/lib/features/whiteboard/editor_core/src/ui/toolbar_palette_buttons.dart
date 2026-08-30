import 'package:flutter/material.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';

class BrushPaletteButton extends StatefulWidget {
  const BrushPaletteButton({
    super.key,
    required this.controller,
    required this.dock,
    required this.size,
  });

  final MarkdrawController controller;
  final ToolbarDock dock;
  final double size;

  @override
  State<BrushPaletteButton> createState() => _BrushPaletteButtonState();
}

class _BrushPaletteButtonState extends State<BrushPaletteButton> {
  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  @override
  void didUpdateWidget(BrushPaletteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.takeBrushPaletteRequest()) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showPalette(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StudioRailIconButton(
      tooltip: '笔型与压感',
      selected:
          widget.controller.editorState.activeToolType == ToolType.freedraw,
      size: widget.size,
      onPressed: () {
        if (widget.controller.activateBrush()) {
          _showPalette(context);
        }
      },
      child: Icon(_iconForBrush(widget.controller.activeBrushType), size: 20),
    );
  }

  Future<void> _showPalette(BuildContext context) async {
    if (_paletteOpen) return;
    _paletteOpen = true;
    try {
      await showAnchoredPopupMenu<Object>(
        context: context,
        placement: _placementForDock(widget.dock),
        items: [
          PopupMenuItem<Object>(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _BrushPalette(controller: widget.controller),
          ),
        ],
      );
    } finally {
      _paletteOpen = false;
    }
  }
}

class ShapePaletteButton extends StatelessWidget {
  const ShapePaletteButton({
    super.key,
    required this.controller,
    required this.dock,
    required this.size,
  });

  static const _shapeTools = [
    ToolType.rectangle,
    ToolType.diamond,
    ToolType.ellipse,
    ToolType.arrow,
    ToolType.line,
  ];

  final MarkdrawController controller;
  final ToolbarDock dock;
  final double size;

  @override
  Widget build(BuildContext context) {
    final activeType = controller.editorState.activeToolType;
    final active = _shapeTools.contains(activeType);
    final iconType = active ? activeType : ToolType.rectangle;
    final colors = Theme.of(context).colorScheme;
    return StudioRailIconButton(
      tooltip: '绘制图形',
      selected: active,
      emphasized: active,
      size: size,
      onPressed: () => _showPalette(context),
      child: iconWidgetFor(
        iconType,
        color: active ? colors.primary : colors.onSurfaceVariant,
        size: 20,
        isActive: active,
      ),
    );
  }

  Future<void> _showPalette(BuildContext context) async {
    await showAnchoredPopupMenu<Object>(
      context: context,
      placement: _placementForDock(dock),
      items: [
        PopupMenuItem<Object>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final type in _shapeTools)
                  StudioRailIconButton(
                    tooltip: labelForToolType(type),
                    selected: controller.editorState.activeToolType == type,
                    size: 44,
                    onPressed: () {
                      controller.switchTool(type);
                      Navigator.of(context).pop();
                    },
                    child: iconWidgetFor(
                      type,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BrushPalette extends StatelessWidget {
  const _BrushPalette({required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // 圆珠笔/荧光笔恒定线宽：不显示压力滑块（历史偏好仍持久化，
        // 切回压感笔型时自动恢复，不丢用户设置）。
        final pressureEnabled = BrushRenderProfile.forType(
          controller.activeBrushType,
        ).pressureEnabled;
        return SizedBox(
          width: 310,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final brushType in BrushType.values)
                      StudioRailIconButton(
                        tooltip: _labelForBrush(brushType),
                        selected: controller.activeBrushType == brushType,
                        size: 44,
                        onPressed: () {
                          controller.selectBrush(brushType);
                          Navigator.of(context).pop();
                        },
                        child: Icon(_iconForBrush(brushType), size: 20),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (pressureEnabled) ...[
                  Row(
                    children: [
                      Text(
                        pressureLabelFor(controller.activeBrushType),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('均匀', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Slider(
                          value: controller.pressureSensitivity,
                          min: 0,
                          max: 1,
                          onChanged: (value) {
                            controller.pressureSensitivity = value;
                          },
                        ),
                      ),
                      const Text('极强', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                  if (simulatedPressureCaptionFor(
                    controller.activeBrushType,
                  ).isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        simulatedPressureCaptionFor(controller.activeBrushType),
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text(
                          '压感',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '恒定线宽',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 压力滑块标签（T10）：v2 笔形按响应语义命名——铅笔压力主要控制
/// 石墨浓淡、毛笔主要控制笔肚提按宽度；其余笔保持"压感"既有语义。
String pressureLabelFor(BrushType brushType) => switch (brushType) {
  BrushType.pencil => '浓淡响应',
  BrushType.brushPen => '提按响应',
  _ => '压感',
};

/// v2 笔形（无手写笔时按书写速度模拟压力）的可解释文案。
String simulatedPressureCaptionFor(BrushType brushType) => switch (brushType) {
  BrushType.pencil => '无手写笔时按书写速度模拟浓淡',
  BrushType.brushPen => '无手写笔时按书写速度模拟提按',
  _ => '',
};

AnchoredPopupPlacement _placementForDock(ToolbarDock dock) => switch (dock) {
  ToolbarDock.top => AnchoredPopupPlacement.below,
  ToolbarDock.left => AnchoredPopupPlacement.right,
  ToolbarDock.right => AnchoredPopupPlacement.left,
};

String _labelForBrush(BrushType brushType) => switch (brushType) {
  BrushType.pencil => '铅笔',
  BrushType.ballpoint => '圆珠笔',
  BrushType.fountainPen => '钢笔',
  BrushType.brushPen => '毛笔',
  BrushType.highlighter => '荧光笔',
};

IconData _iconForBrush(BrushType brushType) => switch (brushType) {
  BrushType.pencil => Icons.edit_outlined,
  BrushType.ballpoint => Icons.mode_edit_outline,
  BrushType.fountainPen => Icons.draw,
  BrushType.brushPen => Icons.brush,
  // 荧光笔不用 material_symbols_icons：其字形经 release 构建 tree-shake
  // 后真机渲染为 .notdef 实心块（其余四笔同用 Material Icons 正常），
  // 与四支笔保持同族图标。
  BrushType.highlighter => Icons.highlight,
};
