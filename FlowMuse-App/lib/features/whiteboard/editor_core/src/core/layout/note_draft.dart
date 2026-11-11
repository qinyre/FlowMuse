import '../elements/latex_source.dart';

enum NoteDraftRole { title, section, paragraph, bullet, formula }

typedef NoteDraftBlock = ({NoteDraftRole role, String text});

/// The small subset shared by the draft preview and the editable canvas page.
List<NoteDraftBlock> parseNoteDraft(String source) {
  final blocks = <NoteDraftBlock>[];
  final lines = source.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;
    if (standaloneLatex(line) != null) {
      blocks.add((role: NoteDraftRole.formula, text: line));
      continue;
    }
    final closing = switch (line) {
      r'$$' => r'$$',
      r'\[' => r'\]',
      _ => null,
    };
    if (closing != null) {
      final end = lines.indexWhere((part) => part.trim() == closing, index + 1);
      if (end > index) {
        final formula = lines.sublist(index, end + 1).join('\n').trim();
        if (standaloneLatex(formula) != null) {
          blocks.add((role: NoteDraftRole.formula, text: formula));
          index = end;
          continue;
        }
      }
    }
    final (role, prefix) = switch (line) {
      String() when line.startsWith('# ') && blocks.isEmpty => (
        NoteDraftRole.title,
        2,
      ),
      String() when line.startsWith('## ') => (NoteDraftRole.section, 3),
      String() when line.startsWith('- ') => (NoteDraftRole.bullet, 2),
      _ => (NoteDraftRole.paragraph, 0),
    };
    final text = line.substring(prefix).trim();
    if (text.isNotEmpty) blocks.add((role: role, text: text));
  }
  if (blocks.length > 100 ||
      !blocks.any(
        (block) =>
            block.role == NoteDraftRole.paragraph ||
            block.role == NoteDraftRole.bullet ||
            block.role == NoteDraftRole.formula,
      )) {
    throw const FormatException('整理稿需要正文，且最多 100 段');
  }
  if (blocks.first.role != NoteDraftRole.title) {
    blocks.insert(0, (role: NoteDraftRole.title, text: '整理笔记'));
  }
  return List.unmodifiable(blocks);
}
