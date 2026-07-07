import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Abstraction for system clipboard access.
///
/// Allows mocking in tests and provides a single point of control
/// for clipboard I/O across platforms.
abstract class ClipboardService {
  /// Copies [text] to the system clipboard.
  Future<void> copyText(String text);

  /// Reads text from the system clipboard, or null if unavailable.
  Future<String?> readText();

  /// Copies a PNG image to the system clipboard.
  Future<void> copyImage(Uint8List pngBytes);
}

/// Default implementation using Flutter's [Clipboard] API for text
/// and `super_clipboard` for binary formats (e.g. PNG).
class FlutterClipboardService implements ClipboardService {
  const FlutterClipboardService();

  @override
  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> copyImage(Uint8List pngBytes) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem(suggestedName: 'drawing.png');
    item.add(Formats.png(pngBytes));
    await clipboard.write([item]);
  }
}
