library;

import 'package:flutter/material.dart';

import '../../markdraw.dart' hide TextAlign;

/// Compact bottom toolbar for mobile layout.
class CompactToolbar extends StatelessWidget {
  final MarkdrawController controller;

  const CompactToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    final showPressureSlider = activeType == ToolType.freedraw;
    return FocusTraversalGroup(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.17),
              blurRadius: 1,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 3,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _compactButton(
                cs: cs,
                icon: Icons.undo,
                tooltip: '撤销',
                onPressed: controller.undo,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.redo,
                tooltip: '重做',
                onPressed: controller.redo,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 20,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              for (final type in ToolType.values)
                if (type != ToolType.frame)
                  _compactButton(
                    cs: cs,
                    iconWidget: iconWidgetFor(
                      type,
                      color: activeType == type
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      size: 22,
                      isActive: activeType == type,
                    ),
                    tooltip: labelForToolType(type),
                    onPressed: () => controller.switchTool(type),
                    isActive: activeType == type,
                  ),
              // 压感灵敏度滑块：仅在手写(freedraw)工具激活时显示
              if (showPressureSlider) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CompactPressureSlider(controller: controller),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactButton({
    required ColorScheme cs,
    IconData? icon,
    Widget? iconWidget,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child:
                    iconWidget ??
                    Icon(
                      icon,
                      size: 22,
                      color: isActive ? cs.primary : cs.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact 布局的压感灵敏度弹出式滑块。
class _CompactPressureSlider extends StatelessWidget {
  final MarkdrawController controller;
  const _CompactPressureSlider({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return GestureDetector(
          onTap: () => _showSliderPopup(context),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.line_weight,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '压感',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSliderPopup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: controller,
          builder: (ctx, _) {
            final value = controller.pressureSensitivity;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('压感强度', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('均匀', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: value,
                          min: 0.0,
                          max: 1.0,
                          onChanged: (v) {
                            controller.pressureSensitivity = v;
                          },
                        ),
                      ),
                      const Text('极强', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
