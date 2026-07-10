import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/note_item.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.item, required this.onTap});

  static const coverWidth = 154.0;
  static const coverHeight = 204.0;

  final NoteItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: coverWidth,
          height: coverHeight,
          child: Card(
            elevation: 5,
            shadowColor: const Color(0x165A625F),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              key: ValueKey('note-card-${item.id}'),
              onTap: onTap,
              child: NoteCover(item: item),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                item.title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF222725),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              LucideIcons.chevronDown,
              color: Color(0xFF555C59),
              size: 18,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          item.date,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFFA3AAA6)),
        ),
      ],
    );
  }
}

class NoteCover extends StatelessWidget {
  const NoteCover({super.key, required this.item});

  final NoteItem item;

  @override
  Widget build(BuildContext context) {
    final thumbnailBytes = item.coverThumbnailBytes;
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(color: item.coverColor),
        child: Image.memory(
          thumbnailBytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.expand();
          },
        ),
      );
    }
    return const SizedBox.expand();
  }
}
