import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_spacing.dart';
import 'note_card.dart';

class CreateNoteCard extends StatelessWidget {
  const CreateNoteCard({
    super.key,
    required this.onTap,
    this.icon = LucideIcons.plus,
    this.title = '新建笔记',
    this.subtitle = '记录想法，开始书写',
    this.isPrimary = true,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isPrimary;

  Key get _tapKey {
    return title == '加入房间'
        ? const ValueKey('join-room-card')
        : const ValueKey('create-notebook-card');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          width: NoteCard.coverWidth,
          height: NoteCard.coverHeight,
          child: Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            color: isPrimary
                ? Color.alphaBlend(
                    colorScheme.primary.withValues(alpha: 0.06),
                    colorScheme.surface,
                  )
                : colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              side: BorderSide(
                color: isPrimary
                    ? colorScheme.primary.withValues(alpha: 0.3)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: InkWell(
              key: _tapKey,
              onTap: onTap,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(
                      alpha: isPrimary ? 0.12 : 0.06,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Icon(
                      icon,
                      size: 28,
                      color: isPrimary
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 13),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
