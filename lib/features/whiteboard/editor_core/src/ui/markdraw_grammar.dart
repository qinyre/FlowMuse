/// highlight.js [Mode] definition for .markdraw sketch element syntax.
library;

import 'package:re_highlight/re_highlight.dart';

/// highlight.js language mode for .markdraw sketch element lines.
///
/// Used with `re_editor`'s [CodeHighlightTheme] to provide syntax coloring.
final langMarkdraw = Mode(
  name: 'markdraw',
  caseInsensitive: false,
  contains: <Mode>[
    // Comments: # at start of line only (avoid matching hex colors)
    Mode(scope: 'comment', begin: r'^\s*#', end: r'$', relevance: 0),

    // Quoted strings: "Hello World"
    QUOTE_STRING_MODE,

    // Element keywords
    Mode(
      scope: 'keyword',
      begin:
          r'\b(rect|ellipse|diamond|line|arrow|text|freedraw|frame|image)\b(?!-)',
    ),

    // Position keywords
    Mode(scope: 'keyword', begin: r'\b(from|to|at)\b'),

    // Property keys before '='
    Mode(scope: 'attr', begin: r'[a-z][a-z0-9-]*(?==)'),

    // Known property values after '=' (font aliases, named sizes)
    Mode(
      scope: 'string',
      begin:
          r'(?<==)(hand-drawn|normal|code|small|medium|large|extra-large|s|m|l|xl)\b',
    ),

    // Quoted property values: key="value with spaces"
    Mode(scope: 'string', begin: r'(?<==)"', end: r'"'),

    // Hex colors: #RRGGBB (after comment to avoid false match)
    Mode(scope: 'number', begin: r'#[0-9a-fA-F]{3,6}\b'),

    // Dimensions: WxH
    Mode(scope: 'number', begin: r'\b\d+x\d+\b'),

    // Flags
    Mode(
      scope: 'literal',
      begin:
          r'(?<=\s)(locked|closed|rounded|elbowed|no-simulate-pressure)(?=\s|$)',
    ),

    // Numbers (after dimension so WxH is matched first)
    NUMBER_MODE,
  ],
);
