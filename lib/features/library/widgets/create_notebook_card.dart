import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class CreateNotebookCard extends StatelessWidget {
  const CreateNotebookCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Card.outlined(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('create-notebook-card'),
              onTap: onTap,
              child: Center(
                child: Icon(
                  LucideIcons.plus,
                  size: 46,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '新建',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '轻点两下，创建快捷笔记',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF9BA5A1)),
        ),
      ],
    );
  }
}
