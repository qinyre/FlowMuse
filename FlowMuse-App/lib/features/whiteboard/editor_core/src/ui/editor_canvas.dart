library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';

import 'pointer_pressure.dart';

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
  static const double _lastPagePromptRevealDistance = 56;
  static const double _lastPageCreateDistance = 112;

  MarkdrawController get controller => widget.controller;
  Size? _lastReportedSize;
  final Set<int> _activeTouchPointers = {};
  int? _pagedScrollPointer;
  double _lastPagePullDistance = 0;
  bool _lastPagePromptArmed = false;
  bool _gestureStartedWithPromptArmed = false;
  bool _createdPageDuringGesture = false;
  Timer? _lastPagePromptResetTimer;
  late final AnimationController _lastPagePromptController;

  @override
  void initState() {
    super.initState();
    _lastPagePromptController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _lastPagePromptResetTimer?.cancel();
    _lastPagePromptController.dispose();
    super.dispose();
  }

  bool _shouldHandlePagedTouch(PointerEvent event) {
    return controller.isPagedViewport &&
        event.kind == PointerDeviceKind.touch &&
        (controller.viewMode ||
            controller.editorState.activeToolType == ToolType.hand);
  }

  void _startPagedTouch(PointerDownEvent event) {
    _activeTouchPointers.add(event.pointer);
    if (_activeTouchPointers.length == 1) {
      _pagedScrollPointer = event.pointer;
      _lastPagePullDistance = 0;
      _gestureStartedWithPromptArmed = _lastPagePromptArmed;
      _createdPageDuringGesture = false;
    } else {
      _pagedScrollPointer = null;
      _lastPagePullDistance = 0;
    }
  }

  void _updatePagedTouch(PointerMoveEvent event) {
    if (_pagedScrollPointer != event.pointer ||
        _activeTouchPointers.length != 1) {
      return;
    }

    final scrollDeltaY = -event.delta.dy;
    if (scrollDeltaY == 0) {
      return;
    }

    controller.scrollPagedViewportBy(scrollDeltaY);
    widget.onVisibleSceneBoundsChanged?.call(controller.canvasSize);

    final metrics = controller.pagedViewportMetrics;
    if (metrics == null || !metrics.atEnd || scrollDeltaY <= 0) {
      if (!_lastPagePromptArmed) {
        _setLastPagePromptProgress(0);
      }
      return;
    }

    _lastPagePullDistance += scrollDeltaY;
    if (_gestureStartedWithPromptArmed &&
        !_createdPageDuringGesture &&
        _lastPagePullDistance >= _lastPageCreateDistance) {
      _createdPageDuringGesture = true;
      controller.appendPageAfterLastAndScroll();
      _clearLastPagePrompt();
      return;
    }

    final progress = (_lastPagePullDistance / _lastPagePromptRevealDistance)
        .clamp(0.0, 1.0)
        .toDouble();
    _setLastPagePromptProgress(progress);
    if (progress >= 1) {
      _setLastPagePromptArmed(true);
      _lastPagePromptController.forward();
    }
  }

  void _endPagedTouch(PointerEvent event) {
    _activeTouchPointers.remove(event.pointer);
    if (_pagedScrollPointer != event.pointer) {
      return;
    }
    _pagedScrollPointer = null;
    if (_createdPageDuringGesture) {
      _lastPagePullDistance = 0;
      return;
    }
    if (_lastPagePromptArmed) {
      _lastPagePromptController.forward();
      _lastPagePromptResetTimer?.cancel();
      _lastPagePromptResetTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted && _activeTouchPointers.isEmpty) {
          _clearLastPagePrompt();
        }
      });
    } else {
      _clearLastPagePrompt();
    }
    _lastPagePullDistance = 0;
  }

  void _setLastPagePromptProgress(double value) {
    _lastPagePromptResetTimer?.cancel();
    final nextValue = value.clamp(0.0, 1.0).toDouble();
    if ((_lastPagePromptController.value - nextValue).abs() < 0.01) {
      return;
    }
    _lastPagePromptController.value = nextValue;
  }

  void _setLastPagePromptArmed(bool value) {
    if (_lastPagePromptArmed == value) {
      return;
    }
    if (!mounted) {
      _lastPagePromptArmed = value;
      return;
    }
    setState(() {
      _lastPagePromptArmed = value;
    });
  }

  void _clearLastPagePrompt() {
    _lastPagePromptResetTimer?.cancel();
    _setLastPagePromptArmed(false);
    _gestureStartedWithPromptArmed = false;
    _lastPagePullDistance = 0;
    _lastPagePromptController.reverse();
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
          if (_lastReportedSize != canvasSize) {
            _lastReportedSize = canvasSize;
            runWhenUiStable(() {
              if (mounted) {
                controller.canvasSize = canvasSize;
                widget.onVisibleSceneBoundsChanged?.call(canvasSize);
              }
            });
          }
          return MouseRegion(
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
                      controller.onPointerDown(
                        event.localPosition,
                        kind: event.kind,
                        pressure: reliableStylusPressure(
                          kind: event.kind,
                          pressure: event.pressure,
                          pressureMin: event.pressureMin,
                          pressureMax: event.pressureMax,
                        ),
                      );
                      widget.onPointerPresence?.call(event.localPosition, true);
                    },
                    onPointerMove: (event) {
                      if (_shouldHandlePagedTouch(event)) {
                        _updatePagedTouch(event);
                        widget.onPointerPresence?.call(
                          event.localPosition,
                          true,
                        );
                        return;
                      }
                      controller.onPointerMove(
                        event.localPosition,
                        event.delta,
                        kind: event.kind,
                        pressure: reliableStylusPressure(
                          kind: event.kind,
                          pressure: event.pressure,
                          pressureMin: event.pressureMin,
                          pressureMax: event.pressureMax,
                        ),
                      );
                      widget.onPointerPresence?.call(event.localPosition, true);
                    },
                    onPointerUp: (event) {
                      if (_shouldHandlePagedTouch(event)) {
                        _endPagedTouch(event);
                        widget.onPointerPresence?.call(
                          event.localPosition,
                          false,
                        );
                        widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                        return;
                      }
                      controller.onPointerUp(
                        event.localPosition,
                        kind: event.kind,
                        pressure: reliableStylusPressure(
                          kind: event.kind,
                          pressure: event.pressure,
                          pressureMin: event.pressureMin,
                          pressureMax: event.pressureMax,
                        ),
                      );
                      widget.onPointerPresence?.call(
                        event.localPosition,
                        false,
                      );
                      widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                    },
                    onPointerCancel: (event) {
                      if (_shouldHandlePagedTouch(event)) {
                        _endPagedTouch(event);
                      }
                    },
                    onPointerSignal: (event) {
                      controller.onPointerSignal(event);
                      widget.onVisibleSceneBoundsChanged?.call(canvasSize);
                    },
                    child: CustomPaint(
                      painter: StaticCanvasPainter(
                        scene: controller.editorState.scene,
                        adapter: controller.adapter,
                        viewport: controller.editorState.viewport,
                        layout: controller.layout,
                        previewElement: controller.buildPreviewElement(
                          toolOverlay,
                        ),
                        editingElementId: controller.editingTextElementId,
                        resolvedImages: controller.resolveImages(),
                        pendingElements: controller.flowchartCreator.isCreating
                            ? controller.flowchartCreator.pendingElements
                            : null,
                        gridSize: controller.gridSize,
                        isDarkBackground: _isDark(
                          controller.canvasBackgroundColor,
                        ),
                        contentBounds: controller.contentBounds,
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
                _PagedProgressIndicator(controller: controller),
                _LastPagePullPrompt(
                  controller: _lastPagePromptController,
                  armed: _lastPagePromptArmed,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Checks if a hex background color is dark (luminance < 0.5).
bool _isDark(String hexColor) {
  final c = parseColor(hexColor);
  return c.computeLuminance() < 0.5;
}

class _PagedProgressIndicator extends StatelessWidget {
  final MarkdrawController controller;
  const _PagedProgressIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    final metrics = controller.pagedViewportMetrics;
    if (metrics == null) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    const trackHeight = 168.0;
    const trackWidth = 4.0;
    const thumbHeight = 34.0;
    final thumbTop = (trackHeight - thumbHeight) * metrics.progress;

    return Positioned(
      right: 10,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: SizedBox(
            width: 18,
            height: trackHeight,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned.fill(
                  left: 7,
                  right: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(trackWidth / 2),
                    ),
                  ),
                ),
                Positioned(
                  top: thumbTop,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(trackWidth / 2),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.24),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const SizedBox(
                      width: trackWidth,
                      height: thumbHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastPagePullPrompt extends StatelessWidget {
  final Animation<double> controller;
  final bool armed;

  const _LastPagePullPrompt({required this.controller, required this.armed});

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 28,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final value = controller.value;
            if (value <= 0) {
              return const SizedBox.shrink();
            }
            final content = Opacity(
              opacity: value,
              child: Transform.translate(
                offset: reduceMotion
                    ? Offset.zero
                    : Offset(0, 18 * (1 - value)),
                child: child,
              ),
            );
            return Center(child: content);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.94),
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    armed ? Icons.add_box_outlined : Icons.post_add_outlined,
                    size: 20,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    armed ? '再次下拉，新建一页' : '继续下拉，准备新建页面',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
