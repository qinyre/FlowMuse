library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../markdraw.dart' hide TextAlign;

/// Diamond tool icon — rotated rounded square.
class DiamondIconPainter extends CustomPainter {
  final Color color;
  final bool filled;
  DiamondIconPainter({required this.color, this.filled = false});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final s = size.width * 0.58;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(math.pi / 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: s, height: s),
        const Radius.circular(2.5),
      ),
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DiamondIconPainter old) =>
      old.color != color || old.filled != filled;
}

/// Diagonal red line for transparent color indicator.
class DiagonalLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 20x20 circle cursor for the eraser tool.
class EraserCursorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, 5, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      5,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fill style icon (solid, hachure, cross-hatch, zigzag).
class FillStyleIcon extends CustomPainter {
  final String style;
  final Color color;
  FillStyleIcon(this.style, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(3, 3, size.width - 6, size.height - 6);
    canvas.drawRect(rect, paint);

    final fillPaint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    switch (style) {
      case 'solid':
        canvas.drawRect(rect, fillPaint..style = PaintingStyle.fill);
      case 'hachure':
        canvas.save();
        canvas.clipRect(rect);
        for (var x = -size.height; x < size.width; x += 4) {
          canvas.drawLine(
            Offset(rect.left + x, rect.bottom),
            Offset(rect.left + x + rect.height, rect.top),
            fillPaint..style = PaintingStyle.stroke,
          );
        }
        canvas.restore();
      case 'cross-hatch':
        canvas.save();
        canvas.clipRect(rect);
        for (var x = -size.height; x < size.width; x += 4) {
          canvas.drawLine(
            Offset(rect.left + x, rect.bottom),
            Offset(rect.left + x + rect.height, rect.top),
            fillPaint..style = PaintingStyle.stroke,
          );
          canvas.drawLine(
            Offset(rect.left + x, rect.top),
            Offset(rect.left + x + rect.height, rect.bottom),
            fillPaint..style = PaintingStyle.stroke,
          );
        }
        canvas.restore();
      case 'zigzag':
        canvas.save();
        canvas.clipRect(rect);
        final path = Path();
        for (var x = rect.left; x < rect.right; x += 6) {
          path.moveTo(x, rect.top);
          var y = rect.top;
          var goRight = true;
          while (y < rect.bottom) {
            final nx = goRight ? x + 3 : x;
            final ny = y + 3;
            path.lineTo(nx, ny);
            y = ny;
            goRight = !goRight;
          }
        }
        canvas.drawPath(path, fillPaint..style = PaintingStyle.stroke);
        canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FillStyleIcon old) =>
      old.style != style || old.color != color;
}

/// Stroke width icon (horizontal line at given thickness).
class StrokeWidthIcon extends CustomPainter {
  final double width;
  final Color color;
  StrokeWidthIcon(this.width, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), paint);
  }

  @override
  bool shouldRepaint(StrokeWidthIcon old) =>
      old.width != width || old.color != color;
}

/// Stroke style icon (solid, dashed, dotted).
class StrokeStyleIcon extends CustomPainter {
  final String style;
  final Color color;
  StrokeStyleIcon(this.style, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    switch (style) {
      case 'solid':
        canvas.drawLine(Offset(4, y), Offset(size.width - 4, y), paint);
      case 'dashed':
        final path = Path();
        var x = 4.0;
        while (x < size.width - 4) {
          path.moveTo(x, y);
          path.lineTo(math.min(x + 5, size.width - 4), y);
          x += 8;
        }
        canvas.drawPath(path, paint);
      case 'dotted':
        var x = 5.0;
        while (x < size.width - 4) {
          canvas.drawCircle(
            Offset(x, y),
            1.0,
            paint..style = PaintingStyle.fill,
          );
          x += 5;
        }
    }
  }

  @override
  bool shouldRepaint(StrokeStyleIcon old) =>
      old.style != style || old.color != color;
}

