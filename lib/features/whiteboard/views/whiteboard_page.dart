import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/whiteboard_toolbar.dart';
import '../widgets/zoom_controls.dart';

class WhiteboardPage extends StatelessWidget {
  const WhiteboardPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFB),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              left: 24,
              top: 22,
              child: IconButton.filledTonal(
                tooltip: '返回',
                onPressed: () => context.pop(),
                icon: const Icon(LucideIcons.arrowLeft),
                style: IconButton.styleFrom(
                  fixedSize: const Size(56, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 22),
                child: WhiteboardToolbar(),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.panelTop,
                    color: Theme.of(context).colorScheme.primary,
                    size: 44,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFF2B302E),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '白板工作台',
                    style: TextStyle(color: Color(0xFF8E9692), fontSize: 16),
                  ),
                ],
              ),
            ),
            const Positioned(left: 24, bottom: 24, child: ZoomControls()),
          ],
        ),
      ),
    );
  }
}
