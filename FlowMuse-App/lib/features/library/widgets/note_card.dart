import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/note_item.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.item, required this.onTap});

  static const coverWidth = 132.0;
  static const coverHeight = 176.0;
  static const gridMaxCrossAxisExtent = 166.0;
  static const gridMainAxisExtent = 226.0;
  static const compactGridCrossGap = 12.0;
  static const gridCrossGap = 16.0;
  static const compactGridMainGap = 16.0;
  static const gridMainGap = 20.0;

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
            margin: EdgeInsets.zero,
            elevation: 1,
            shadowColor: const Color(0x0F5A625F),
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(),
            child: InkWell(
              key: ValueKey('note-card-${item.id}'),
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NoteCover(item: item),
                  const PageFoldIndicator(),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
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
            const SizedBox(width: 4),
            const Icon(
              LucideIcons.chevronDown,
              color: Color(0xFF555C59),
              size: 16,
            ),
          ],
        ),
        const SizedBox(height: 3),
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

class PageFoldIndicator extends StatelessWidget {
  const PageFoldIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: CustomPaint(
        size: const Size(22, 22),
        painter: _PageFoldIndicatorPainter(
          borderColor: Theme.of(context).colorScheme.outlineVariant,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

class _PageFoldIndicatorPainter extends CustomPainter {
  const _PageFoldIndicatorPainter({
    required this.borderColor,
    required this.fillColor,
  });

  final Color borderColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final fold = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(fold, Paint()..color = fillColor.withValues(alpha: 0.84));
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width, size.height),
      Paint()
        ..color = borderColor.withValues(alpha: 0.70)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PageFoldIndicatorPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        fillColor != oldDelegate.fillColor;
  }
}
