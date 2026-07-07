library;

import 'package:flutter/material.dart' hide Element;
import 'package:flutter/services.dart';

import 'package:flow_muse/features/whiteboard/editor_core/flow_muse_whiteboard_editor.dart' hide TextAlign;

/// Builds shortcut bindings for system-level shortcuts (Cmd+S, Cmd+O, etc.)
/// that macOS intercepts before KeyEvent reaches Flutter.
Map<ShortcutActivator, VoidCallback> buildShortcutBindings({
  required VoidCallback onSave,
  required VoidCallback onSaveAs,
  required VoidCallback onOpen,
  required VoidCallback onUndo,
  required VoidCallback onRedo,
  required VoidCallback onExportPng,
  required VoidCallback onZoomIn,
  required VoidCallback onZoomOut,
  required VoidCallback onResetZoom,
  required VoidCallback onFind,
}) {
  return {
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
        onSaveAs,
    const SingleActivator(LogicalKeyboardKey.keyO, meta: true): onOpen,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): onUndo,
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
        onRedo,
    const SingleActivator(LogicalKeyboardKey.keyE, meta: true, shift: true):
        onExportPng,
    const SingleActivator(LogicalKeyboardKey.keyY, meta: true): onRedo,
    // Ctrl variants for non-macOS platforms
    const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
    const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
        onSaveAs,
    const SingleActivator(LogicalKeyboardKey.keyO, control: true): onOpen,
    const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true):
        onExportPng,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): onUndo,
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
        onRedo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): onRedo,
    // Zoom shortcuts — meta (macOS)
    const SingleActivator(LogicalKeyboardKey.equal, meta: true): onZoomIn,
    const SingleActivator(LogicalKeyboardKey.minus, meta: true): onZoomOut,
    const SingleActivator(LogicalKeyboardKey.digit0, meta: true): onResetZoom,
    // Zoom shortcuts — ctrl
    const SingleActivator(LogicalKeyboardKey.equal, control: true): onZoomIn,
    const SingleActivator(LogicalKeyboardKey.minus, control: true): onZoomOut,
    const SingleActivator(LogicalKeyboardKey.digit0, control: true):
        onResetZoom,
    // Find: Cmd/Ctrl+F
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onFind,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true): onFind,
    // Grid toggle is handled in handleKeyEvent — not here, because Cmd+'
    // is NOT intercepted by macOS (unlike Cmd+S/Z) and would double-fire.
  };
}

