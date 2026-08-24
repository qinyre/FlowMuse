import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 截图模式覆盖层。仅做手势/视觉，**不**认识 controller——
/// 坐标换算与导出由调用方（whiteboard_page）执行。
class RegionCaptureOverlay extends StatefulWidget {
  const RegionCaptureOverlay({
    super.key,
    required this.onCommit, // Rect screenRect → Future<void>；页面负责换算+导出+关闭
    required this.onCancel, // VoidCallback；页面负责取消+关闭
  });

  final Future<void> Function(Rect screenRect) onCommit;
  final VoidCallback onCancel;

  @override
  State<RegionCaptureOverlay> createState() => _RegionCaptureOverlayState();
}

class _RegionCaptureOverlayState extends State<RegionCaptureOverlay> {
  static const double _minSide = 16;
  static const String _guideText = '拖动框选要发送的内容';
  static const String _tooSmallHint = '矩形太小，请重新框选';

  Offset? _start;
  Rect? _dragRect;
  String? _hint;
  bool _committing = false;

  void _onPointerDown(PointerDownEvent event) {
    if (_committing) return;
    _start = event.localPosition;
    setState(() {
      _dragRect = null;
      _hint = null;
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _start;
    if (start == null) return;
    setState(() => _dragRect = Rect.fromPoints(start, event.localPosition));
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _start;
    if (start == null) return;
    final rect = _dragRect;
    _start = null;
    if (rect == null || rect.width < _minSide || rect.height < _minSide) {
      setState(() => _hint = _tooSmallHint);
      return;
    }
    unawaited(_commit(rect));
  }

  Future<void> _commit(Rect rect) async {
    if (_committing) return;
    setState(() => _committing = true);
    try {
      await widget.onCommit(rect);
    } catch (_) {
      // 页面已处理错误展示；成功/失败均保持提交态，直至页面卸载本组件。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: CustomPaint(painter: _RegionMaskPaint(dragRect: _dragRect)),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _hint ?? _guideText,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '取消',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _committing ? null : widget.onCancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RegionMaskPaint extends CustomPainter {
  const _RegionMaskPaint({required this.dragRect});

  static const double _dashLength = 8;
  static const double _gapLength = 6;

  final Rect? dragRect;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = dragRect;
    if (rect == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x8B000000),
      );
      return;
    }
    // 回形遮罩：外矩形减去内矩形（evenOdd）→ 矩形外 55% 黑。
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(mask, Paint()..color = const Color(0x8B000000));

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF4A90D9);
    _drawDashedEdge(canvas, rect.topLeft, rect.topRight, border);
    _drawDashedEdge(canvas, rect.topRight, rect.bottomRight, border);
    _drawDashedEdge(canvas, rect.bottomRight, rect.bottomLeft, border);
    _drawDashedEdge(canvas, rect.bottomLeft, rect.topLeft, border);
  }

  /// 沿 a→b 画 8 实/6 空的短线段（不足余数实线收尾）。
  void _drawDashedEdge(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final len = delta.distance;
    if (len <= 0) return;
    final dir = delta / len;
    var d = 0.0;
    while (d < len) {
      final end = math.min(d + _dashLength, len);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d += _dashLength + _gapLength;
    }
  }

  @override
  bool shouldRepaint(_RegionMaskPaint oldDelegate) =>
      oldDelegate.dragRect != dragRect;
}
