import 'dart:async';

import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('锚点菜单从触发按钮下方展开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('menu-anchor'),
              onPressed: () {
                unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    placement: AnchoredPopupPlacement.below,
                    items: const [
                      PopupMenuItem(value: 'option', child: Text('选项')),
                    ],
                  ),
                );
              },
              child: const Text('打开菜单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('menu-anchor')));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(
      find.byKey(const ValueKey('menu-anchor')),
    );
    final menuItemRect = tester.getRect(find.byType(PopupMenuItem<String>));

    expect(menuItemRect.top, greaterThanOrEqualTo(anchorRect.bottom));
  });

  testWidgets('侧方锚点菜单从触发按钮右下方展开', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('right-menu-anchor'),
              onPressed: () {
                unawaited(
                  showAnchoredPopupMenu<String>(
                    context: context,
                    placement: AnchoredPopupPlacement.right,
                    items: const [
                      PopupMenuItem(value: 'option', child: Text('选项')),
                    ],
                  ),
                );
              },
              child: const Text('打开菜单'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('right-menu-anchor')));
    await tester.pumpAndSettle();

    final anchorRect = tester.getRect(
      find.byKey(const ValueKey('right-menu-anchor')),
    );
    final menuItemRect = tester.getRect(find.byType(PopupMenuItem<String>));

    expect(menuItemRect.top, greaterThanOrEqualTo(anchorRect.bottom));
    expect(menuItemRect.left, greaterThanOrEqualTo(anchorRect.right));
  });
}
