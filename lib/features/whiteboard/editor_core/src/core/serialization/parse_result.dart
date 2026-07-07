/// A warning generated during parsing.
class ParseWarning {
  final int line;
  final String message;
  final String? context;

  const ParseWarning({required this.line, required this.message, this.context});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParseWarning &&
          line == other.line &&
          message == other.message &&
          context == other.context;

  @override
  int get hashCode => Object.hash(line, message, context);

  @override
  String toString() => 'ParseWarning(line $line: $message)';
}

/// Result of a parse operation, containing the parsed value and any warnings.
class ParseResult<T> {
  final T value;
  final List<ParseWarning> warnings;

  ParseResult({required this.value, List<ParseWarning> warnings = const []})
    : warnings = List.unmodifiable(warnings);

  bool get hasWarnings => warnings.isNotEmpty;
}
