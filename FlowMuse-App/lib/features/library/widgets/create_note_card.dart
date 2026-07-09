import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'note_card.dart';

class CreateNoteCard extends StatelessWidget {
  const CreateNoteCard({
    super.key,
    required this.onTap,
    this.icon = LucideIcons.plus,
    this.title = '新建',
    this.subtitle = '轻点两下，创建快捷笔记',
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;

  Key get _tapKey {
    return title == '新建'
        ? const ValueKey('create-notebook-card')
        : const ValueKey('join-room-card');
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
            clipBehavior: Clip.antiAlias,
            color: colorScheme.primary.withValues(alpha: 0.035),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              key: _tapKey,
              onTap: onTap,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Icon(icon, size: 34, color: colorScheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9BA5A1)),
        ),
      ],
    );
  }
}
