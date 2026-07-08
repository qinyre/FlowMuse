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
            left: 22,
            right: 18,
            top: 62,
            child: Column(
              children: List.generate(
                5,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: foreground.withValues(
                      alpha: index == 0 ? 0.16 : 0.10,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(height: 2),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(34, 34),
              painter: _PageFoldPainter(
                foreground: foreground,
                background: item.coverColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.fileText,
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
                    LucideIcons.fileText,
                    color: foreground.withValues(alpha: 0.24),
                    size: 54,
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

class _PageFoldPainter extends CustomPainter {
  const _PageFoldPainter({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final foldPaint = Paint()
      ..color = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.30),
        background,
      );
    final shadowPaint = Paint()
      ..color = foreground.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(path, foldPaint);
    canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), shadowPaint);
  }

  @override
  bool shouldRepaint(covariant _PageFoldPainter oldDelegate) {
    return foreground != oldDelegate.foreground ||
        background != oldDelegate.background;
  }
}
