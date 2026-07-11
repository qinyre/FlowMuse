import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/note_item.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onActionsTap,
  });

  static const coverWidth = 132.0;
  static const coverHeight = 176.0;
  static const gridMaxCrossAxisExtent = 192.0;
  static const gridMainAxisExtent = 251.0;
  static const compactGridCrossGap = 16.0;
  static const gridCrossGap = 22.0;
  static const compactGridMainGap = 20.0;
  static const gridMainGap = 26.0;

  final NoteItem item;
  final VoidCallback onTap;
  final void Function(BuildContext context)? onActionsTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: coverWidth,
          height: coverHeight,
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            shadowColor: const Color(0x0F5A625F),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
            child: InkWell(
              key: ValueKey('note-card-${item.id}'),
              onTap: onTap,
              onLongPress: onActionsTap != null
                  ? () => onActionsTap!(context)
                  : null,
              child: NoteCover(item: item),
            ),
          ),
        ),
        const SizedBox(height: 13),
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
                  fontSize: 14,
                ),
              ),
            ),
            if (onActionsTap != null)
              GestureDetector(
                onTap: () => onActionsTap!(context),
                child: const Icon(
                  LucideIcons.chevronDown,
                  color: Color(0xFF555C59),
                  size: 16,
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
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
