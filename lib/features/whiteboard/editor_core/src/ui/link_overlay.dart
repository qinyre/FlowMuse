library;

import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';

import 'markdraw_controller.dart';

/// Floating link editor overlay positioned near the selected element.
///
/// Two modes:
/// - **info**: shows link text (clickable), edit button, remove button
/// - **editor**: shows TextField, "Link to element" button, save/remove buttons
class LinkOverlay extends StatefulWidget {
  const LinkOverlay({
    super.key,
    required this.controller,
    required this.getCanvasSize,
  });

  final MarkdrawController controller;
  final Size Function() getCanvasSize;

  @override
  State<LinkOverlay> createState() => _LinkOverlayState();
}

class _LinkOverlayState extends State<LinkOverlay> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initText();
  }

  @override
  void didUpdateWidget(LinkOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.isLinkEditorEditing !=
        oldWidget.controller.isLinkEditorEditing) {
      _initText();
    }
  }

  void _initText() {
    final elements = widget.controller.selectedElements;
    if (elements.length == 1) {
      _textController.text = elements.first.link ?? '';
    }
    if (widget.controller.isLinkEditorEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
        _textController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _textController.text.length,
        );
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    final elements = widget.controller.selectedElements;
    if (elements.length != 1) return;
    final url = _textController.text.trim();
    widget.controller.setElementLink(
      elements.first.id,
      url.isEmpty ? null : url,
    );
    widget.controller.closeLinkEditor();
    widget.controller.keyboardFocusNode.requestFocus();
  }

  void _remove() {
    final elements = widget.controller.selectedElements;
    if (elements.length != 1) return;
    widget.controller.setElementLink(elements.first.id, null);
    widget.controller.closeLinkEditor();
    widget.controller.keyboardFocusNode.requestFocus();
  }

  void _cancel() {
    widget.controller.closeLinkEditor();
    widget.controller.keyboardFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.controller.linkToElementMode) {
      return _buildStatusMessage(cs, 'Click an element to link to');
    }

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
        }
      },
      child: Container(
        width: 340,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.17),
              blurRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: widget.controller.isLinkEditorEditing
            ? _buildEditorMode(cs)
            : _buildInfoMode(cs),
      ),
    );
  }

  Widget _buildStatusMessage(ColorScheme cs, String message) {
    return Container(
      width: 260,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.17), blurRadius: 1),
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app, size: 16, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: 'Cancel (Esc)',
              onPressed: _cancel,
              icon: Icon(Icons.close, color: cs.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoMode(ColorScheme cs) {
    final elements = widget.controller.selectedElements;
    final link = elements.length == 1 ? elements.first.link : null;
    final displayLink = link ?? '';
    final isElementLink = displayLink.startsWith('#');
    final displayText = isElementLink
        ? 'Element: ${displayLink.substring(1)}'
        : (displayLink.length > 30
              ? '${displayLink.substring(0, 30)}...'
              : displayLink);

    return Row(
      children: [
        Icon(Icons.link, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            onTap: () {
              if (link != null && link.isNotEmpty) {
                widget.controller.followLink(link, widget.getCanvasSize());
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: cs.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 16,
            tooltip: 'Edit link',
            onPressed: () {
              widget.controller.openLinkEditor();
            },
            icon: const Icon(Icons.edit),
          ),
        ),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 16,
            tooltip: 'Remove link',
            onPressed: _remove,
            icon: const Icon(Icons.link_off),
          ),
        ),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 16,
            tooltip: 'Close',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorMode(ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: TextField(
            controller: _textController,
            focusNode: _focusNode,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Link URL',
              hintText: 'https://... or #elementId',
              hintStyle: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 0,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: cs.outline),
              ),
              isDense: true,
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: () {
                  widget.controller.enterLinkToElementMode();
                },
                icon: const Icon(Icons.touch_app, size: 14),
                label: const Text(
                  'Link to element',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
              ),
            ),
            const Spacer(),
            if (_textController.text.isNotEmpty ||
                (widget.controller.selectedElements.length == 1 &&
                    widget.controller.selectedElements.first.link != null))
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  tooltip: 'Remove link',
                  onPressed: _remove,
                  icon: const Icon(Icons.link_off),
                ),
              ),
            const SizedBox(width: 4),
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: _save,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Text('Save', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
