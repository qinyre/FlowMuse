import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/notebook_item.dart';

class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.item, required this.onTap});

  final NotebookItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: NotebookCover(item: item),
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

class NotebookCover extends StatelessWidget {
  const NotebookCover({super.key, required this.item});

  final NotebookItem item;

  @override
  Widget build(BuildContext context) {
    final isPdf = item.kind == LibraryFilter.pdf;
    final foreground =
        ThemeData.estimateBrightnessForColor(item.coverColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF202523);

    return ColoredBox(
      color: item.coverColor,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  isPdf ? LucideIcons.fileText : LucideIcons.bookOpen,
                  color: foreground.withValues(alpha: 0.9),
                  size: 22,
                ),
                const Spacer(),
                Text(
                  isPdf ? 'PDF' : 'NOTEBOOK',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: Icon(
                LucideIcons.layers,
                color: foreground.withValues(alpha: 0.34),
                size: 58,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
