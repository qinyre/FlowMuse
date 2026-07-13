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
    final colorScheme = Theme.of(context).colorScheme;
    final actionsKey = GlobalKey();

    void showActions() {
      final actionsContext = actionsKey.currentContext;
      if (actionsContext != null) {
        onActionsTap!(actionsContext);
      }
    }

    return Column(
      children: [
        SizedBox(
          width: coverWidth,
          height: coverHeight,
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 1,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.06),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
            child: InkWell(
              key: ValueKey('note-card-${item.id}'),
              onTap: onTap,
              onLongPress: onActionsTap != null ? showActions : null,
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
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (onActionsTap != null)
              GestureDetector(
                key: actionsKey,
                onTap: showActions,
                child: SizedBox(
                  key: ValueKey('note-card-actions-${item.id}'),
                  width: 24,
                  height: 24,
                  child: Center(
                    child: Icon(
                      LucideIcons.chevronDown,
                      color: colorScheme.onSurfaceVariant,
                      size: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          item.date,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
