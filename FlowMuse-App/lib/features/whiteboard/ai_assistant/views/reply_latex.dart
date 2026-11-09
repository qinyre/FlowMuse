import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../editor_core/src/core/elements/latex_source.dart';

class ReplyInlineLatex extends md.InlineSyntax {
  ReplyInlineLatex()
    : super(
        r'\\\(([^\r\n]+?)\\\)|\$(?![\s$])((?:\\.|[^$\\\r\n])*?(?:\\.|[^$\s\\]))\$(?![\d$])',
      );

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    if (start > 0 &&
        parser.source[start] == r'$' &&
        parser.source[start - 1] == r'$') {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('reply-math-inline', (match[1] ?? match[2]!).trim())
        ..attributes['source'] = match[0]!,
    );
    return true;
  }
}

class ReplyBlockLatex extends md.BlockSyntax {
  @override
  RegExp get pattern => _opening;

  static final _opening = RegExp(r'^ {0,3}(?:\$\$|\\\[)');

  int? _closingOffset(md.BlockParser parser) {
    final opening = parser.current.content.trim();
    if (opening != r'$$' && opening != r'\[') return null;
    final closing = opening == r'$$' ? r'$$' : r'\]';
    for (var offset = 1; ; offset++) {
      final line = parser.peek(offset)?.content.trim();
      if (line == null || line.isEmpty) return null;
      if (line == closing) return offset > 1 ? offset : null;
      if (_opening.hasMatch(line)) return null;
    }
  }

  @override
  bool canParse(md.BlockParser parser) =>
      super.canParse(parser) &&
      (standaloneLatex(parser.current.content) != null ||
          _closingOffset(parser) != null);

  @override
  md.Node parse(md.BlockParser parser) {
    final closing = _closingOffset(parser) ?? 0;
    final source = [
      for (var i = 0; i <= closing; i++) parser.peek(i)!.content,
    ].join('\n').trim();
    for (var i = 0; i <= closing; i++) {
      parser.advance();
    }
    final latex = standaloneLatex(source);
    if (latex == null) return md.Element.text('p', source);
    return md.Element('p', [
      md.Element.text('reply-math-block', latex)..attributes['source'] = source,
    ]);
  }
}

class ReplyLatexBuilder extends MarkdownElementBuilder {
  ReplyLatexBuilder({this.display = false});

  final bool display;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final style =
        preferredStyle ?? parentStyle ?? Theme.of(context).textTheme.bodyMedium;
    final source = element.attributes['source']!;
    final math = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Math.tex(
        element.textContent,
        mathStyle: display ? MathStyle.display : MathStyle.text,
        textStyle: style,
        onErrorFallback: (_) => Text(source, style: style),
      ),
    );
    if (display) return math;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: math,
          ),
        ],
      ),
    );
  }
}
