import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ZoomControls extends StatelessWidget {
  const ZoomControls({super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'zoomOut',
          icon: Icon(LucideIcons.minus, size: 18),
        ),
        ButtonSegment(value: 'current', label: Text('100%')),
        ButtonSegment(value: 'zoomIn', icon: Icon(LucideIcons.plus, size: 18)),
      ],
      selected: const {'current'},
      showSelectedIcon: false,
      onSelectionChanged: (_) {},
    );
  }
}