/// Roughness icon (straight, wobbly, very wobbly line).
class RoughnessIcon extends CustomPainter {
  final double roughness;
  final Color color;
  RoughnessIcon(this.roughness, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    final path = Path();
    path.moveTo(4, y);
    if (roughness < 0.5) {
      path.lineTo(size.width - 4, y);
    } else if (roughness < 2.0) {
      final w = size.width - 8;
      for (var i = 0; i <= 8; i++) {
        final t = i / 8.0;
        final offset = math.sin(t * math.pi * 3) * 2.0;
        path.lineTo(4 + w * t, y + offset);
      }
    } else {
      final w = size.width - 8;
      for (var i = 0; i <= 12; i++) {
        final t = i / 12.0;
        final offset = math.sin(t * math.pi * 5) * 3.5;
        path.lineTo(4 + w * t, y + offset);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(RoughnessIcon old) =>
      old.roughness != roughness || old.color != color;
}

/// Roundness icon (sharp or rounded corner).
class RoundnessIcon extends CustomPainter {
  final bool rounded;
  final Color color;
  RoundnessIcon(this.rounded, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (rounded) {
      path.moveTo(size.width - 6, 6);
      path.lineTo(size.width - 6, 12);
      path.quadraticBezierTo(
        size.width - 6,
        size.height - 6,
        12,
        size.height - 6,
      );
      path.lineTo(6, size.height - 6);
    } else {
      path.moveTo(size.width - 6, 6);
      path.lineTo(size.width - 6, size.height - 6);
      path.lineTo(6, size.height - 6);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(RoundnessIcon old) =>
      old.rounded != rounded || old.color != color;
}

/// Arrow type icon (sharp, round, elbow, round-elbow).
class ArrowTypeIcon extends CustomPainter {
  final String type;
  final Color color;
  ArrowTypeIcon(this.type, {this.color = const Color(0xFF1e1e1e)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    switch (type) {
      case 'sharp':
        path.moveTo(5, size.height - 5);
        path.lineTo(size.width / 2, 8);
        path.lineTo(size.width - 5, size.height - 5);
      case 'round':
        path.moveTo(5, size.height - 5);
        path.quadraticBezierTo(
          size.width / 2,
          2,
          size.width - 5,
          size.height - 5,
        );
      case 'elbow':
        path.moveTo(5, size.height - 5);
        path.lineTo(5, 8);
        path.lineTo(size.width - 5, 8);
        path.lineTo(size.width - 5, size.height - 5);
      case 'round-elbow':
        path.moveTo(5, size.height - 5);
        path.lineTo(5, 12);
        path.quadraticBezierTo(5, 8, 9, 8);
        path.lineTo(size.width - 9, 8);
        path.quadraticBezierTo(size.width - 5, 8, size.width - 5, 12);
        path.lineTo(size.width - 5, size.height - 5);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ArrowTypeIcon old) =>
      old.type != type || old.color != color;
}

/// Arrowhead icon (various head styles).
class ArrowheadIcon extends CustomPainter {
  final Arrowhead? arrowhead;
  final bool isStart;
  final Color color;

  ArrowheadIcon(
    this.arrowhead, {
    this.isStart = false,
    this.color = const Color(0xFF1e1e1e),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final cy = size.height / 2;

    final double lineStart;
    final double lineEnd;
    if (isStart) {
      lineStart = size.width - 4;
      lineEnd = 4;
    } else {
      lineStart = 4;
      lineEnd = size.width - 4;
    }

    canvas.drawLine(Offset(lineStart, cy), Offset(lineEnd, cy), paint);

    if (arrowhead == null) return;

    final tipX = lineEnd;
    final dir = isStart ? 1.0 : -1.0;

    switch (arrowhead!) {
      case Arrowhead.arrow:
        final path = Path()
          ..moveTo(tipX + dir * 5, cy - 4)
          ..lineTo(tipX, cy)
          ..lineTo(tipX + dir * 5, cy + 4);
        canvas.drawPath(path, paint);
      case Arrowhead.bar:
        canvas.drawLine(Offset(tipX, cy - 4), Offset(tipX, cy + 4), paint);
      case Arrowhead.dot:
        canvas.drawCircle(
          Offset(tipX, cy),
          3,
          paint..style = PaintingStyle.fill,
        );
      case Arrowhead.triangle:
        final path = Path()
          ..moveTo(tipX, cy)
          ..lineTo(tipX + dir * 6, cy - 4)
          ..lineTo(tipX + dir * 6, cy + 4)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
      case Arrowhead.triangleOutline:
        final path = Path()
          ..moveTo(tipX, cy)
          ..lineTo(tipX + dir * 6, cy - 4)
          ..lineTo(tipX + dir * 6, cy + 4)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      case Arrowhead.circle:
        canvas.drawCircle(
          Offset(tipX, cy),
          3,
          paint..style = PaintingStyle.fill,
        );
      case Arrowhead.circleOutline:
        canvas.drawCircle(
          Offset(tipX, cy),
          3,
          paint..style = PaintingStyle.stroke,
        );
      case Arrowhead.diamond:
        final path = Path()
          ..moveTo(tipX, cy)
          ..lineTo(tipX + dir * 3, cy - 3)
          ..lineTo(tipX + dir * 6, cy)
          ..lineTo(tipX + dir * 3, cy + 3)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
      case Arrowhead.diamondOutline:
        final path = Path()
          ..moveTo(tipX, cy)
          ..lineTo(tipX + dir * 3, cy - 3)
          ..lineTo(tipX + dir * 6, cy)
          ..lineTo(tipX + dir * 3, cy + 3)
          ..close();
        canvas.drawPath(path, paint..style = PaintingStyle.stroke);
      case Arrowhead.crowfootOne:
        final barX = tipX + dir * 3;
        canvas.drawLine(Offset(barX, cy - 4), Offset(barX, cy + 4), paint);
      case Arrowhead.crowfootMany:
        final forkX = tipX + dir * 5;
        final path = Path()
          ..moveTo(tipX, cy - 4)
          ..lineTo(forkX, cy)
          ..lineTo(tipX, cy + 4);
        canvas.drawPath(path, paint);
      case Arrowhead.crowfootOneOrMany:
        final forkX = tipX + dir * 5;
        final barX = tipX + dir * 3;
        final path = Path()
          ..moveTo(tipX, cy - 4)
          ..lineTo(forkX, cy)
          ..lineTo(tipX, cy + 4);
        canvas.drawPath(path, paint);
        canvas.drawLine(Offset(barX, cy - 4), Offset(barX, cy + 4), paint);
    }
  }

  @override
  bool shouldRepaint(ArrowheadIcon old) =>
      old.arrowhead != arrowhead ||
      old.isStart != isStart ||
      old.color != color;
}
