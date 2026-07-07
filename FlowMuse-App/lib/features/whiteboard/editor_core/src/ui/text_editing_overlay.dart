library;

import 'package:flutter/material.dart' hide Element, SelectionOverlay;

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    as core
    show TextAlign;
import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart'
    hide TextAlign;

/// Delegate for [TextSelectionGestureDetectorBuilder] to enable text
/// selection (tap-to-place-cursor, drag-to-select) on [EditableText].
class TextSelectionDelegate
    extends TextSelectionGestureDetectorBuilderDelegate {
  @override
  final GlobalKey<EditableTextState> editableTextKey;

  TextSelectionDelegate(this.editableTextKey);

  @override
  bool get forcePressEnabled => true;

  @override
  bool get selectionEnabled => true;
}

/// Text editing overlay positioned over the canvas during inline text editing.
class TextEditingOverlay extends StatefulWidget {
  final MarkdrawController controller;

  const TextEditingOverlay({super.key, required this.controller});

  @override
  State<TextEditingOverlay> createState() => _TextEditingOverlayState();
}

class _TextEditingOverlayState extends State<TextEditingOverlay> {
  final _editableTextKey = GlobalKey<EditableTextState>();
  Object? _registration;

  MarkdrawController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _registerEditableText();
  }

  @override
  void didUpdateWidget(covariant TextEditingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_registration case final registration?) {
        oldWidget.controller.unregisterEditableText(registration);
      }
      _registerEditableText();
    }
  }

  @override
  void dispose() {
    if (_registration case final registration?) {
      controller.unregisterEditableText(registration);
    }
    super.dispose();
  }

  void _registerEditableText() {
    _registration = controller.registerEditableText(
      readSelection: () =>
          _editableTextKey.currentState?.textEditingValue.selection,
      restoreSelection: (selection) {
        final editable = _editableTextKey.currentState;
        if (editable == null) {
          return;
        }
        editable.userUpdateTextEditingValue(
          editable.textEditingValue.copyWith(selection: selection),
          SelectionChangedCause.keyboard,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final element = controller.editorState.scene.getElementById(
      controller.editingTextElementId!,
    );
    if (element == null) return const SizedBox.shrink();

    final zoom = controller.editorState.viewport.zoom;
    final textElem = element is TextElement ? element : null;
    final fontSize = (textElem?.fontSize ?? 20.0) * zoom;
    final fontFamily = textElem?.fontFamily ?? 'Excalifont';
    final lineHeight = textElem?.lineHeight ?? 1.25;
    final textColor = parseColor(element.strokeColor);
    final flutterTextAlign = switch (textElem?.textAlign) {
      core.TextAlign.center => TextAlign.center,
      core.TextAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };

    // For bound text, center the editor within the parent shape.
    // Arrow labels position above the arrow midpoint to match rendering.
    if (textElem != null && textElem.containerId != null) {
      final parent = controller.editorState.scene.getElementById(
        ElementId(textElem.containerId!),
      );
      if (parent != null && parent is ArrowElement) {
        return _buildArrowLabelOverlay(
          parent,
          zoom,
          fontSize,
          fontFamily,
          lineHeight,
          textColor,
          flutterTextAlign,
        );
      }
      if (parent != null && parent is! LineElement) {
        return _buildBoundTextOverlay(
          parent,
          textElem,
          zoom,
          fontSize,
          fontFamily,
          lineHeight,
          textColor,
          flutterTextAlign,
        );
      }
    }

    // Fixed-width text
    if (textElem != null && !textElem.autoResize && textElem.width > 0) {
      return _buildFixedWidthTextOverlay(
        element,
        textElem,
        zoom,
        fontSize,
        fontFamily,
        lineHeight,
        textColor,
        flutterTextAlign,
      );
    }

    // Standalone text
    return _buildStandaloneTextOverlay(
      element,
      zoom,
      fontSize,
      fontFamily,
      lineHeight,
      textColor,
      flutterTextAlign,
    );
  }

  Widget _buildBoundTextOverlay(
    Element parent,
    TextElement textElem,
    double zoom,
    double fontSize,
    String fontFamily,
    double lineHeight,
    Color textColor,
    TextAlign flutterTextAlign,
  ) {
    final parentTopLeft = controller.editorState.viewport.sceneToScreen(
      Offset(parent.x, parent.y),
    );
    final parentW = parent.width * zoom;
    final parentH = parent.height * zoom;
    // Match the fixed 5px padding used by _renderShapeLabel in
    // StaticCanvasPainter (boundTextPadding = 5.0).
    // Flutter's RenderEditable subtracts an internal caret margin
    // (_kCaretGap + cursorWidth/2 = 2px) from the text layout width,
    // so we reduce horizontal padding to compensate.
    final pad = 5.0 * zoom;
    final hPad = pad - 2.0;

    return Positioned(
      left: parentTopLeft.dx,
      top: parentTopLeft.dy,
      child: Transform.rotate(
        angle: parent.angle,
        alignment: Alignment.center,
        child: SizedBox(
          width: parentW,
          height: parentH,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: pad),
            child: Align(
              alignment: switch (textElem.verticalAlign) {
                VerticalAlign.top => Alignment.topLeft,
                VerticalAlign.middle => Alignment.centerLeft,
                VerticalAlign.bottom => Alignment.bottomLeft,
              },
              child: SizedBox(
                width: double.infinity,
                child: _buildEditableText(
                  fontSize,
                  fontFamily,
                  lineHeight,
                  textColor,
                  flutterTextAlign,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFixedWidthTextOverlay(
    Element element,
    TextElement textElem,
    double zoom,
    double fontSize,
    String fontFamily,
    double lineHeight,
    Color textColor,
    TextAlign flutterTextAlign,
  ) {
    final topLeftScene = Offset(element.x, element.y);
    final screenTopLeft = controller.editorState.viewport.sceneToScreen(
      topLeftScene,
    );
    final screenW = textElem.width * zoom;
    final screenH = element.height * zoom;
    final centerScene = Offset(
      element.x + element.width / 2,
      element.y + element.height / 2,
    );
    final screenCenter = controller.editorState.viewport.sceneToScreen(
      centerScene,
    );

    return Positioned(
      left: screenTopLeft.dx,
      top: screenTopLeft.dy,
      child: Transform.rotate(
        angle: element.angle,
        origin: Offset(
          screenCenter.dx - screenTopLeft.dx,
          screenCenter.dy - screenTopLeft.dy,
        ),
        child: SizedBox(
          width: screenW,
          height: screenH > 0 ? screenH : null,
          child: Align(
            alignment: switch (textElem.verticalAlign) {
              VerticalAlign.top => Alignment.topLeft,
              VerticalAlign.middle => Alignment.centerLeft,
              VerticalAlign.bottom => Alignment.bottomLeft,
            },
            child: _buildEditableText(
              fontSize,
              fontFamily,
              lineHeight,
              textColor,
              flutterTextAlign,
            ),
          ),
        ),
      ),
    );
  }

  /// Arrow label overlay — centered on the arrow midpoint, matching
  /// [StaticCanvasPainter._renderArrowLabel].
  Widget _buildArrowLabelOverlay(
    ArrowElement arrow,
    double zoom,
    double fontSize,
    String fontFamily,
    double lineHeight,
    Color textColor,
    TextAlign flutterTextAlign,
  ) {
    final mid = ArrowLabelUtils.computeArrowMidpoint(arrow);
    final screenMid = controller.editorState.viewport.sceneToScreen(
      Offset(mid.x, mid.y),
    );

    return Positioned(
      left: screenMid.dx,
      top: screenMid.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IntrinsicWidth(
          child: _buildEditableText(
            fontSize,
            fontFamily,
            lineHeight,
            textColor,
            flutterTextAlign,
          ),
        ),
      ),
    );
  }

  Widget _buildStandaloneTextOverlay(
    Element element,
    double zoom,
    double fontSize,
    String fontFamily,
    double lineHeight,
    Color textColor,
    TextAlign flutterTextAlign,
  ) {
    final centerScene = Offset(
      element.x + element.width / 2,
      element.y + element.height / 2,
    );
    final screenCenter = controller.editorState.viewport.sceneToScreen(
      centerScene,
    );

    return Positioned(
      left: screenCenter.dx,
      top: screenCenter.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: element.angle,
          alignment: Alignment.center,
          child: IntrinsicWidth(
            child: _buildEditableText(
              fontSize,
              fontFamily,
              lineHeight,
              textColor,
              flutterTextAlign,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditableText(
    double fontSize,
    String fontFamily,
    double lineHeight,
    Color textColor,
    TextAlign flutterTextAlign,
  ) {
    return TextSelectionGestureDetectorBuilder(
      delegate: TextSelectionDelegate(_editableTextKey),
    ).buildGestureDetector(
      behavior: HitTestBehavior.translucent,
      child: EditableText(
        key: _editableTextKey,
        rendererIgnoresPointer: true,
        controller: controller.textEditingController,
        focusNode: controller.textFocusNode,
        autofocus: true,
        textAlign: flutterTextAlign,
        style: FontResolver.resolve(
          fontFamily,
          baseStyle: TextStyle(
            fontSize: fontSize,
            color: textColor,
            height: lineHeight,
          ),
        ),
        cursorColor: Colors.blue,
        backgroundCursorColor: Colors.grey,
        selectionColor: Colors.blue.shade300.withValues(alpha: 0.5),
        maxLines: null,
        onChanged: (_) => controller.onTextChanged(),
        onSubmitted: (_) => controller.commitTextEditing(),
      ),
    );
  }
}
