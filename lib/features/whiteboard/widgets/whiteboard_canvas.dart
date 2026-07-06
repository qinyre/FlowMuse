import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/whiteboard_element.dart';
import '../view_models/whiteboard_view_model.dart';

class WhiteboardCanvas extends StatefulWidget {
  const WhiteboardCanvas({
    super.key,
    required this.state,
    required this.onDragComplete,
  });

  final WhiteboardState state;
  final Future<void> Function({
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  })
  onDragComplete;

  @override
  State<WhiteboardCanvas> createState() => _WhiteboardCanvasState();
}

class _WhiteboardCanvasState extends State<WhiteboardCanvas> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey(widget.state.notebookId),
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        if (!_canCreateElement) {
          return;
        }
        setState(() {
          _dragStart = _toScene(details.localPosition);
          _dragCurrent = _dragStart;
        });
      },
      onPanUpdate: (details) {
        if (_dragStart == null) {
          return;
        }
        setState(() {
          _dragCurrent = _toScene(details.localPosition);
        });
      },
      onPanEnd: (_) async {
        final start = _dragStart;
        final current = _dragCurrent;
        setState(() {
          _dragStart = null;
          _dragCurrent = null;
        });
        if (start == null || current == null) {
          return;
        }
        await widget.onDragComplete(
          startX: start.dx,
          startY: start.dy,
          endX: current.dx,
          endY: current.dy,
        );
      },
      onTapUp: (details) async {
        if (widget.state.activeTool != WhiteboardTool.text) {
          return;
        }
        final position = _toScene(details.localPosition);
        await widget.onDragComplete(
          startX: position.dx,
          startY: position.dy,
          endX: position.dx,
          endY: position.dy,
        );
      },
      child: CustomPaint(
        key: const ValueKey('whiteboard-canvas'),
        painter: _WhiteboardPainter(
          elements: widget.state.elements,
          zoom: widget.state.zoom,
          pan: Offset(widget.state.panX, widget.state.panY),
          preview: _previewElement(),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  bool get _canCreateElement {
    return switch (widget.state.activeTool) {
      WhiteboardTool.rectangle ||
      WhiteboardTool.ellipse ||
      WhiteboardTool.arrow ||
      WhiteboardTool.pen => true,
      _ => false,
    };
  }

  Offset _toScene(Offset local) {
    return Offset(
      local.dx / widget.state.zoom + widget.state.panX,
      local.dy / widget.state.zoom + widget.state.panY,
    );
  }

  WhiteboardElement? _previewElement() {
    final start = _dragStart;
    final current = _dragCurrent;
    if (start == null || current == null) {
      return null;
    }
    final left = math.min(start.dx, current.dx);
    final top = math.min(start.dy, current.dy);
    final width = (current.dx - start.dx).abs();
    final height = (current.dy - start.dy).abs();
    return switch (widget.state.activeTool) {
      WhiteboardTool.rectangle => WhiteboardElement.rectangle(
        id: 'preview',
        x: left,
        y: top,
        width: width,
        height: height,
        fractionalIndex: 'preview',
      ),
      WhiteboardTool.ellipse => WhiteboardElement.ellipse(
        id: 'preview',
        x: left,
        y: top,
        width: width,
        height: height,
        fractionalIndex: 'preview',
      ),
      WhiteboardTool.arrow => WhiteboardElement.arrow(
        id: 'preview',
        x1: start.dx,
        y1: start.dy,
        x2: current.dx,
        y2: current.dy,
        fractionalIndex: 'preview',
      ),
      WhiteboardTool.pen => WhiteboardElement.path(
        id: 'preview',
        points: [
          WhiteboardPoint(start.dx, start.dy),
          WhiteboardPoint(current.dx, current.dy),
        ],
        fractionalIndex: 'preview',
      ),
      _ => null,
    };
  }
}

class _WhiteboardPainter extends CustomPainter {
  const _WhiteboardPainter({
    required this.elements,
    required this.zoom,
    required this.pan,
    this.preview,
  });

  final List<WhiteboardElement> elements;
  final double zoom;
  final Offset pan;
  final WhiteboardElement? preview;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFDFDFB),
    );
    canvas.save();
    canvas.scale(zoom);
    canvas.translate(-pan.dx, -pan.dy);
    _drawGrid(canvas, size);
    for (final element in elements.where((item) => !item.isDeleted)) {
      _drawElement(canvas, element, const Color(0xFF202523));
    }
    if (preview != null) {
      _drawElement(
        canvas,
        preview!,
        const Color(0xFF4C8F79).withValues(alpha: 0.68),
      );
    }
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Size size) {
    const grid = 40.0;
    final visibleWidth = size.width / zoom;
    final visibleHeight = size.height / zoom;
    final left = pan.dx;
    final top = pan.dy;
    final right = left + visibleWidth;
    final bottom = top + visibleHeight;
    final paint = Paint()
      ..color = const Color(0xFFE8EEEA)
      ..strokeWidth = 1 / zoom;
    final boldPaint = Paint()
      ..color = const Color(0xFFD9E2DD)
      ..strokeWidth = 1 / zoom;

    for (var x = (left / grid).floor() * grid; x <= right; x += grid) {
      canvas.drawLine(
        Offset(x, top),
        Offset(x, bottom),
        (x / grid).round() % 5 == 0 ? boldPaint : paint,
      );
    }
    for (var y = (top / grid).floor() * grid; y <= bottom; y += grid) {
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        (y / grid).round() % 5 == 0 ? boldPaint : paint,
      );
    }
  }

  void _drawElement(Canvas canvas, WhiteboardElement element, Color color) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.2 / zoom;
    final fill = Paint()
      ..color = const Color(0x334C8F79)
      ..style = PaintingStyle.fill;

    switch (element.type) {
      case WhiteboardElementType.rectangle:
        final rect = _rectFromData(element.data);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(8)),
          stroke,
        );
      case WhiteboardElementType.ellipse:
        final rect = _rectFromData(element.data);
        canvas.drawOval(rect, fill);
        canvas.drawOval(rect, stroke);
      case WhiteboardElementType.arrow:
        final start = Offset(
          (element.data['x1']! as num).toDouble(),
          (element.data['y1']! as num).toDouble(),
        );
        final end = Offset(
          (element.data['x2']! as num).toDouble(),
          (element.data['y2']! as num).toDouble(),
        );
        canvas.drawLine(start, end, stroke);
        _drawArrowHead(canvas, start, end, stroke);
      case WhiteboardElementType.freedraw:
      case WhiteboardElementType.line:
        final points = element.scenePoints;
        if (points.length < 2) {
          return;
        }
        final path = Path()..moveTo(points.first.x, points.first.y);
        for (final point in points.skip(1)) {
          path.lineTo(point.x, point.y);
        }
        canvas.drawPath(path, stroke);
      case WhiteboardElementType.text:
        final painter = TextPainter(
          text: TextSpan(
            text: element.text ?? '',
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(element.x, element.y));
      case WhiteboardElementType.image:
      case WhiteboardElementType.diamond:
      case WhiteboardElementType.frame:
        break;
    }
  }

  Rect _rectFromData(Map<String, Object?> data) {
    return Rect.fromLTWH(
      (data['x']! as num).toDouble(),
      (data['y']! as num).toDouble(),
      (data['width']! as num).toDouble(),
      (data['height']! as num).toDouble(),
    );
  }

  void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    const size = 14.0;
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - size * math.cos(angle - math.pi / 6),
        end.dy - size * math.sin(angle - math.pi / 6),
      )
      ..moveTo(end.dx, end.dy)
      ..lineTo(
        end.dx - size * math.cos(angle + math.pi / 6),
        end.dy - size * math.sin(angle + math.pi / 6),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WhiteboardPainter oldDelegate) {
    return oldDelegate.elements != elements ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan ||
        oldDelegate.preview != preview;
  }
}
