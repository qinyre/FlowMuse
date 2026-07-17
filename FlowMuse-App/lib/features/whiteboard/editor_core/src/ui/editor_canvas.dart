library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element, SelectionOverlay;
import 'package:flutter_math_fork/flutter_math.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';

import '../rendering/math_text_utils.dart';

/// The main canvas area with pointer/gesture handling.
class EditorCanvas extends StatefulWidget {
  final MarkdrawController controller;
  final List<RemoteCollaboratorOverlay> collaborators;
  final void Function(Offset localPosition, bool pointerDown)?
  onPointerPresence;
  final void Function(Size canvasSize)? onVisibleSceneBoundsChanged;

  const EditorCanvas({
    super.key,
    required this.controller,
    this.collaborators = const [],
    this.onPointerPresence,
    this.onVisibleSceneBoundsChanged,
  });

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas>
    with SingleTickerProviderStateMixin {
  static const double _appendPageReleaseThreshold = 196;
  static const double _appendPageMaxOverscroll = 228;

  MarkdrawController get controller => widget.controller;
  Size? _lastReportedSize;
  final Set<int> _activeTouchPointers = {};
  int? _pagedScrollPointer;
  double _appendPageOverscroll = 0;
  bool _appendPageReady = false;
  late final AnimationController _appendPageOverscrollController;

  @override
  void initState() {
    super.initState();
    _appendPageOverscrollController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        _setAppendPageOverscroll(
          _appendPageOverscrollController.value,
          updateController: false,
        );
      });
  }

  @override
  void dispose() {
    _appendPageOverscrollController.dispose();
    super.dispose();
  }

  bool _shouldHandlePagedTouch(PointerEvent event) {
    return controller.isPagedViewport &&
        event.kind == PointerDeviceKind.touch &&
        controller.canPanPagedViewportWithTouch;
  }

  bool _isPagedTouchPointer(PointerEvent event) =>
      _activeTouchPointers.contains(event.pointer);

  void _startPagedTouch(PointerDownEvent event) {
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length == 1) {
      _pagedScrollPointer = event.pointer;
      _appendPageOverscrollController.stop();
    } else {
      _pagedScrollPointer = null;
      _snapBackAppendPageOverscroll();
    }
  }

  void _updatePagedTouch(PointerMoveEvent event) {
    if (_pagedScrollPointer != event.pointer ||
        _activeTouchPointers.length != 1) {
      return;
    }

    final scrollDelta = controller.layout.isRightToLeft
        ? event.delta.dx
        : -event.delta.dy;
    if (scrollDelta == 0) {
      return;
    }

    if (_appendPageOverscroll > 0 && scrollDelta < 0) {
      _setAppendPageOverscroll(_appendPageOverscroll + scrollDelta);
      widget.onVisibleSceneBoundsChanged?.call(controller.canvasSize);
      return;
    }

    final metrics = controller.pagedViewportMetrics;
    if (metrics != null && metrics.atEnd && scrollDelta > 0) {
      _setAppendPageOverscroll(
        _appendPageOverscroll + scrollDelta * _elasticFactor,
      );
      widget.onVisibleSceneBoundsChanged?.call(controller.canvasSize);
      return;
    }

    controller.scrollPagedViewportBy(scrollDelta);
    widget.onVisibleSceneBoundsChanged?.call(controller.canvasSize);
  }

  void _endPagedTouch(PointerEvent event) {
    _activeTouchPointers.remove(event.pointer);
    if (_pagedScrollPointer != event.pointer) {
      return;
    }
    _pagedScrollPointer = null;
    if (_appendPageReady) {
      controller.appendPageAfterLastAndScroll();
      _setAppendPageOverscroll(0);
      return;
    }
    _snapBackAppendPageOverscroll();
  }

  void _cancelPagedTouch(PointerEvent event) {
    _activeTouchPointers.remove(event.pointer);
    if (_pagedScrollPointer == event.pointer) {
      _pagedScrollPointer = null;
      _snapBackAppendPageOverscroll();
    }
  }

  double get _elasticFactor {
    final resistance = _appendPageOverscroll / _appendPageMaxOverscroll;
    return (0.62 - resistance * 0.34).clamp(0.24, 0.62).toDouble();
  }

  void _setAppendPageOverscroll(double value, {bool updateController = true}) {
    final next = value.clamp(0.0, _appendPageMaxOverscroll).toDouble();
    final ready = next >= _appendPageReleaseThreshold;
    if ((_appendPageOverscroll - next).abs() < 0.1 &&
        _appendPageReady == ready) {
      return;
    }
    setState(() {
      _appendPageOverscroll = next;
      _appendPageReady = ready;
    });
    if (updateController) {
      _appendPageOverscrollController.value = next;
    }
  }

  void _snapBackAppendPageOverscroll() {
    _appendPageOverscrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  ViewportState _paintViewport() {
    final viewport = controller.editorState.viewport;
    if (_appendPageOverscroll <= 0) {
      return viewport;
    }
    final sceneOverscroll = _appendPageOverscroll / viewport.zoom;
    return ViewportState(
      offset: controller.layout.isRightToLeft
          ? Offset(viewport.offset.dx - sceneOverscroll, viewport.offset.dy)
          : Offset(viewport.offset.dx, viewport.offset.dy + sceneOverscroll),
      zoom: viewport.zoom,
    );
  }

  PagedAppendPageHint? _appendPageHint() {
    if (_appendPageOverscroll <= 0) {
      return null;
    }
    return PagedAppendPageHint(
      overscrollPx: _appendPageOverscroll,
      readyToRelease: _appendPageReady,
      releaseThresholdPx: _appendPageReleaseThreshold,
    );
  }

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

  /// Returns the single selected mind-map node, or null if the selection is
  /// empty, multi, or not a mind-map node. Used to gate the floating + button.
  Element? _singleSelectedMindmapNode(MarkdrawController controller) {
    final selected = controller.selectedElements;
    if (selected.length != 1) return null;
    final node = selected.first;
    return MindmapUtils.isMindmapNode(node) ? node : null;
  }

  List<RemoteCollaboratorOverlay> _buildRemoteCollaborators() {
    return [
      for (final collaborator in widget.collaborators)
        RemoteCollaboratorOverlay(
          socketId: collaborator.socketId,
          username: collaborator.username,
          pointer: collaborator.pointer,
          selectedElementIds: collaborator.selectedElementIds,
          idle: collaborator.idle,
          selectionBounds: [
            for (final id in collaborator.selectedElementIds)
              if (controller.editorState.scene.getElementById(ElementId(id))
                  case final element?)
                ElementSelectionBounds(
                  bounds: Bounds.fromLTWH(
                    element.x,
                    element.y,
                    element.width,
                    element.height,
                  ),
                  angle: element.angle,
                ),
          ],
        ),
    ];
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          runWhenUiStable(() {
            final renderBox = context.findRenderObject() as RenderBox?;
            if (renderBox != null && renderBox.attached) {
              controller.canvasGlobalOffset = renderBox.localToGlobal(
                Offset.zero,
              );
            }
          });
          if (_lastReportedSize != canvasSize) {
            _lastReportedSize = canvasSize;
            runWhenUiStable(() {
              if (mounted) {
                controller.canvasSize = canvasSize;
                widget.onVisibleSceneBoundsChanged?.call(canvasSize);
              }
            });
          }
          final paintViewport = _paintViewport();
          final appendPageHint = _appendPageHint();
          return MouseRegion(
            cursor: controller.cursorForTool,
            child: Stack(
              children: [
                GestureDetector(
                  onScaleStart: (details) => controller.onScaleStart(details),
                  onScaleUpdate: (details) => controller.onScaleUpdate(details),
                  onScaleEnd: controller.onScaleEnd,
                  child: Listener(
                    onPointerHover: (event) {
                      controller.onPointerHover(event.localPosition);
                      widget.onPointerPresence?.call(
                        event.localPosition,
                        false,
                      );
                    },
                    onPointerDown: (event) {
                      if (_shouldHandlePagedTouch(event)) {
                        _startPagedTouch(event);
                        widget.onPointerPresence?.call(
                          event.localPosition,
                          true,
                        );
                        return;
                      }
                      controller.onPointerDown(event);
                      widget.onPointerPresence?.call(event.localPosition, true);
                    },
                    onPointerMove: (event) {
                      if (_isPagedTouchPointer(event)) {
                        _updatePagedTouch(event);
                        widget.onPointerPresence?.call(
                          event.localPosition,
                          true,
                        );
                        return;
                      }
                      controller.onPointerMove(event);
                      widget.onPointerPresence?.call(event.localPosition, true);
                    },
                    onPointerUp: (event) {
                      if (_isPagedTouchPointer(event)) {
                        _endPagedTouch(event);
                        widget.onPointerPresence?.call(
                          event.localPosition,
                          false,
                        );
                        widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                        return;
                      }
                      controller.onPointerUp(event);
                      widget.onPointerPresence?.call(
                        event.localPosition,
                        false,
                      );
                      widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                    },
                    onPointerCancel: (event) {
                      if (_isPagedTouchPointer(event)) {
                        _cancelPagedTouch(event);
                      } else {
                        controller.onPointerCancel(event);
                      }
                      widget.onPointerPresence?.call(
                        event.localPosition,
                        false,
                      );
                    },
                    onPointerSignal: (event) {
                      controller.onPointerSignal(event);
                      widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                    },
                    child: CustomPaint(
                      painter: StaticCanvasPainter(
                        scene: controller.editorState.scene,
                        adapter: controller.adapter,
                        viewport: paintViewport,
                        layout: controller.layout,
                        previewElement: controller.buildPreviewElement(
                          toolOverlay,
                        ),
                        editingElementId: controller.editingTextElementId,
                        resolvedImages: controller.resolveImages(),
                        pendingElements: controller.pendingPreviewElements.isNotEmpty
                            ? controller.pendingPreviewElements
                            : null,
                        gridSize: controller.gridSize,
                        isDarkBackground: _isDark(
                          controller.canvasBackgroundColor,
                        ),
                        contentBounds: controller.contentBounds,
                        appendPageHint: appendPageHint,
                        skipMathText: true,
                      ),
                      foregroundPainter: InteractiveCanvasPainter(
                        viewport: paintViewport,
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
                        creationPoints:
                            toolOverlay?.showCreationPreviewLine ?? false
                            ? toolOverlay?.creationPoints
                            : null,
                        showCreationPreviewLine:
                            toolOverlay?.showCreationPreviewLine ?? false,
                        creationBounds: toolOverlay?.creationBounds,
                        laserTrail: controller.activeTool is LaserTool
                            ? (controller.activeTool as LaserTool).activeTrail
                            : null,
                        linkIcons: _buildLinkIcons(),
                        remoteCollaborators: _buildRemoteCollaborators(),
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
                _MathTextOverlay(
                  controller: controller,
                  viewport: paintViewport,
                ),
                if (controller.editingFrameLabelId != null)
                  _FrameLabelEditingOverlay(controller: controller),
                // Compact property panel trigger
                if (controller.isCompact &&
                    controller.selectedElements.isNotEmpty)
                  Positioned(
                    bottom: 72,
                    right: 12,
                    child: _CompactPropertyButton(controller: controller),
                  ),
                // Mind-map floating + button: shown when a single mind-map
                // node is selected, positioned at the node's right edge.
                if (_singleSelectedMindmapNode(controller) != null)
                  _MindmapAddButtonOverlay(controller: controller),
                _PagedProgressIndicator(controller: controller),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MathTextOverlay extends StatelessWidget {
  const _MathTextOverlay({required this.controller, required this.viewport});

  final MarkdrawController controller;
  final ViewportState viewport;

  @override
  Widget build(BuildContext context) {
    final elements = [
      for (final element in controller.editorState.scene.activeElements)
        if (element is TextElement &&
            MathTextUtils.isMathText(element) &&
            element.id != controller.editingTextElementId)
          element,
    ];
    if (elements.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final element in elements)
            _PositionedMathText(element: element, viewport: viewport),
        ],
      ),
    );
  }
}

class _PositionedMathText extends StatelessWidget {
  const _PositionedMathText({required this.element, required this.viewport});

  final TextElement element;
  final ViewportState viewport;

  @override
  Widget build(BuildContext context) {
    final zoom = viewport.zoom;
    final left = (element.x - viewport.offset.dx) * zoom;
    final top = (element.y - viewport.offset.dy) * zoom;
    final width = element.width * zoom;
    final height = element.height * zoom;
    final color = parseColor(
      element.strokeColor,
    ).withValues(alpha: element.opacity);

    final child = Align(
      alignment: Alignment.topLeft,
      child: Math.tex(
        element.text,
        mathStyle: MathStyle.display,
        textStyle: TextStyle(color: color, fontSize: element.fontSize * zoom),
        onErrorFallback: (_) => Text(
          element.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: element.fontSize * zoom,
            height: element.lineHeight,
            fontFamily: element.fontFamily,
          ),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: element.angle,
        alignment: Alignment.center,
        child: ClipRect(child: child),
      ),
    );
  }
}

/// Checks if a hex background color is dark (luminance < 0.5).
bool _isDark(String hexColor) {
  final c = parseColor(hexColor);
  return c.computeLuminance() < 0.5;
}

class _PagedProgressIndicator extends StatefulWidget {
  final MarkdrawController controller;
  const _PagedProgressIndicator({required this.controller});

  @override
  State<_PagedProgressIndicator> createState() =>
      _PagedProgressIndicatorState();
}

class _PagedProgressIndicatorState extends State<_PagedProgressIndicator> {
  static const double _trackHeight = 168;
  static const double _contentHeight = _trackHeight * 5;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncScrollbar(double progress) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      final target = position.maxScrollExtent * progress;
      if ((position.pixels - target).abs() < 0.5) {
        return;
      }
      _scrollController.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.controller.pagedViewportMetrics;
    if (metrics == null) {
      return const SizedBox.shrink();
    }
    _syncScrollbar(metrics.progress);

    final cs = Theme.of(context).colorScheme;

    final theme = ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(cs.primary.withValues(alpha: 0.72)),
        trackColor: WidgetStatePropertyAll(
          cs.outlineVariant.withValues(alpha: 0.38),
        ),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(999),
      ),
      child: widget.controller.layout.isRightToLeft
          ? SizedBox(
              width: _trackHeight,
              height: 18,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: false,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: const SizedBox(width: _contentHeight, height: 1),
                ),
              ),
            )
          : SizedBox(
              width: 18,
              height: _trackHeight,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: false,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const NeverScrollableScrollPhysics(),
                  child: const SizedBox(width: 1, height: _contentHeight),
                ),
              ),
            ),
    );

    if (widget.controller.layout.isRightToLeft) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 10,
        child: IgnorePointer(child: Center(child: theme)),
      );
    }
    return Positioned(
      right: 10,
      top: 0,
      bottom: 0,
      child: IgnorePointer(child: Center(child: theme)),
    );
  }
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
    runWhenUiStable(() {
      if (mounted && _focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      }
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
          BoxShadow(color: cs.shadow.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 3),
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

/// Floating "+" button anchored to the right edge of the selected mind-map
/// node. Tapping it adds a child node — this is the primary mobile interaction
/// for growing a mind-map, since it bypasses the canvas's single-finger pan
/// gesture interception that would otherwise swallow the touch.
class _MindmapAddButtonOverlay extends StatelessWidget {
  const _MindmapAddButtonOverlay({required this.controller});

  final MarkdrawController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedElements;
    if (selected.length != 1 || !MindmapUtils.isMindmapNode(selected.first)) {
      return const SizedBox.shrink();
    }
    final node = selected.first;
    final viewport = controller.editorState.viewport;
    // Anchor at the node's right edge, vertically centred.
    final rightEdgeScene = Offset(node.x + node.width, node.y + node.height / 2);
    final screen = viewport.sceneToScreen(rightEdgeScene);

    final cs = Theme.of(context).colorScheme;
    const size = 28.0;
    return Positioned(
      left: screen.dx + 6,
      top: screen.dy - size / 2,
      child: Material(
        color: cs.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: controller.mindmapAddChild,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.add, size: 18, color: cs.onPrimary),
          ),
        ),
      ),
    );
  }
}
