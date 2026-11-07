import 'package:flutter/painting.dart';

/// A safe canvas subset. No network resources, links or embedded HTML.
class CanvasMarkdown {
  static final _block = RegExp(r'^(#{1,6}|[-+*]) +(?=\S)', multiLine: true);
  static final _word = RegExp(r'[A-Za-z0-9_]');
  static final _inline = RegExp(
    r'\\([*_#$\x60\\])|\x60([^\x60\n]+)\x60|\$[^$\n]+\$|\\\([^\n]*?\\\)|\*\*([^*\n]+)\*\*|__([^_\n]+)__|\*([^*\n]+)\*|_([^_\n]+)_',
  );

  static TextSpan span(String source, TextStyle style) {
    if (!_block.hasMatch(source) && !_inline.hasMatch(source)) {
      return TextSpan(text: source, style: style);
    }
    final children = <TextSpan>[];
    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final prefix = _block.firstMatch(line);
      final marker = prefix?.group(1);
      final heading = marker?.startsWith('#') ?? false;
      final lineStyle = heading
          ? style.copyWith(
              fontSize:
                  (style.fontSize ?? 16) *
                  (marker!.length == 1
                      ? 1.55
                      : marker.length == 2
                      ? 1.3
                      : 1.12),
              fontWeight: FontWeight.w700,
            )
          : style;
      if (marker != null && !heading) {
        children.add(const TextSpan(text: '•  '));
      }
      final content = prefix == null ? line : line.substring(prefix.end);
      var start = 0;
      for (final match in _inline.allMatches(content)) {
        if (match.start > start) {
          children.add(
            TextSpan(
              text: content.substring(start, match.start),
              style: lineStyle,
            ),
          );
        }
        final code = match.group(2);
        final bold = match.group(3) ?? match.group(4);
        final italic = match.group(5) ?? match.group(6);
        final insideWord =
            match.group(6) != null &&
            ((match.start > 0 && _word.hasMatch(content[match.start - 1])) ||
                (match.end < content.length &&
                    _word.hasMatch(content[match.end])));
        children.add(
          TextSpan(
            text: insideWord
                ? match[0]
                : match.group(1) ?? code ?? bold ?? italic ?? match[0],
            style: insideWord
                ? lineStyle
                : code != null
                ? lineStyle.copyWith(fontFamily: 'monospace')
                : bold != null
                ? lineStyle.copyWith(fontWeight: FontWeight.w700)
                : italic != null
                ? lineStyle.copyWith(fontStyle: FontStyle.italic)
                : lineStyle,
          ),
        );
        start = match.end;
      }
      children.add(
        TextSpan(
          text:
              content.substring(start) + (index + 1 < lines.length ? '\n' : ''),
          style: lineStyle,
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }
}
