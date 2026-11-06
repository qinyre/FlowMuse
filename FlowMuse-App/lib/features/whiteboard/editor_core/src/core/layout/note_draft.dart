enum NoteDraftRole { title, section, paragraph, bullet }

typedef NoteDraftBlock = ({NoteDraftRole role, String text});

/// The small subset shared by the draft preview and the editable canvas page.
List<NoteDraftBlock> parseNoteDraft(String source) {
  final blocks = <NoteDraftBlock>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
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
            block.role == NoteDraftRole.bullet,
      )) {
    throw const FormatException('整理稿需要正文，且最多 100 段');
  }
  if (blocks.first.role != NoteDraftRole.title) {
    blocks.insert(0, (role: NoteDraftRole.title, text: '整理笔记'));
  }
  return List.unmodifiable(blocks);
}
