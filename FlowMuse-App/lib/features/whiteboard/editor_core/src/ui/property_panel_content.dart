library;

import 'dart:async';

import 'package:flutter/material.dart' hide Element;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    as core
    show TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';

import 'color_picker.dart' as cp;

/// Shared property panel content used by both desktop and compact panels.
class PropertyPanelContent extends StatefulWidget {
  final MarkdrawController controller;
  final ElementStyle style;
  final List<Element> elements;
  final bool isLocked;
  final bool showFullTextProps;
  final bool isEditingText;
  final bool textOnly;
  final Size? canvasSize;

  const PropertyPanelContent({
    super.key,
    required this.controller,
    required this.style,
    required this.elements,
    required this.isLocked,
    required this.showFullTextProps,
    required this.isEditingText,
    this.textOnly = false,
    this.canvasSize,
  });

  @override
  State<PropertyPanelContent> createState() => _PropertyPanelContentState();
}

class _PropertyPanelContentState extends State<PropertyPanelContent> {
  OverlayEntry? _fontPickerEntry;
  bool _fontPickerInserted = false;

  MarkdrawController get controller => widget.controller;
  ElementStyle get style => widget.style;
  List<Element> get elements => widget.elements;
  bool get isLocked => widget.isLocked;
  bool get showFullTextProps => widget.showFullTextProps;
  bool get isEditingText => widget.isEditingText;
  bool get textOnly => widget.textOnly;
  Size? get canvasSize => widget.canvasSize;
  bool get isFreedrawTool =>
      controller.editorState.activeToolType == ToolType.freedraw;

  @override
  void dispose() {
    _removeFontPickerOverlay(restoreFocus: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isEditingText) {
      return _buildTextEditingPanel(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IgnorePointer(
          ignoring: isLocked,
          child: Opacity(
            opacity: isLocked ? 0.4 : 1.0,
            child: _buildStylePanel(context),
          ),
        ),
        if (elements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSectionLabel(context, '图层顺序'),
          _buildLayerButtons(context),
          const SizedBox(height: 8),
          _buildAlignmentButtons(context, elements.length),
          const SizedBox(height: 12),
          _buildSectionLabel(context, '操作'),
          _buildActionsRow(context),
        ],
      ],
    );
  }

