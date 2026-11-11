import 'package:flutter/material.dart';

import '../models/guide_topic.dart';

/// Deliberately schematic: no fake screenshot or interactive-looking controls.
class GuideIllustration extends StatelessWidget {
  const GuideIllustration({super.key, required this.topic});
  final GuideTopic topic;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      image: true,
      label: '${topic.label}功能示意',
      child: ExcludeSemantics(
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _GuideScene(topic, colors)),
              ),
              Positioned(
                right: 16,
                bottom: 12,
                child: Text(
                  '功能示意',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideScene extends CustomPainter {
  const _GuideScene(this.topic, this.colors);
  final GuideTopic topic;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = RRect.fromRectAndRadius(
      Rect.fromLTWH(24, 20, size.width - 48, 164),
      const Radius.circular(8),
    );
    canvas.drawRRect(paper, Paint()..color = colors.surfaceContainerLowest);
    canvas.drawRRect(
      paper,
      Paint()
        ..color = colors.outlineVariant
        ..style = PaintingStyle.stroke,
    );
    final left = 44.0, right = size.width - 44;
    void text(
      String value,
      Offset position, {
      double fontSize = 14,
      Color? color,
      FontWeight weight = FontWeight.w400,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontFamily: 'FlowMuseSans',
            fontSize: fontSize,
            color: color ?? colors.onSurface,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (right - position.dx).clamp(0, size.width));
      painter.paint(canvas, position);
    }

    if (topic == GuideTopic.library || topic == GuideTopic.backup) {
      text(
        topic == GuideTopic.library ? '我的笔记本' : '留一份，安心记录',
        Offset(left, 36),
        weight: FontWeight.w600,
      );
      for (var i = 0; i < 3; i++) {
        final y = 77.0 + i * 30;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, y, 18, 22),
            const Radius.circular(3),
          ),
          Paint()..color = colors.primaryContainer,
        );
        text(
          ['课程笔记', '阅读记录', '项目讨论'][i],
          Offset(left + 30, y + 1),
          fontSize: 12,
        );
        canvas.drawLine(
          Offset(right - 16, y + 10),
          Offset(right, y + 10),
          Paint()
            ..color = colors.primary
            ..strokeWidth = 2,
        );
      }
      return;
    }
    if (topic == GuideTopic.messages) {
      text('协作伙伴', Offset(left, 38), weight: FontWeight.w600);
      text(
        '邀请你一起编辑白板',
        Offset(left, 67),
        fontSize: 12,
        color: colors.onSurfaceVariant,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, 104, right - left, 44),
          const Radius.circular(8),
        ),
        Paint()..color = colors.primaryContainer,
      );
      text(
        '讨论，在同一页继续',
        Offset(left + 12, 118),
        fontSize: 12,
        color: colors.onPrimaryContainer,
      );
      return;
    }
    text(
      topic == GuideTopic.pdf
          ? '阅读与批注'
          : topic == GuideTopic.smart
          ? '让记录更清晰'
          : '一起，把想法写下来',
      Offset(left, 36),
      weight: FontWeight.w600,
    );
    for (var i = 0; i < 4; i++) {
      final y = 82.0 + i * 24;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()..color = colors.outlineVariant.withValues(alpha: .65),
      );
    }
    final width = right - left;
    final path = Path()
      ..moveTo(left + 4, 96)
      ..cubicTo(
        left + width * .2,
        57,
        left + width * .22,
        134,
        left + width * .4,
        99,
      )
      ..cubicTo(
        left + width * .48,
        72,
        left + width * .5,
        115,
        left + width * .68,
        89,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (topic == GuideTopic.collaboration) {
      canvas.drawLine(
        Offset(left + width * .32, 143),
        Offset(right - 9, 143),
        Paint()
          ..color = colors.tertiary
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      final pointer = Path()
        ..moveTo(right - 25, 112)
        ..lineTo(right - 18, 127)
        ..lineTo(right - 13, 117)
        ..close();
      canvas.drawPath(pointer, Paint()..color = colors.tertiary);
      text(
        'B',
        Offset(right - 8, 116),
        fontSize: 10,
        color: colors.tertiary,
        weight: FontWeight.w700,
      );
      text(
        'A',
        Offset(left + 3, 112),
        fontSize: 10,
        color: colors.primary,
        weight: FontWeight.w700,
      );
    } else {
      canvas.drawLine(
        Offset(left + width * .1, 145),
        Offset(right - 12, 145),
        Paint()
          ..color = colors.primary.withValues(alpha: .3)
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_GuideScene oldDelegate) =>
      oldDelegate.topic != topic || oldDelegate.colors != colors;
}
