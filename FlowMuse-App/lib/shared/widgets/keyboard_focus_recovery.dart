import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Leaves an input with its own keyboard recovery behavior untouched.
class KeyboardFocusRecoveryExclusion extends InheritedWidget {
  const KeyboardFocusRecoveryExclusion({super.key, required super.child});

  static bool isExcluded(BuildContext context) =>
      context
          .getElementForInheritedWidgetOfExactType<
            KeyboardFocusRecoveryExclusion
          >() !=
      null;

  @override
  bool updateShouldNotify(KeyboardFocusRecoveryExclusion oldWidget) => false;
}

/// Lets an editor ignore the brief focus loss used to reopen its keyboard.
class KeyboardFocusRecoveryGuard extends InheritedWidget {
  const KeyboardFocusRecoveryGuard({
    super.key,
    required this.onRecoveryChanged,
    required super.child,
  });

  final ValueChanged<bool> onRecoveryChanged;

  static KeyboardFocusRecoveryGuard? maybeOf(BuildContext context) =>
      context
              .getElementForInheritedWidgetOfExactType<
                KeyboardFocusRecoveryGuard
              >()
              ?.widget
          as KeyboardFocusRecoveryGuard?;

  @override
  bool updateShouldNotify(KeyboardFocusRecoveryGuard oldWidget) => false;
}

/// Rebuilds a focused text input connection after a plain tap.
///
/// Some embedders dismiss the keyboard without clearing Flutter's focus. A
/// fresh focus transition is then needed to reopen the platform connection.
class KeyboardFocusRecovery extends StatefulWidget {
  const KeyboardFocusRecovery({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardFocusRecovery> createState() => _KeyboardFocusRecoveryState();
}

class _PointerDown {
  _PointerDown(this.position, this.timeStamp) {
    _timer = Timer(kLongPressTimeout, () => isLongPress = true);
  }

  final Offset position;
  final Duration timeStamp;
  late final Timer _timer;
  bool isLongPress = false;

  void cancel() => _timer.cancel();
}

class _KeyboardFocusRecoveryState extends State<KeyboardFocusRecovery> {
  final _pointerDowns = <int, _PointerDown>{};
  Timer? _restoreTimer;
  RenderBox? _recoveringBox;
  ValueChanged<bool>? _onRecoveryChanged;

  void _handlePointerDown(PointerDownEvent event) {
    if (_restoreTimer != null && !_contains(_recoveringBox, event.position)) {
      _finishRecovery();
    }
    _pointerDowns[event.pointer]?.cancel();
    _pointerDowns[event.pointer] = _PointerDown(
      event.position,
      event.timeStamp,
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    final down = _pointerDowns.remove(event.pointer);
    if (down == null) return;
    down.cancel();
    if (down.isLongPress ||
        (event.position - down.position).distance > kTouchSlop ||
        event.timeStamp - down.timeStamp >= kLongPressTimeout) {
      return;
    }

    final focus = FocusManager.instance.primaryFocus;
    final focusContext = focus?.context;
    if (focus == null ||
        focusContext == null ||
        KeyboardFocusRecoveryExclusion.isExcluded(focusContext)) {
      return;
    }
    final editable = switch (focusContext) {
      StatefulElement(:final state) when state is EditableTextState => state,
      _ => focusContext.findAncestorStateOfType<EditableTextState>(),
    };
    if (editable == null ||
        editable.widget.focusNode != focus ||
        editable.widget.readOnly) {
      return;
    }
    final box = _inputBox(focusContext, editable);
    if (!_contains(box, event.position)) return;

    // Let TextField.onTap run first. Fields with their own recovery already
    // unfocus here, so they will not receive a second focus reset.
    scheduleMicrotask(() {
      if (!mounted ||
          !editable.mounted ||
          !focus.hasFocus ||
          FocusManager.instance.primaryFocus != focus) {
        return;
      }
      final guard = KeyboardFocusRecoveryGuard.maybeOf(focusContext);
      _onRecoveryChanged = guard?.onRecoveryChanged;
      _onRecoveryChanged?.call(true);
      _recoveringBox = box;
      final scope = focus.nearestScope;
      focus.unfocus();
      _restoreTimer?.cancel();
      _restoreTimer = Timer(const Duration(milliseconds: 50), () {
        _restoreTimer = null;
        if (mounted &&
            focus.canRequestFocus &&
            focus.context != null &&
            (FocusManager.instance.primaryFocus == scope ||
                FocusManager.instance.primaryFocus == focus)) {
          focus.requestFocus();
          // Keep the editor's commit guard until the focus change is applied.
          scheduleMicrotask(_finishRecovery);
        } else {
          _finishRecovery();
        }
      });
    });
  }

  RenderBox? _inputBox(BuildContext context, EditableTextState editable) {
    RenderBox? box;
    context.visitAncestorElements((element) {
      if (element.widget is TextField || element.widget is SearchBar) {
        final renderObject = element.findRenderObject();
        if (renderObject is RenderBox) box = renderObject;
        return false;
      }
      return true;
    });
    return box ?? editable.context.findRenderObject() as RenderBox?;
  }

  bool _contains(RenderBox? box, Offset position) =>
      box != null &&
      box.attached &&
      (Offset.zero & box.size).contains(box.globalToLocal(position));

  void _finishRecovery() {
    _restoreTimer?.cancel();
    _restoreTimer = null;
    _recoveringBox = null;
    final onRecoveryChanged = _onRecoveryChanged;
    _onRecoveryChanged = null;
    onRecoveryChanged?.call(false);
  }

  @override
  void dispose() {
    for (final down in _pointerDowns.values) {
      down.cancel();
    }
    _finishRecovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (event) => _pointerDowns.remove(event.pointer)?.cancel(),
      child: widget.child,
    );
  }
}
