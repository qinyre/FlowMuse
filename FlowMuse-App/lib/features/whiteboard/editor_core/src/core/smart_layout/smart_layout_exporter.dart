import 'smart_layout_document.dart';

class SmartLayoutExporter {
  const SmartLayoutExporter._();

  static String export(
    SmartLayoutDocument document,
    SmartLayoutExportFormat format,
  ) {
    final blocks = [...document.blocks]
      ..sort((a, b) => a.order.compareTo(b.order));
    return switch (format) {
      SmartLayoutExportFormat.markdown => _markdown(blocks),
      SmartLayoutExportFormat.latex => _latex(blocks),
    };
  }

  static String _markdown(List<SmartLayoutBlock> blocks) {
    final buffer = StringBuffer();
    for (final block in blocks) {
      final text = _trimDocumentText(block.text);
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      if (block.type == 'heading') {
        buffer.writeln('# ${text.trim()}');
      } else if (block.type == 'math') {
        buffer.writeln(r'$$');
        buffer.writeln(
          block.latex?.trim().isNotEmpty == true ? block.latex!.trim() : text,
        );
        buffer.writeln(r'$$');
      } else {
        buffer.writeln(text);
      }
    }
    return buffer.toString();
  }

  static String _latex(List<SmartLayoutBlock> blocks) {
    final buffer = StringBuffer()
      ..writeln(r'\documentclass{article}')
      ..writeln(r'\usepackage{amsmath}')
      ..writeln(r'\usepackage[UTF8]{ctex}')
      ..writeln(r'\begin{document}');
    for (final block in blocks) {
      final text = _trimDocumentText(block.text);
      if (text.isEmpty) continue;
      if (block.type == 'heading') {
        buffer.writeln('\\section*{${_escapeLatex(text.trim())}}');
      } else if (block.type == 'math') {
        buffer.writeln(r'\[');
        buffer.writeln(
          block.latex?.trim().isNotEmpty == true
              ? block.latex!.trim()
              : _escapeLatex(text),
        );
        buffer.writeln(r'\]');
      } else {
        _writeLatexLayoutText(buffer, text);
      }
    }
    buffer.writeln(r'\end{document}');
    return buffer.toString();
  }

  static String _trimDocumentText(String value) {
    var text = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    while (text.startsWith('\n')) {
      text = text.substring(1);
    }
    return text.replaceFirst(RegExp(r'[ \t\n]+$'), '');
  }

  static void _writeLatexLayoutText(StringBuffer buffer, String text) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        buffer.writeln(r'\par');
        continue;
      }
      final indent = line.length - line.trimLeft().length;
      final content = line.trimLeft();
      if (indent > 0) {
        buffer.write('\\hspace*{${(indent * 0.5).toStringAsFixed(1)}em}');
      }
      buffer.write(_escapeLatex(content));
      if (i < lines.length - 1) {
        buffer.writeln(r'\\');
      } else {
        buffer.writeln();
      }
    }
    buffer.writeln();
  }

  static String _escapeLatex(String value) {
    return value
        .replaceAll(r'\', r'\textbackslash{}')
        .replaceAll('&', r'\&')
        .replaceAll('%', r'\%')
        .replaceAll(r'$', r'\$')
        .replaceAll('#', r'\#')
        .replaceAll('_', r'\_')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}');
  }
}
