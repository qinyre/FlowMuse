import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ZoomControls extends StatelessWidget {
  const ZoomControls({
    super.key,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6E2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('whiteboard-zoom-out'),
            tooltip: '缩小',
            onPressed: onZoomOut,
            icon: const Icon(LucideIcons.minus, size: 18),
          ),
          TextButton(
            key: const ValueKey('whiteboard-zoom-reset'),
            onPressed: onResetZoom,
            child: Text('${(zoom * 100).round()}%'),
          ),
          IconButton(
            key: const ValueKey('whiteboard-zoom-in'),
            tooltip: '放大',
            onPressed: onZoomIn,
            icon: const Icon(LucideIcons.plus, size: 18),
          ),
        ],
      ),
    );
  }
}
