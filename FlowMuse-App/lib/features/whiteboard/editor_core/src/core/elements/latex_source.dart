/// Returns the body of a single, explicitly delimited LaTeX formula.
String? standaloneLatex(String text) {
  final source = text.trim();
  final (open, close) = switch (source) {
    String() when source.startsWith(r'$$') => (r'$$', r'$$'),
    String() when source.startsWith(r'\[') => (r'\[', r'\]'),
    String() when source.startsWith(r'\(') => (r'\(', r'\)'),
    String() when source.startsWith(r'$') && !source.contains('\n') => (
      r'$',
      r'$',
    ),
    _ => ('', ''),
  };
  if (open.isEmpty ||
      source.length <= open.length + close.length ||
      !source.endsWith(close)) {
    return null;
  }
  final body = source
      .substring(open.length, source.length - close.length)
      .trim();
  return body.isEmpty || body.contains(close) ? null : body;
}
