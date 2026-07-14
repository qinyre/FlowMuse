import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';

class BrushPaletteButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return StudioRailIconButton(
      tooltip: '笔型与压感',
      selected: controller.editorState.activeToolType == ToolType.freedraw,
      size: size,
      onPressed: () => _showPalette(context),
      child: Icon(_iconForBrush(controller.activeBrushType), size: 20),
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
          child: _BrushPalette(controller: controller),
        ),
      ],
    );
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
      builder: (context, _) => SizedBox(
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
                        controller.activeBrushType = brushType;
                        controller.switchTool(ToolType.freedraw);
                        Navigator.of(context).pop();
                      },
                      child: Icon(_iconForBrush(brushType), size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '压感',
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
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
            ],
          ),
        ),
      ),
    );
  }
}

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
  BrushType.highlighter => Symbols.ink_highlighter,
};
