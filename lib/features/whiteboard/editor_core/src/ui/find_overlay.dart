library;

import 'dart:async';

import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';

import 'markdraw_controller.dart';

/// Floating search bar for finding text on the canvas.
///
/// Positioned at the top-center of the editor stack. Supports case-insensitive
/// search of text elements, bound text, and frame labels.
class FindOverlay extends StatefulWidget {
  const FindOverlay({
    super.key,
    required this.controller,
    required this.getCanvasSize,
  });

  final MarkdrawController controller;
  final Size Function() getCanvasSize;

  @override
  State<FindOverlay> createState() => _FindOverlayState();
}

class _FindOverlayState extends State<FindOverlay> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.updateFindQuery(value);
    });
  }

  void _onSubmitted(String _) {
    // Flush any pending debounce
    _debounce?.cancel();
    widget.controller.updateFindQuery(_textController.text);

    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.findPrevious(widget.getCanvasSize());
    } else {
      widget.controller.findNext(widget.getCanvasSize());
    }
  }

  void _close() {
    widget.controller.closeFind();
    widget.controller.keyboardFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final results = widget.controller.findResults;
    final index = widget.controller.findCurrentIndex;
    final query = widget.controller.findQuery;

    String matchLabel;
    if (query.isEmpty) {
      matchLabel = '';
    } else if (results.isEmpty) {
      matchLabel = '0 results';
    } else {
      matchLabel = '${index + 1} of ${results.length}';
    }

    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
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
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Search',
                    hintText: 'Find on canvas',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
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
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                ),
              ),
            ),
            if (matchLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                matchLabel,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Previous (Shift+Enter)',
                onPressed: results.isEmpty
                    ? null
                    : () => widget.controller.findPrevious(
                        widget.getCanvasSize(),
                      ),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
            ),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Next (Enter)',
                onPressed: results.isEmpty
                    ? null
                    : () => widget.controller.findNext(widget.getCanvasSize()),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'Close (Esc)',
                onPressed: _close,
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
