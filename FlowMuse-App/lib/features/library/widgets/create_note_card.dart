import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'note_card.dart';

class CreateNoteCard extends StatelessWidget {
  const CreateNoteCard({
    super.key,
    required this.onTap,
    this.icon = LucideIcons.plus,
    this.title = '新建笔记',
    this.subtitle = '轻点两下，创建快捷笔记',
  });

  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;

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
            color: colorScheme.primary.withValues(alpha: 0.035),
            shape: const RoundedRectangleBorder(),
            child: InkWell(
              key: _tapKey,
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Icon(icon, size: 28, color: colorScheme.primary),
                      ),
                    ),
                  ),
                  const PageFoldIndicator(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
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
