library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// The main canvas area with pointer/gesture handling.
class EditorCanvas extends StatefulWidget {
  final MarkdrawController controller;

  const EditorCanvas({super.key, required this.controller});

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  MarkdrawController get controller => widget.controller;

  List<LinkIconInfo>? _buildLinkIcons() {
    final selectedIds = controller.editorState.selectedIds;
    final icons = <LinkIconInfo>[];
    for (final element in controller.editorState.scene.activeElements) {
      if (element.link == null || element.link!.isEmpty) continue;
      // Skip selected elements — they show the overlay instead
      if (selectedIds.contains(element.id)) continue;
      icons.add(
        LinkIconInfo(
          x: element.x,
          y: element.y,
          width: element.width,
          height: element.height,
        ),
      );
    }
    return icons.isEmpty ? null : icons;
  }

  @override
  Widget build(BuildContext context) {
    final toolOverlay = controller.activeTool.overlay;

    // Convert Bounds marqueeRect to Flutter Rect
    Rect? marqueeRect;
    if (toolOverlay?.marqueeRect != null) {
      final b = toolOverlay!.marqueeRect!;
      marqueeRect = Rect.fromLTWH(b.left, b.top, b.size.width, b.size.height);
    }

    return ColoredBox(
      color: parseColor(controller.canvasBackgroundColor),
      child: MouseRegion(
        cursor: controller.cursorForTool,
        child: Stack(
          children: [
            GestureDetector(
              onScaleStart: (details) => controller.onScaleStart(details),
              onScaleUpdate: (details) => controller.onScaleUpdate(details),
              onScaleEnd: (_) {},
              child: Listener(
                onPointerHover: (event) {
                  controller.onPointerHover(event.localPosition);
                },
                onPointerDown: (event) {
                  controller.onPointerDown(event.localPosition);
                },
                onPointerMove: (event) {
                  controller.onPointerMove(event.localPosition, event.delta);
                },
                onPointerUp: (event) {
                  controller.onPointerUp(event.localPosition);
                },
                onPointerSignal: (event) {
                  controller.onPointerSignal(event);
                },
                child: CustomPaint(
                  painter: StaticCanvasPainter(
                    scene: controller.editorState.scene,
                    adapter: controller.adapter,
                    viewport: controller.editorState.viewport,
                    previewElement: controller.buildPreviewElement(toolOverlay),
                    editingElementId: controller.editingTextElementId,
                    resolvedImages: controller.resolveImages(),
                    pendingElements: controller.flowchartCreator.isCreating
                        ? controller.flowchartCreator.pendingElements
                        : null,
                    gridSize: controller.gridSize,
                    isDarkBackground: _isDark(controller.canvasBackgroundColor),
                  ),
                  foregroundPainter: InteractiveCanvasPainter(
                    viewport: controller.editorState.viewport,
                    interactionMode: controller.interactionMode,
                    selection: controller.isDraggingPointHandle()
                        ? null
                        : controller.buildSelectionOverlay(),
                    marqueeRect: marqueeRect,
                    snapLines: toolOverlay?.snapLines ?? const [],
                    bindTargetBounds: toolOverlay?.bindTargetBounds,
                    bindTargetAngle: toolOverlay?.bindTargetAngle ?? 0.0,
                    closeIndicatorCenter: toolOverlay?.closeIndicatorCenter,
                    pointHandles: controller.buildPointHandles(),
                    midpointHandles: controller.buildMidpointHandles(),
                    segmentMidpoints: controller.isDraggingPointHandle()
                        ? null
                        : controller.buildSegmentMidpoints(),
                    creationPoints: toolOverlay?.creationPoints,
                    creationBounds: toolOverlay?.creationBounds,
                    laserTrail: controller.activeTool is LaserTool
                        ? (controller.activeTool as LaserTool).activeTrail
                        : null,
                    linkIcons: _buildLinkIcons(),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            if (controller.editorState.activeToolType == ToolType.eraser &&
                controller.mousePosition != null)
              Positioned(
                left: controller.mousePosition!.dx - 10,
                top: controller.mousePosition!.dy - 10,
                child: IgnorePointer(
                  child: CustomPaint(
                    size: const Size(20, 20),
                    painter: EraserCursorPainter(),
                  ),
                ),
              ),
            if (controller.editingTextElementId != null)
              TextEditingOverlay(controller: controller),
            if (controller.editingFrameLabelId != null)
              _FrameLabelEditingOverlay(controller: controller),
            // Compact property panel trigger
            if (controller.isCompact && controller.selectedElements.isNotEmpty)
              Positioned(
                bottom: 72,
                right: 12,
                child: _CompactPropertyButton(controller: controller),
              ),
          ],
        ),
      ),
    );
  }
}

/// Checks if a hex background color is dark (luminance < 0.5).
bool _isDark(String hexColor) {
  final c = parseColor(hexColor);
  return c.computeLuminance() < 0.5;
}

/// Inline text field overlay for editing a frame's label on the canvas.
class _FrameLabelEditingOverlay extends StatefulWidget {
  final MarkdrawController controller;
  const _FrameLabelEditingOverlay({required this.controller});

  @override
  State<_FrameLabelEditingOverlay> createState() =>
      _FrameLabelEditingOverlayState();
}

class _FrameLabelEditingOverlayState extends State<_FrameLabelEditingOverlay> {
  late TextEditingController _textController;
  final _focusNode = FocusNode();
  bool _committed = false;

  FrameElement? get _frame {
    final id = widget.controller.editingFrameLabelId;
    if (id == null) return null;
    final e = widget.controller.editorState.scene.getElementById(id);
    return e is FrameElement ? e : null;
  }

  @override
  void initState() {
    super.initState();
    final frame = _frame;
    _textController = TextEditingController(text: frame?.label ?? '');
    _textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _textController.text.length,
    );
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (!_committed) {
      widget.controller.commitFrameLabel(_textController.text);
    }
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _submit(_textController.text);
    }
  }

  void _submit(String value) {
    if (_committed) return;
    _committed = true;
    widget.controller.commitFrameLabel(value);
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    if (frame == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewport = widget.controller.editorState.viewport;
    final zoom = viewport.zoom;

    // Position the text field at the frame label location (above top-left)
    final screenPos = viewport.sceneToScreen(Offset(frame.x, frame.y - 4));

    // Match the rendered label style
    const fontSize = 14.0;
    final scaledFontSize = fontSize * zoom;
    final fieldWidth = (frame.width * zoom).clamp(80.0, 400.0);

    return Positioned(
      left: screenPos.dx,
      top: screenPos.dy - scaledFontSize - 4,
      child: SizedBox(
        width: fieldWidth,
        height: scaledFontSize + 8,
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          style: TextStyle(
            fontSize: scaledFontSize,
            fontFamily: 'Helvetica',
            color: isDark ? cs.onSurface : cs.onSurface,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 2,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(color: cs.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            filled: true,
            fillColor: cs.surface,
          ),
          onSubmitted: _submit,
        ),
      ),
    );
  }
}

/// Floating button that opens the compact property panel bottom sheet.
class _CompactPropertyButton extends StatelessWidget {
  final MarkdrawController controller;
  const _CompactPropertyButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: IconButton(
        icon: const Icon(Icons.tune, size: 22),
        tooltip: '属性',
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: () => showCompactPropertyPanel(context, controller),
      ),
    );
  }
}
