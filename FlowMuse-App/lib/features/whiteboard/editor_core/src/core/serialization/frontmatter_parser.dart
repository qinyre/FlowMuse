import 'canvas_settings.dart';
import 'parse_result.dart';

/// The result of parsing frontmatter: extracted settings and remaining content.
class FrontmatterResult {
  final CanvasSettings settings;
  final String remaining;

  FrontmatterResult({required this.settings, required this.remaining});
}

/// Parses YAML-like frontmatter delimited by `---` lines.
class FrontmatterParser {
  static ParseResult<FrontmatterResult> parse(String input) {
    if (input.isEmpty) {
      return ParseResult(
        value: FrontmatterResult(
          settings: const CanvasSettings(),
          remaining: '',
        ),
      );
    }

    final lines = input.split('\n');

    // Check for opening ---
    if (lines.isEmpty || lines.first.trim() != '---') {
      return ParseResult(
        value: FrontmatterResult(
          settings: const CanvasSettings(),
          remaining: input,
        ),
      );
    }

    // Find closing ---
    int closingIndex = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        closingIndex = i;
        break;
      }
    }

    if (closingIndex < 0) {
      // Unclosed frontmatter
      return ParseResult(
        value: FrontmatterResult(
          settings: const CanvasSettings(),
          remaining: input,
        ),
        warnings: [
          const ParseWarning(
            line: 1,
            message: 'Frontmatter unclosed (missing closing ---)',
          ),
        ],
      );
    }

    // Parse key-value pairs
    final warnings = <ParseWarning>[];
    int? formatVersion;
    String? background;
    int? grid;

    for (var i = 1; i < closingIndex; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;

      final key = line.substring(0, colonIdx).trim();
      var value = line.substring(colonIdx + 1).trim();

      // Strip surrounding quotes
      if (value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }

      switch (key) {
        case 'markdraw':
          formatVersion = int.tryParse(value);
        case 'background':
          background = value;
        case 'grid':
          grid = int.tryParse(value);
        default:
          warnings.add(
            ParseWarning(
              line: i + 1,
              message: 'Unknown frontmatter key: $key',
              context: line,
            ),
          );
      }
    }

    // Remaining content after frontmatter
    final remaining = lines.sublist(closingIndex + 1).join('\n');
    // Strip leading newline if present
    final trimmedRemaining = remaining.startsWith('\n')
        ? remaining.substring(1)
        : remaining;

    return ParseResult(
      value: FrontmatterResult(
        settings: CanvasSettings(
          formatVersion: formatVersion ?? 1,
          background: background ?? '#ffffff',
          grid: grid,
        ),
        remaining: trimmedRemaining,
      ),
      warnings: warnings,
    );
  }
}
