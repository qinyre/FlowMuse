import 'tool_type.dart';

/// Returns the [ToolType] mapped to the given single-character [key],
/// or `null` if the key is not a tool shortcut.
///
/// Number keys 1–8 map to tools in toolbar order (matching Excalidraw).
/// Letter keys F and H map to frame and hand tools (matching Excalidraw).
/// Key 9 is reserved for image (not yet implemented).
/// Only fires when no modifier keys (Ctrl/Shift) are held.
ToolType? toolTypeForKey(String key) {
  return switch (key) {
    '1' || 'v' => ToolType.select,
    '2' || 'r' => ToolType.rectangle,
    '3' || 'd' => ToolType.diamond,
    '4' || 'o' => ToolType.ellipse,
    '5' || 'a' => ToolType.arrow,
    '6' || 'l' => ToolType.line,
    '7' || 'p' => ToolType.freedraw,
    '8' || 't' => ToolType.text,
    'f' => ToolType.frame,
    'h' => ToolType.hand,
    '0' || 'e' => ToolType.eraser,
    'k' => ToolType.laser,
    _ => null,
  };
}

/// Returns the keyboard shortcut label for the given [ToolType],
/// or `null` if no shortcut is assigned.
String? shortcutForToolType(ToolType type) {
  return switch (type) {
    ToolType.select => '1',
    ToolType.rectangle => '2',
    ToolType.diamond => '3',
    ToolType.ellipse => '4',
    ToolType.arrow => '5',
    ToolType.line => '6',
    ToolType.freedraw => '7',
    ToolType.text => '8',
    ToolType.frame => 'F',
    ToolType.hand => 'H',
    ToolType.eraser => '0',
    ToolType.laser => 'K',
  };
}
