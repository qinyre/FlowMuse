import 'package:flutter/material.dart';

import 'hover_tooltip.dart';
import 'markdraw_controller.dart';

class PageNavigationControls extends StatefulWidget {
  const PageNavigationControls({
    super.key,
    required this.controller,
    required this.onOverview,
    this.enabled = true,
  });

  final MarkdrawController controller;
  final VoidCallback onOverview;
  final bool enabled;

  @override
  State<PageNavigationControls> createState() => _PageNavigationControlsState();
}

class _PageNavigationControlsState extends State<PageNavigationControls> {
  late (int, int, bool, bool) _snapshot;

  (int, int, bool, bool) _readSnapshot() => (
    widget.controller.layout.pages.length,
    widget.controller.pagedViewportMetrics?.currentPageIndex ?? 0,
    widget.controller.layout.isRightToLeft,
    widget.controller.canReturnToPagePosition,
  );

  @override
  void initState() {
    super.initState();
    _snapshot = _readSnapshot();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(PageNavigationControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _snapshot = _readSnapshot();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final next = _readSnapshot();
    if (next != _snapshot) setState(() => _snapshot = next);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final enabled = widget.enabled;
    final pages = controller.layout.pages;
    final index = controller.pagedViewportMetrics?.currentPageIndex ?? 0;
    final rtl = controller.layout.isRightToLeft;
    Widget button(String label, IconData icon, VoidCallback? action) =>
        HoverTooltip(
          message: label,
          child: Semantics(
            label: label,
            button: true,
            child: IconButton(
              onPressed: enabled ? action : null,
              icon: Icon(icon, size: 18),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              padding: const EdgeInsets.all(6),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(
              '上一页',
              rtl ? Icons.chevron_right : Icons.chevron_left,
              index > 0
                  ? () => controller.navigateToPage(pages[index - 1].id)
                  : null,
            ),
            Semantics(
              label: '第 ${index + 1} 页，共 ${pages.length} 页，点击跳转',
              button: true,
              child: TextButton(
                onPressed: enabled
                    ? () => showPageJumpDialog(context, controller)
                    : null,
                child: Text(
                  '${index + 1} / ${pages.length}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            button(
              '下一页',
              rtl ? Icons.chevron_left : Icons.chevron_right,
              index + 1 < pages.length
                  ? () => controller.navigateToPage(pages[index + 1].id)
                  : null,
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button('多页预览', Icons.grid_view_outlined, widget.onOverview),
            button(
              '适合当前页',
              Icons.fit_screen,
              pages.isEmpty
                  ? null
                  : () => controller.navigateToPage(pages[index].id, fit: true),
            ),
            button(
              '返回跳转前位置',
              Icons.undo,
              controller.canReturnToPagePosition
                  ? controller.returnToPagePosition
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool> showPageJumpDialog(
  BuildContext context,
  MarkdrawController controller,
) async {
  if (!controller.preparePageNavigation()) return false;
  final input = TextEditingController(
    text: '${(controller.pagedViewportMetrics?.currentPageIndex ?? 0) + 1}',
  );
  input.selection = TextSelection(
    baseOffset: 0,
    extentOffset: input.text.length,
  );
  String? error;
  final route = DialogRoute<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final number = int.tryParse(input.text);
          final pages = controller.layout.pages;
          if (number == null || number < 1 || number > pages.length) {
            setState(() => error = '请输入 1–${pages.length} 之间的页码');
            return;
          }
          if (controller.navigateToPage(pages[number - 1].id)) {
            Navigator.of(context).pop(true);
          }
        }

        return AlertDialog(
          title: const Text('跳转到页面'),
          content: TextField(
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              labelText: '页码',
              helperText: '共 ${controller.layout.pages.length} 页',
              errorText: error,
            ),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(onPressed: submit, child: const Text('跳转')),
          ],
        );
      },
    ),
  );
  final navigated = await Navigator.of(
    context,
    rootNavigator: true,
  ).push(route);
  await route.completed;
  input.dispose();
  if (!controller.isDisposed) controller.restoreKeyboardFocusWhenStable();
  return navigated ?? false;
}
