import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/notebook_item.dart';

class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.item, required this.onTap});

  static const coverWidth = 154.0;
  static const coverHeight = 204.0;

  final NotebookItem item;
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
              key: ValueKey('notebook-card-${item.id}'),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: item.coverColor,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.10),
              item.coverColor,
            ),
            item.coverColor,
            Color.alphaBlend(
              Colors.black.withValues(alpha: 0.08),
              item.coverColor,
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.10),
                border: Border(
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
              ),
              child: const SizedBox(width: 16),
            ),
          ),
          Positioned(
            right: 0,
            top: 10,
            bottom: 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(3),
                ),
              ),
              child: const SizedBox(width: 5),
            ),
          ),
          Positioned(
            left: 30,
            right: 18,
            top: 58,
            child: Column(
              children: List.generate(
                5,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: foreground.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPdf ? LucideIcons.fileText : LucideIcons.bookOpen,
                      color: foreground.withValues(alpha: 0.86),
                      size: 20,
                    ),
                    const Spacer(),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        child: Text(
                          isPdf ? 'PDF' : 'NOTE',
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.86),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  item.subtitle ?? (isPdf ? 'PDF 文档' : '手写笔记'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 15,
                    height: 1.28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    item.kind == LibraryFilter.pdf
                        ? LucideIcons.fileImage
                        : LucideIcons.mountain,
                    color: foreground.withValues(alpha: 0.24),
                    size: 56,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