  Widget _buildTextEditingPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, '描边'),
        _buildColorPickerRow(
          context,
          selected: style.strokeColor,
          onSelect: (c) =>
              controller.applyStyleChange(ElementStyle(strokeColor: c)),
          quickPicks: strokeQuickPicks,
          target: ColorPickerTarget.stroke,
        ),
        const SizedBox(height: 8),
        if (showFullTextProps) ...[
          _buildSectionLabel(context, '字体'),
          _buildFontPicker(context, style.fontFamily),
          const SizedBox(height: 8),
        ],
        if (style.hasText) ...[
          _buildSectionLabel(context, '字号'),
          _buildFontSizeRow(context, style.fontSize),
          const SizedBox(height: 8),
        ],
        if (showFullTextProps) ...[
          _buildSectionLabel(context, '文字对齐'),
          _buildTextAlignCombinedRow(
            context,
            style.textAlign,
            style.verticalAlign,
          ),
          const SizedBox(height: 8),
        ],
        _buildSectionLabel(context, '透明度'),
        _buildOpacitySlider(context, style.opacity),
      ],
    );
  }

  Widget _buildStylePanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, isFreedrawTool ? '颜色' : '描边'),
        _buildColorPickerRow(
          context,
          selected: style.strokeColor,
          onSelect: (c) =>
              controller.applyStyleChange(ElementStyle(strokeColor: c)),
          quickPicks: strokeQuickPicks,
          target: ColorPickerTarget.stroke,
        ),
        if (!textOnly) ...[
          if (!isFreedrawTool) ...[
            const SizedBox(height: 8),
            _buildSectionLabel(context, '背景'),
            _buildColorPickerRow(
              context,
              selected: style.backgroundColor,
              onSelect: (c) => controller.applyStyleChange(
                ElementStyle(backgroundColor: c),
              ),
              quickPicks: backgroundQuickPicks,
              target: ColorPickerTarget.background,
            ),
            const SizedBox(height: 8),
            _buildSectionLabel(context, '填充样式'),
            _buildFillStyleRow(context, style.fillStyle),
          ],
          const SizedBox(height: 8),
          _buildSectionLabel(
            context,
            isFreedrawTool ? '笔迹粗细' : '描边宽度',
          ),
          _buildStrokeWidthRow(context, style.strokeWidth),
          if (!isFreedrawTool) ...[
            const SizedBox(height: 8),
            _buildSectionLabel(context, '描边样式'),
            _buildStrokeStyleRow(context, style.strokeStyle),
            const SizedBox(height: 8),
            _buildSectionLabel(context, '手绘感'),
            _buildRoughnessRow(context, style.roughness),
            if (style.hasRoundness || style.canBreakPolygon) ...[
              const SizedBox(height: 8),
              _buildSectionLabel(context, '边角'),
              _buildEdgesRow(context, style),
            ],
          ],
        ],
        if (style.hasArrows) ...[
          const SizedBox(height: 8),
          _buildSectionLabel(context, '箭头类型'),
          _buildArrowTypeRow(context, style.arrowType),
        ],
        if (showFullTextProps) ...[
          const SizedBox(height: 12),
          _buildSectionLabel(context, '字体'),
          _buildFontPicker(context, style.fontFamily),
        ],
        if (style.hasText) ...[
          const SizedBox(height: 8),
          _buildSectionLabel(context, '字号'),
          _buildFontSizeRow(context, style.fontSize),
        ],
        if (showFullTextProps) ...[
          const SizedBox(height: 8),
          _buildSectionLabel(context, '文字对齐'),
          _buildTextAlignCombinedRow(
            context,
            style.textAlign,
            style.verticalAlign,
          ),
        ],
        if (style.hasArrows) ...[
          const SizedBox(height: 8),
          _buildArrowheadRow(
            context,
            label: '起点箭头',
            current: style.startArrowhead,
            isNone: style.startArrowheadNone,
            onSelect: (a) {
              if (a == null) {
                controller.applyStyleChange(
                  const ElementStyle(hasLines: true, startArrowheadNone: true),
                );
              } else {
                controller.applyStyleChange(
                  ElementStyle(hasLines: true, startArrowhead: a),
                );
              }
            },
          ),
          const SizedBox(height: 4),
          _buildArrowheadRow(
            context,
            label: '终点箭头',
            current: style.endArrowhead,
            isNone: style.endArrowheadNone,
            onSelect: (a) {
              if (a == null) {
                controller.applyStyleChange(
                  const ElementStyle(hasLines: true, endArrowheadNone: true),
                );
              } else {
                controller.applyStyleChange(
                  ElementStyle(hasLines: true, endArrowhead: a),
                );
              }
            },
          ),
        ],
        const SizedBox(height: 8),
        _buildSectionLabel(context, '透明度'),
        _buildOpacitySlider(context, style.opacity),
      ],
    );
  }

  // --- Helper builders ---

  Widget _buildSectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildColorPickerRow(
    BuildContext context, {
    required String? selected,
    required ValueChanged<String> onSelect,
    required List<String> quickPicks,
    ColorPickerTarget? target,
  }) {
    final isQuickPick = quickPicks.contains(selected);
    final shouldAutoOpen =
        target != null && controller.pendingColorPicker == target;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in quickPicks)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: cp.ColorSwatch(
              color: c,
              isSelected: selected == c,
              onTap: () => onSelect(c),
            ),
          ),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          color: Theme.of(context).dividerColor,
        ),
        cp.ColorPickerButton(
          color: selected ?? '#000000',
          isActive: !isQuickPick,
          onColorSelected: onSelect,
          onRenderScene: canvasSize != null
              ? controller.renderSceneImage
              : null,
          onSampleColor: controller.sampleColorFromImage,
          canvasSize: canvasSize,
          autoOpen: shouldAutoOpen,
          onAutoOpened: controller.clearPendingColorPicker,
          autoActivateEyedropper: target == ColorPickerTarget.stroke &&
              controller.pendingEyedropper,
          onEyedropperActivated: controller.clearPendingEyedropper,
        ),
      ],
    );
  }

  Widget _buildStrokeWidthRow(BuildContext context, double? current) {
    const widths = [1.0, 2.0, 4.0, 6.0];
    const displayWidths = [1.0, 2.0, 3.5, 5.0];
    const tooltips = ['细', '中', '粗', '特粗'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < widths.length; i++)
          IconToggleChip(
            isSelected: current == widths[i],
            onTap: () => controller.applyStyleChange(
              ElementStyle(strokeWidth: widths[i]),
            ),
            tooltip: tooltips[i],
            child: CustomPaint(
              size: const Size(20, 20),
              painter: StrokeWidthIcon(
                displayWidths[i],
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStrokeStyleRow(BuildContext context, StrokeStyle? current) {
    const styles = StrokeStyle.values;
    final names = ['solid', 'dashed', 'dotted'];
    const tooltips = ['实线', '虚线', '点线'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < styles.length; i++)
          IconToggleChip(
            isSelected: current == styles[i],
            onTap: () => controller.applyStyleChange(
              ElementStyle(strokeStyle: styles[i]),
            ),
            tooltip: tooltips[i],
            child: CustomPaint(
              size: const Size(20, 20),
              painter: StrokeStyleIcon(
                names[i],
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFillStyleRow(BuildContext context, FillStyle? current) {
    const styles = FillStyle.values;
    final names = ['solid', 'hachure', 'cross-hatch', 'zigzag'];
    const tooltips = ['纯色', '斜线', '交叉线', '锯齿线'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < styles.length; i++)
          IconToggleChip(
            isSelected: current == styles[i],
            onTap: () =>
                controller.applyStyleChange(ElementStyle(fillStyle: styles[i])),
            tooltip: tooltips[i],
            child: CustomPaint(
              size: const Size(20, 20),
              painter: FillStyleIcon(
                names[i],
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoughnessRow(BuildContext context, double? current) {
    const values = [0.0, 1.0, 3.0];
    const tooltips = ['精准', '自然', '夸张'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < values.length; i++)
          IconToggleChip(
            isSelected: current == values[i],
            onTap: () =>
                controller.applyStyleChange(ElementStyle(roughness: values[i])),
            tooltip: tooltips[i],
            child: CustomPaint(
              size: const Size(20, 20),
              painter: RoughnessIcon(
                values[i],
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOpacitySlider(BuildContext context, double? current) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 160,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: current ?? 1.0,
            min: 0,
            max: 1,
            divisions: 20,
            label: current != null ? '${(current * 100).round()}%' : '混合',
            onChanged: (v) =>
                controller.applyStyleChange(ElementStyle(opacity: v)),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgesRow(BuildContext context, ElementStyle style) {
    final current = style.roundness;
    final isRound = current != null;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (style.hasRoundness) ...[
          IconToggleChip(
            isSelected: !isRound,
            onTap: () {
              controller.applyStyleChange(
                const ElementStyle(hasRoundness: true),
              );
            },
            tooltip: '尖角',
            child: CustomPaint(
              size: const Size(20, 20),
              painter: RoundnessIcon(
                false,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          IconToggleChip(
            isSelected: isRound,
            onTap: () {
              final elems = controller.selectedElements;
              if (elems.isNotEmpty) {
                controller.pushHistory();
                final results = <ToolResult>[];
                for (final e in elems) {
                  final r = e is DiamondElement
                      ? const Roundness.proportional(value: 0)
                      : e is LineElement
                      ? const Roundness.proportional(value: 0)
                      : const Roundness.adaptive(value: 0);
                  results.add(UpdateElementResult(e.copyWith(roundness: r)));
                }
                controller.applyResult(
                  results.length == 1 ? results.first : CompoundResult(results),
                );
              } else {
                controller.applyStyleChange(
                  const ElementStyle(
                    roundness: Roundness.adaptive(value: 0),
                    hasRoundness: true,
                  ),
                );
              }
            },
            tooltip: '圆角',
            child: CustomPaint(
              size: const Size(20, 20),
              painter: RoundnessIcon(
                true,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
        if (style.canBreakPolygon)
          IconToggleChip(
            isSelected: true,
            onTap: () {
              final elems = controller.selectedElements;
              if (elems.isEmpty) return;
              controller.pushHistory();
              final result = PropertyPanelState.applyStyle(
                elems,
                const ElementStyle(canBreakPolygon: true),
              );
              controller.applyResult(result);
            },
            tooltip: '拆分多边形',
            child: const Icon(Icons.hexagon_outlined, size: 20),
          ),
      ],
    );
  }

  Widget _buildArrowTypeRow(BuildContext context, ArrowType? current) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final type in ArrowType.values)
          IconToggleChip(
            isSelected: current == type,
            onTap: () {
              controller.pushHistory();
              controller.applyStyleChange(
                ElementStyle(hasArrows: true, arrowType: type),
              );
            },
            tooltip: switch (type) {
              ArrowType.sharp => '直角',
              ArrowType.round => '圆滑',
              ArrowType.sharpElbow => '折线直角',
              ArrowType.roundElbow => '折线圆角',
            },
            child: CustomPaint(
              size: const Size(20, 20),
              painter: ArrowTypeIcon(switch (type) {
                ArrowType.sharp => 'sharp',
                ArrowType.round => 'round',
                ArrowType.sharpElbow => 'elbow',
                ArrowType.roundElbow => 'round-elbow',
              }, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
      ],
    );
  }

  Widget _buildArrowheadRow(
    BuildContext context, {
    required String label,
    required Arrowhead? current,
    required bool isNone,
    required void Function(Arrowhead?) onSelect,
  }) {
    final isStart = label == '起点箭头';
    const arrowheads = Arrowhead.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, label),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            IconToggleChip(
              isSelected: isNone,
              onTap: () => onSelect(null),
              tooltip: '无',
              child: CustomPaint(
                size: const Size(20, 20),
                painter: ArrowheadIcon(
                  null,
                  isStart: isStart,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            for (final ah in arrowheads)
              IconToggleChip(
                isSelected: current == ah,
                onTap: () => onSelect(ah),
                tooltip: _labelForArrowhead(ah),
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: ArrowheadIcon(
                    ah,
                    isStart: isStart,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayerButtons(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        IconToggleChip(
          isSelected: false,
          onTap: () {
            controller.pushHistory();
            final ids = controller.editorState.selectedIds;
            final updated = LayerUtils.sendToBack(
              controller.editorState.scene,
              ids,
            );
            if (updated.isEmpty) return;
            controller.applyResult(
              CompoundResult([for (final e in updated) UpdateElementResult(e)]),
            );
          },
          tooltip: '置于底层 (Ctrl+Shift+[)',
          child: const Icon(Icons.vertical_align_bottom, size: 18),
        ),
        IconToggleChip(
          isSelected: false,
          onTap: () {
            controller.pushHistory();
            final ids = controller.editorState.selectedIds;
            final updated = LayerUtils.sendBackward(
              controller.editorState.scene,
              ids,
            );
            if (updated.isEmpty) return;
            controller.applyResult(
              CompoundResult([for (final e in updated) UpdateElementResult(e)]),
            );
          },
          tooltip: '下移一层 (Ctrl+[)',
          child: const Icon(Icons.arrow_downward, size: 18),
        ),
        IconToggleChip(
          isSelected: false,
          onTap: () {
            controller.pushHistory();
            final ids = controller.editorState.selectedIds;
            final updated = LayerUtils.bringForward(
              controller.editorState.scene,
              ids,
            );
            if (updated.isEmpty) return;
            controller.applyResult(
              CompoundResult([for (final e in updated) UpdateElementResult(e)]),
            );
          },
          tooltip: '上移一层 (Ctrl+])',
          child: const Icon(Icons.arrow_upward, size: 18),
        ),
        IconToggleChip(
          isSelected: false,
          onTap: () {
            controller.pushHistory();
            final ids = controller.editorState.selectedIds;
            final updated = LayerUtils.bringToFront(
              controller.editorState.scene,
              ids,
            );
            if (updated.isEmpty) return;
            controller.applyResult(
              CompoundResult([for (final e in updated) UpdateElementResult(e)]),
            );
          },
          tooltip: '置于顶层 (Ctrl+Shift+])',
          child: const Icon(Icons.vertical_align_top, size: 18),
        ),
      ],
    );
  }

  Widget _buildAlignmentButtons(BuildContext context, int selectedCount) {
    if (selectedCount < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(context, '对齐'),
        Wrap(
          spacing: 4,
          children: [
            _alignButton(
              context,
              Icons.align_horizontal_left,
              '左对齐',
              AlignmentUtils.alignLeft,
            ),
            _alignButton(
              context,
              Icons.align_horizontal_center,
              '水平居中',
              AlignmentUtils.alignCenterH,
            ),
            _alignButton(
              context,
              Icons.align_horizontal_right,
              '右对齐',
              AlignmentUtils.alignRight,
            ),
            _alignButton(
              context,
              Icons.align_vertical_top,
              '顶部对齐',
              AlignmentUtils.alignTop,
            ),
            _alignButton(
              context,
              Icons.align_vertical_center,
              '垂直居中',
              AlignmentUtils.alignCenterV,
            ),
            _alignButton(
              context,
              Icons.align_vertical_bottom,
              '底部对齐',
              AlignmentUtils.alignBottom,
            ),
          ],
        ),
        if (selectedCount >= 3) ...[
          const SizedBox(height: 4),
          _buildSectionLabel(context, '分布'),
          Wrap(
            spacing: 4,
            children: [
              _alignButton(
                context,
                Icons.horizontal_distribute,
                '水平分布',
                AlignmentUtils.distributeH,
              ),
              _alignButton(
                context,
                Icons.vertical_distribute,
                '垂直分布',
                AlignmentUtils.distributeV,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _alignButton(
    BuildContext context,
    IconData icon,
    String tooltip,
    List<Element> Function(List<Element>) operation,
  ) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        onPressed: () {
          final elems = controller.selectedElements;
          if (elems.isEmpty) return;
          controller.pushHistory();
          final updated = operation(elems);
          if (updated.isEmpty) return;
          controller.applyResult(
            CompoundResult([for (final e in updated) UpdateElementResult(e)]),
          );
        },
      ),
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    final hasGroup = elements.any((e) => e.groupIds.isNotEmpty);
    final isSingle = elements.length == 1;
    final canConvertInk =
        elements.isNotEmpty &&
        elements.every((element) => element is FreedrawElement);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        IconToggleChip(
          isSelected: false,
          onTap: () => controller.dispatchKey('d', ctrl: true),
          tooltip: '复制副本',
          child: const Icon(Icons.copy, size: 18),
        ),
        if (elements.length >= 2)
          IconToggleChip(
            isSelected: false,
            onTap: () => controller.dispatchKey('g', ctrl: true),
            tooltip: '组合',
            child: const Icon(Icons.group_work, size: 18),
          ),
        if (hasGroup)
          IconToggleChip(
            isSelected: false,
            onTap: () => controller.dispatchKey('g', ctrl: true, shift: true),
            tooltip: '取消组合',
            child: const Icon(Icons.group_work_outlined, size: 18),
          ),
        if (isSingle)
          IconToggleChip(
            isSelected: elements.first.link != null,
            onTap: () => controller.openLinkEditor(),
            tooltip: '链接 (Ctrl+K)',
            child: const Icon(Icons.link, size: 18),
          ),
        if (isSingle &&
            elements.first is LineElement &&
            !(elements.first is ArrowElement &&
                (elements.first as ArrowElement).elbowed))
          IconToggleChip(
            isSelected: controller.isEditingLinear,
            onTap: () {
              controller.isEditingLinear = !controller.isEditingLinear;
            },
            tooltip: elements.first is ArrowElement ? '编辑箭头' : '编辑直线',
            child: const Icon(Icons.timeline, size: 18),
          ),
        if (canConvertInk)
          IconToggleChip(
            isSelected: false,
            onTap: () {
              unawaited(controller.convertSelectedInkToText());
            },
            tooltip: '转为文字',
            child: const Icon(Icons.text_fields, size: 18),
          ),
        IconToggleChip(
          isSelected: false,
          onTap: () => controller.dispatchKey('Delete'),
          tooltip: '删除',
          child: const Icon(Icons.delete_outline, size: 18),
        ),
        _buildLockToggle(context, style.locked),
      ],
    );
  }

  Widget _buildLockToggle(BuildContext context, bool? current) {
    final isLocked = current ?? false;
    return IconToggleChip(
      isSelected: isLocked,
      onTap: () {
        controller.pushHistory();
        final elems = controller.selectedElements;
        if (elems.isEmpty) return;
        final on = !isLocked;
        final results = <ToolResult>[
          for (final e in elems) UpdateElementResult(e.copyWith(locked: on)),
        ];
        controller.applyResult(
          results.length == 1 ? results.first : CompoundResult(results),
        );
      },
      tooltip: isLocked ? '解锁' : '锁定',
      child: Icon(isLocked ? Icons.lock : Icons.lock_open, size: 18),
    );
  }

  Widget _buildFontSizeRow(BuildContext context, double? current) {
    const sizes = [16.0, 20.0, 28.0, 36.0];
    const labels = ['S', 'M', 'L', 'XL'];
    final displaySize = current != null ? current.round().toString() : '—';
    final isPreset = current != null && sizes.contains(current);
    return Row(
      children: [
        Flexible(
          child: _buildToggleRow(
            count: 4,
            labels: labels,
            isSelected: (i) => current == sizes[i],
            onTap: (i) => controller.applyStyleChange(
              ElementStyle(hasText: true, fontSize: sizes[i]),
            ),
          ),
        ),
        Container(
          width: 1,
          height: 24,
          color: Theme.of(context).dividerColor,
          margin: const EdgeInsets.symmetric(horizontal: 6),
        ),
        ToggleChip(
          label: displaySize,
          isSelected: !isPreset && current != null,
          onTap: () => _showFontSizeDialog(context, current),
        ),
      ],
    );
  }

  void _showFontSizeDialog(BuildContext context, double? current) {
    final wasEditing = controller.editingTextElementId != null;
    final savedSelection = wasEditing ? controller.editableTextSelection : null;
    if (wasEditing) controller.suppressFocusCommit = true;

    showDialog<double>(
      context: context,
      builder: (ctx) => _FontSizeDialog(
        initialValue: current != null ? current.round().toString() : '',
      ),
    ).then((fontSize) {
      runWhenUiStable(() {
        if (!mounted) {
          return;
        }
        if (fontSize != null) {
          controller.applyStyleChange(
            ElementStyle(hasText: true, fontSize: fontSize.clamp(4.0, 200.0)),
          );
        }
        controller.restoreTextFocus(wasEditing, savedSelection);
      });
    });
  }

  Widget _buildFontPicker(BuildContext context, String? current) {
    final currentCategory = FontResolver.categoryOf(
      current ?? FontResolver.defaultFontFamily,
    );
    final isCompact = controller.isCompact;
    if (isCompact) {
      return _AutoOpenFontPicker(
        controller: controller,
        current: current,
        child: Row(
          children: [
            _buildFontCategoryButtons(context, current, currentCategory),
            Container(
              width: 1,
              height: 24,
              color: Theme.of(context).dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
            IconToggleChip(
              isSelected: controller.fontPickerOpen,
              onTap: () => _showCompactFontPicker(context, current),
              tooltip: '更多字体',
              child: const Icon(Icons.more_horiz, size: 18),
            ),
          ],
        ),
        onAutoOpen: () => _showCompactFontPicker(context, current),
      );
    }
    return Builder(
      builder: (innerContext) => _AutoOpenFontPicker(
        controller: controller,
        current: current,
        onAutoOpen: () => _showFontPickerOverlay(innerContext, current),
        child: Row(
          children: [
            _buildFontCategoryButtons(context, current, currentCategory),
            Container(
              width: 1,
              height: 24,
              color: Theme.of(context).dividerColor,
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
            IconToggleChip(
              isSelected: controller.fontPickerOpen,
              onTap: () => _showFontPickerOverlay(innerContext, current),
              tooltip: '更多字体',
              child: const Icon(Icons.more_horiz, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontCategoryButtons(
    BuildContext context,
    String? current,
    FontCategory category,
  ) {
    return Wrap(
      spacing: 4,
      children: [
        IconToggleChip(
          isSelected:
              category == FontCategory.handDrawn && !controller.fontPickerOpen,
          onTap: () => controller.applyStyleChange(
            ElementStyle(
              hasText: true,
              fontFamily:
                  FontResolver.defaultForCategory[FontCategory.handDrawn],
            ),
          ),
          tooltip: '手绘',
          child: Text(
            'A',
            style: FontResolver.resolve(
              'Excalifont',
              baseStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ),
        IconToggleChip(
          isSelected:
              category == FontCategory.normal && !controller.fontPickerOpen,
          onTap: () => controller.applyStyleChange(
            ElementStyle(
              hasText: true,
              fontFamily: FontResolver.defaultForCategory[FontCategory.normal],
            ),
          ),
          tooltip: '常规',
          child: const Text('Aa', style: TextStyle(fontSize: 13)),
        ),
        IconToggleChip(
          isSelected:
              category == FontCategory.code && !controller.fontPickerOpen,
          onTap: () => controller.applyStyleChange(
            ElementStyle(
              hasText: true,
              fontFamily: FontResolver.defaultForCategory[FontCategory.code],
            ),
          ),
          tooltip: '代码',
          child: const Text(
            '{}',
            style: TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }

  void _showFontPickerOverlay(BuildContext context, String? current) {
    if (_fontPickerEntry != null) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return;
    }
    final renderBox = renderObject;
    final offset = renderBox.localToGlobal(Offset.zero);
    final overlay = Overlay.of(context);

    final wasEditing = controller.editingTextElementId != null;
    final savedSelection = wasEditing ? controller.editableTextSelection : null;
    if (wasEditing) controller.suppressFocusCommit = true;

    runWhenUiStable(() {
      if (mounted) {
        controller.fontPickerOpen = true;
      }
    });

    _fontPickerEntry = OverlayEntry(
      builder: (ctx) => FontPickerOverlay(
        anchor: offset,
        currentFont: current ?? FontResolver.defaultFontFamily,
        sceneFonts: controller.getSceneFontFamilies(),
        onSelect: (font) {
          _removeFontPickerOverlay(restoreFocus: false);
          runWhenUiStable(() {
            if (mounted) {
              controller.applyStyleChange(
                ElementStyle(hasText: true, fontFamily: font),
              );
              controller.restoreTextFocus(wasEditing, savedSelection);
            }
          });
        },
        onDismiss: () {
          _removeFontPickerOverlay();
          runWhenUiStable(() {
            if (mounted) {
              controller.restoreTextFocus(wasEditing, savedSelection);
            }
          });
        },
      ),
    );
    _insertFontPickerOverlay(overlay, _fontPickerEntry!);
  }

  void _removeFontPickerOverlay({bool restoreFocus = true}) {
    final entry = _fontPickerEntry;
    _fontPickerEntry = null;
    runWhenUiStable(() {
      if (mounted) {
        controller.fontPickerOpen = false;
      }
    });
    if (!restoreFocus) {
      controller.suppressFocusCommit = false;
    }
    if (entry == null) {
      return;
    }
    if (!_fontPickerInserted) {
      return;
    }
    _fontPickerInserted = false;
    removeOverlayEntryAfterTeardown(entry);
  }

  void _insertFontPickerOverlay(OverlayState overlay, OverlayEntry entry) {
    insertOverlayEntryWhenStable(
      overlay: overlay,
      entry: entry,
      shouldInsert: () => mounted && identical(_fontPickerEntry, entry),
      onInserted: () {
        if (mounted && identical(_fontPickerEntry, entry)) {
          _fontPickerInserted = true;
        }
      },
    );
  }

  void _showCompactFontPicker(BuildContext context, String? current) {
    final wasEditing = controller.editingTextElementId != null;
    final savedSelection = wasEditing ? controller.editableTextSelection : null;
    String? selectedFont;
    if (wasEditing) controller.suppressFocusCommit = true;

    runWhenUiStable(() {
      if (mounted) {
        controller.fontPickerOpen = true;
      }
    });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => TextFieldTapRegion(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => FontListContent(
            currentFont: current ?? FontResolver.defaultFontFamily,
            sceneFonts: controller.getSceneFontFamilies(),
            scrollController: scrollController,
            onSelect: (font) {
              selectedFont = font;
              Navigator.of(ctx).pop();
            },
          ),
        ),
      ),
    ).whenComplete(() {
      runWhenUiStable(() {
        if (!mounted) {
          return;
        }
        controller.fontPickerOpen = false;
        final font = selectedFont;
        if (font != null) {
          controller.applyStyleChange(
            ElementStyle(hasText: true, fontFamily: font),
          );
        }
        controller.restoreTextFocus(wasEditing, savedSelection);
      });
    });
  }

  Widget _buildTextAlignCombinedRow(
    BuildContext context,
    core.TextAlign? hCurrent,
    VerticalAlign? vCurrent,
  ) {
    const hAligns = core.TextAlign.values;
    const hIcons = [
      Icons.format_align_left,
      Icons.format_align_center,
      Icons.format_align_right,
    ];
    const hTooltips = ['左对齐', '居中对齐', '右对齐'];
    const vAligns = VerticalAlign.values;
    const vIcons = [
      Icons.vertical_align_top,
      Icons.vertical_align_center,
      Icons.vertical_align_bottom,
    ];
    const vTooltips = ['顶部对齐', '中部对齐', '底部对齐'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          children: [
            for (var i = 0; i < hAligns.length; i++)
              IconToggleChip(
                isSelected: hCurrent == hAligns[i],
                onTap: () => controller.applyStyleChange(
                  ElementStyle(hasText: true, textAlign: hAligns[i]),
                ),
                tooltip: hTooltips[i],
                child: Icon(hIcons[i], size: 18),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: [
            for (var i = 0; i < vAligns.length; i++)
              IconToggleChip(
                isSelected: vCurrent == vAligns[i],
                onTap: () => controller.applyStyleChange(
                  ElementStyle(hasText: true, verticalAlign: vAligns[i]),
                ),
                tooltip: vTooltips[i],
                child: Icon(vIcons[i], size: 18),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required int count,
    required List<String> labels,
    required bool Function(int) isSelected,
    required ValueChanged<int> onTap,
  }) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < count; i++)
          ToggleChip(
            label: labels[i],
            isSelected: isSelected(i),
            onTap: () => onTap(i),
          ),
      ],
    );
  }
}

class _FontSizeDialog extends StatefulWidget {
  const _FontSizeDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_FontSizeDialog> createState() => _FontSizeDialogState();
}

class _FontSizeDialogState extends State<_FontSizeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final parsed = double.tryParse(value ?? _controller.text);
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义字号'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '字号',
          hintText: '4–200',
          isDense: true,
        ),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('应用')),
      ],
    );
  }
}

String _labelForArrowhead(Arrowhead arrowhead) {
  return switch (arrowhead) {
    Arrowhead.arrow => '箭头',
    Arrowhead.bar => '竖线',
    Arrowhead.dot => '圆点',
    Arrowhead.triangle => '实心三角',
    Arrowhead.triangleOutline => '空心三角',
    Arrowhead.circle => '实心圆',
    Arrowhead.circleOutline => '空心圆',
    Arrowhead.diamond => '实心菱形',
    Arrowhead.diamondOutline => '空心菱形',
    Arrowhead.crowfootOne => '一端鸦脚',
    Arrowhead.crowfootMany => '多端鸦脚',
    Arrowhead.crowfootOneOrMany => '一或多鸦脚',
  };
}

/// Auto-opens the font picker when [controller.pendingColorPicker] is [ColorPickerTarget.font].
class _AutoOpenFontPicker extends StatefulWidget {
  final MarkdrawController controller;
  final String? current;
  final Widget child;
  final VoidCallback onAutoOpen;

  const _AutoOpenFontPicker({
    required this.controller,
    required this.current,
    required this.child,
    required this.onAutoOpen,
  });

  @override
  State<_AutoOpenFontPicker> createState() => _AutoOpenFontPickerState();
}

class _AutoOpenFontPickerState extends State<_AutoOpenFontPicker> {
  @override
  void initState() {
    super.initState();
    _maybeAutoOpen();
  }

  @override
  void didUpdateWidget(_AutoOpenFontPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeAutoOpen();
  }

  void _maybeAutoOpen() {
    if (widget.controller.pendingColorPicker == ColorPickerTarget.font &&
        !widget.controller.fontPickerOpen) {
      widget.controller.clearPendingColorPicker();
      runWhenUiStable(() {
        if (mounted) widget.onAutoOpen();
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
