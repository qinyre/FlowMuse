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
      final text = block.text.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      if (block.type == 'heading') {
        buffer.writeln('# $text');
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
      final text = block.text.trim();
      if (text.isEmpty) continue;
      if (block.type == 'heading') {
        buffer.writeln('\\section*{${_escapeLatex(text)}}');
      } else if (block.type == 'math') {
        buffer.writeln(r'\[');
        buffer.writeln(
          block.latex?.trim().isNotEmpty == true
              ? block.latex!.trim()
              : _escapeLatex(text),
        );
        buffer.writeln(r'\]');
      } else {
        buffer.writeln(_escapeLatex(text));
        buffer.writeln();
      }
    }
    buffer.writeln(r'\end{document}');
    return buffer.toString();
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