/// Handles key events dispatched to the editor.
bool handleKeyEvent({
  required KeyEvent event,
  required MarkdrawController controller,
  required Size Function() getCanvasSize,
  required VoidCallback onSave,
  required VoidCallback onSaveAs,
  required VoidCallback onOpen,
  required VoidCallback onExportPng,
  required VoidCallback onImportImage,
  required void Function(ThemeMode) onThemeToggle,
  required ThemeMode Function() getCurrentThemeMode,
  required BuildContext context,
  void Function(Element element)? onShowLinkDialog,
}) {
  // Don't intercept keys while editing text
  if (controller.editingTextElementId != null) return false;

  // Handle key-up events for flowchart commit/navigate end
  if (event is KeyUpEvent) {
    if (_isCtrlOrMeta(event.logicalKey)) {
      if (controller.flowchartCreator.isCreating) {
        controller.flowchartCommit();
        return true;
      }
    }
    if (_isAlt(event.logicalKey)) {
      controller.flowchartNavigateEnd();
    }
    return false;
  }

  if (event is! KeyDownEvent) return false;
  final key = event.logicalKey;
  final shift = HardwareKeyboard.instance.isShiftPressed;
  final ctrl =
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  final alt = HardwareKeyboard.instance.isAltPressed;

  // Zen mode: Alt+Z
  if (alt && !ctrl && !shift && key == LogicalKeyboardKey.keyZ) {
    controller.toggleZenMode();
    return true;
  }

  // View mode: Alt+R
  if (alt && !ctrl && !shift && key == LogicalKeyboardKey.keyR) {
    controller.toggleViewMode();
    return true;
  }

  // Snap to objects: Alt+S
  if (alt && !ctrl && !shift && key == LogicalKeyboardKey.keyS) {
    controller.toggleObjectsSnapMode();
    return true;
  }

  // Find on canvas: Ctrl+F
  if (ctrl && !shift && key == LogicalKeyboardKey.keyF) {
    controller.openFind();
    return true;
  }

  // Escape closes find bar
  if (key == LogicalKeyboardKey.escape && controller.isFindOpen) {
    controller.closeFind();
    return true;
  }

  // Block tool shortcuts when in view mode (except hand tool)
  if (controller.viewMode) return false;

  // Escape cancels flowchart creation
  if (key == LogicalKeyboardKey.escape &&
      controller.flowchartCreator.isCreating) {
    controller.flowchartCancel();
    return true;
  }

  // Flowchart creation: Ctrl+Arrow (single flowchart node selected)
  if (ctrl && !shift && !alt && _isArrowKey(key)) {
    if (controller.selectedElements.length == 1 &&
        FlowchartUtils.isFlowchartNode(controller.selectedElements.first)) {
      controller.flowchartCreate(_arrowToDirection(key));
      return true;
    }
  }

  // Flowchart navigation: Alt+Arrow
  if (alt && !ctrl && !shift && _isArrowKey(key)) {
    if (controller.selectedElements.length == 1) {
      controller.flowchartNavigate(_arrowToDirection(key));
      return true;
    }
  }

  // Page scrolling: PgDn/PgUp pans viewport by canvas height (Shift for horizontal)
  if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp) {
    final size = getCanvasSize();
    final down = key == LogicalKeyboardKey.pageDown;
    if (shift) {
      controller.panViewport(
        down
            ? size.width / controller.editorState.viewport.zoom
            : -size.width / controller.editorState.viewport.zoom,
        0,
      );
    } else {
      controller.panViewport(
        0,
        down
            ? size.height / controller.editorState.viewport.zoom
            : -size.height / controller.editorState.viewport.zoom,
      );
    }
    return true;
  }

  // Reset canvas: Ctrl+Delete
  if (ctrl && !shift && key == LogicalKeyboardKey.delete) {
    controller.resetCanvas();
    return true;
  }

  // Font size cycling: Ctrl+Shift+< / Ctrl+Shift+>
  if (ctrl &&
      shift &&
      (key == LogicalKeyboardKey.comma ||
          key == LogicalKeyboardKey.period ||
          key == LogicalKeyboardKey.less ||
          key == LogicalKeyboardKey.greater)) {
    final increase =
        key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.greater;
    controller.cycleFontSize(increase: increase);
    return true;
  }

  // Copy as PNG: Shift+Alt+C
  if (shift && alt && !ctrl && key == LogicalKeyboardKey.keyC) {
    controller.copyAsPng();
    return true;
  }

  // Copy/paste styles: Ctrl+Alt+C / Ctrl+Alt+V (before regular Ctrl+C/V)
  if (ctrl && alt && !shift && key == LogicalKeyboardKey.keyC) {
    controller.copyStyle();
    return true;
  }
  if (ctrl && alt && !shift && key == LogicalKeyboardKey.keyV) {
    controller.pasteStyle();
    return true;
  }

  // Paste as plaintext: Ctrl+Shift+V
  if (ctrl && shift && key == LogicalKeyboardKey.keyV) {
    controller.pasteAsPlaintext(getCanvasSize());
    return true;
  }

  // Undo/redo
  if (ctrl && key == LogicalKeyboardKey.keyZ) {
    if (shift) {
      controller.redo();
    } else {
      controller.undo();
    }
    return true;
  }
  if (ctrl && key == LogicalKeyboardKey.keyY) {
    controller.redo();
    return true;
  }

  // File shortcuts
  if (ctrl && key == LogicalKeyboardKey.keyS) {
    if (shift) {
      onSaveAs();
    } else {
      onSave();
    }
    return true;
  }
  if (ctrl && key == LogicalKeyboardKey.keyO) {
    onOpen();
    return true;
  }

  // Zoom shortcuts
  if (ctrl && key == LogicalKeyboardKey.equal) {
    controller.zoomIn(getCanvasSize());
    return true;
  }
  if (ctrl && key == LogicalKeyboardKey.minus) {
    controller.zoomOut(getCanvasSize());
    return true;
  }
  if (ctrl && key == LogicalKeyboardKey.digit0) {
    controller.resetZoom();
    return true;
  }

  // Link shortcut
  if (ctrl && !shift && key == LogicalKeyboardKey.keyK) {
    final elements = controller.selectedElements;
    if (elements.length == 1 && onShowLinkDialog != null) {
      onShowLinkDialog(elements.first);
    }
    return true;
  }

  // Grid toggle: Ctrl/Cmd+' (matches Excalidraw which uses event.code)
  if (ctrl &&
      (key == LogicalKeyboardKey.quoteSingle ||
          key == LogicalKeyboardKey.quote ||
          event.physicalKey == PhysicalKeyboardKey.quote)) {
    controller.toggleGrid();
    return true;
  }

  // Alt+Shift+D: toggle theme
  if (alt && shift && key == LogicalKeyboardKey.keyD) {
    final current = getCurrentThemeMode();
    onThemeToggle(switch (current) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.dark,
    });
    return true;
  }

  // Shift+1: zoom to fit, Shift+2: zoom to selection
  if (!ctrl && shift) {
    if (key == LogicalKeyboardKey.digit1) {
      controller.zoomToFit(getCanvasSize());
      return true;
    }
    if (key == LogicalKeyboardKey.digit2) {
      controller.zoomToSelection(getCanvasSize());
      return true;
    }
  }

  // ? key opens help dialog
  if (!ctrl && key.keyLabel == '?') {
    showHelpDialog(context);
    return true;
  }

  // Tool lock toggle (Q)
  if (!ctrl && !shift && key == LogicalKeyboardKey.keyQ) {
    controller.toggleToolLocked();
    return true;
  }

  // Color picker shortcuts: S (stroke), G (background) — select tool only
  if (!ctrl &&
      !shift &&
      !alt &&
      controller.editorState.activeToolType == ToolType.select) {
    if (key == LogicalKeyboardKey.keyS) {
      controller.requestColorPicker(ColorPickerTarget.stroke);
      return true;
    }
    if (key == LogicalKeyboardKey.keyG) {
      controller.requestColorPicker(ColorPickerTarget.background);
      return true;
    }
  }

  // Font picker shortcut: Shift+F — select tool only
  if (!ctrl &&
      shift &&
      !alt &&
      controller.editorState.activeToolType == ToolType.select &&
      key == LogicalKeyboardKey.keyF) {
    controller.requestColorPicker(ColorPickerTarget.font);
    return true;
  }

  // Tool shortcuts (no modifier keys)
  if (!ctrl && !shift) {
    final label = key.keyLabel;
    if (label.length == 1) {
      if (label == '9') {
        onImportImage();
        return true;
      }
      final toolType = toolTypeForKey(label.toLowerCase());
      if (toolType != null) {
        controller.switchTool(toolType);
        return true;
      }
    }
  }

  // Escape exits linear editing mode
  if (key == LogicalKeyboardKey.escape && controller.isEditingLinear) {
    controller.isEditingLinear = false;
    return true;
  }

  // Pass to tool
  String? keyName;
  if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
    keyName = key == LogicalKeyboardKey.delete ? 'Delete' : 'Backspace';
  } else if (key == LogicalKeyboardKey.escape) {
    keyName = 'Escape';
  } else if (key == LogicalKeyboardKey.enter) {
    keyName = 'Enter';
  } else if (key == LogicalKeyboardKey.arrowLeft) {
    keyName = 'ArrowLeft';
  } else if (key == LogicalKeyboardKey.arrowRight) {
    keyName = 'ArrowRight';
  } else if (key == LogicalKeyboardKey.arrowUp) {
    keyName = 'ArrowUp';
  } else if (key == LogicalKeyboardKey.arrowDown) {
    keyName = 'ArrowDown';
  } else if (key == LogicalKeyboardKey.tab) {
    keyName = 'Tab';
  } else if (key.keyLabel.length == 1) {
    keyName = key.keyLabel.toLowerCase();
  }

  if (keyName != null) {
    final result = controller.activeTool.onKeyEvent(
      keyName,
      shift: shift,
      ctrl: ctrl,
      context: controller.toolContext,
    );
    if (isSceneChangingResult(result)) {
      controller.historyManager.push(controller.editorState.scene);
    }
    controller.applyResult(result);
    return result != null;
  }

  return false;
}

bool _isArrowKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.arrowUp ||
    key == LogicalKeyboardKey.arrowDown ||
    key == LogicalKeyboardKey.arrowLeft ||
    key == LogicalKeyboardKey.arrowRight;

LinkDirection _arrowToDirection(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return LinkDirection.up;
  if (key == LogicalKeyboardKey.arrowDown) return LinkDirection.down;
  if (key == LogicalKeyboardKey.arrowLeft) return LinkDirection.left;
  return LinkDirection.right;
}

bool _isCtrlOrMeta(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.controlLeft ||
    key == LogicalKeyboardKey.controlRight ||
    key == LogicalKeyboardKey.metaLeft ||
    key == LogicalKeyboardKey.metaRight;

bool _isAlt(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
