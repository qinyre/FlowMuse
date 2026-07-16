library;

import 'package:flutter/material.dart';
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';
import 'toolbar_palette_buttons.dart';

/// Compact bottom toolbar for mobile layout.
class CompactToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;
  final VoidCallback? onCollapse;
  final bool useFlatBackground;
  final VoidCallback? onSpeechPressed;
  final bool speechActive;
  final bool speechAvailable;

  const CompactToolbar({
    super.key,
    required this.controller,
    this.dock = ToolbarDock.top,
    this.onDockChanged,
    this.onCollapse,
    this.useFlatBackground = false,
    this.onSpeechPressed,
    this.speechActive = false,
    this.speechAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    final vertical = dock != ToolbarDock.top;
    final buttonSize = vertical ? 36.0 : 44.0;
    return FocusTraversalGroup(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: useFlatBackground ? cs.surfaceContainerLow : null,
          gradient: useFlatBackground
              ? null
              : LinearGradient(colors: [cs.surfaceContainerLow, cs.surface]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(color: cs.shadow.withValues(alpha: 0.17), blurRadius: 1),
            BoxShadow(color: cs.shadow.withValues(alpha: 0.08), blurRadius: 3),
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
          child: Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              _compactToolButton(
                cs: cs,
                type: ToolType.hand,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.select,
                activeType: activeType,
              ),
              BrushPaletteButton(
                controller: controller,
                dock: dock,
                size: buttonSize,
              ),
              ShapePaletteButton(
                controller: controller,
                dock: dock,
                size: buttonSize,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.text,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.eraser,
                activeType: activeType,
              ),
              _compactToolButton(
                cs: cs,
                type: ToolType.laser,
                activeType: activeType,
              ),
              _compactButton(
                cs: cs,
                icon: speechActive
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none,
                tooltip: speechAvailable ? '语音转文字' : '当前设备不支持语音转文字',
                onPressed: speechAvailable ? onSpeechPressed : null,
                isActive: speechActive,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.text_fields,
                tooltip: '文字识别模式',
                onPressed: controller.toggleInkRecognitionMode,
                isActive: controller.inkRecognitionMode,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.auto_fix_high,
                tooltip: '智能排布模式',
                onPressed: controller.toggleSmartInkLayoutMode,
                isActive: controller.smartInkLayoutMode,
              ),
              _compactButton(
                cs: cs,
                icon: Icons.document_scanner_outlined,
                tooltip: '全局识别排版',
                onPressed: () {
                  _runGlobalSmartLayout(context);
                },
              ),
              _compactButton(
                cs: cs,
                iconWidget: _dockIcon(dock),
                tooltip: '工具栏位置',
                onPressed: () => _showDockMenu(context),
              ),
              if (onCollapse != null)
                _compactButton(
                  cs: cs,
                  icon: switch (dock) {
                    ToolbarDock.top => Icons.keyboard_arrow_up,
                    ToolbarDock.left => Icons.keyboard_arrow_left,
                    ToolbarDock.right => Icons.keyboard_arrow_right,
                  },
                  tooltip: '收起工具栏',
                  onPressed: onCollapse!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactToolButton({
    required ColorScheme cs,
    required ToolType type,
    required ToolType activeType,
  }) {
    final active = activeType == type;
    return _compactButton(
      cs: cs,
      iconWidget: iconWidgetFor(
        type,
        color: active ? cs.primary : cs.onSurfaceVariant,
        size: 22,
        isActive: active,
      ),
      tooltip: labelForToolType(type),
      onPressed: () => controller.switchTool(type),
      isActive: active,
      isEmphasized: active,
      useFlatBackground: useFlatBackground,
    );
  }

  Widget _toolbarDivider(ColorScheme cs, bool vertical) {
    return Padding(
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: vertical ? 16 : 2,
        height: vertical ? 1 : 20,
        decoration: BoxDecoration(
          color: cs.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _dockIcon(ToolbarDock value) => switch (value) {
    ToolbarDock.top => const Icon(Icons.vertical_align_top, size: 22),
    ToolbarDock.left => const Icon(Icons.arrow_left, size: 26),
    ToolbarDock.right => const Icon(Icons.arrow_right, size: 26),
  };

  Future<void> _showDockMenu(BuildContext context) async {
    final selected = await showAnchoredPopupMenu<ToolbarDock>(
      context: context,
      items: [
        for (final option in ToolbarDock.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  option == ToolbarDock.top
                      ? Icons.vertical_align_top
                      : option == ToolbarDock.left
                      ? Icons.arrow_left
                      : Icons.arrow_right,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(switch (option) {
                    ToolbarDock.top => '顶部',
                    ToolbarDock.left => '靠左',
                    ToolbarDock.right => '靠右',
                  }),
                ),
                if (option == dock) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
    if (selected != null) {
      onDockChanged?.call(selected);
    }
  }

  Widget _compactButton({
    required ColorScheme cs,
    IconData? icon,
    Widget? iconWidget,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isActive = false,
    bool isEmphasized = false,
    bool useFlatBackground = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: isActive,
        emphasized: isEmphasized,
        useFlatBackground: useFlatBackground,
        size: dock == ToolbarDock.top ? 44 : 36,
        onPressed: onPressed,
        child:
            iconWidget ?? Icon(icon, size: dock == ToolbarDock.top ? 22 : 20),
      ),
    );
  }

  Future<void> _runGlobalSmartLayout(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final engine = await _pickSmartLayoutRecognitionEngine(context);
    if (engine == null || !context.mounted) {
      return;
    }
    bool changed;
    Object? error;
    try {
      changed = await controller.runGlobalSmartLayout(
        engine: engine,
        onProgress: (completed, total) {
          if (!context.mounted) return;
          _showSmartLayoutProgress(messenger, completed, total);
        },
      );
    } catch (caught) {
      changed = false;
      error = caught;
    }
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _smartLayoutMessage(changed: changed, error: error),
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<SmartLayoutRecognitionEngine?> _pickSmartLayoutRecognitionEngine(
    BuildContext context,
  ) {
    return showDialog<SmartLayoutRecognitionEngine>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择识别模式'),
        content: const Text('请选择全局智能排版使用的识别引擎。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SmartLayoutRecognitionEngine.myscript),
            child: const Text('MyScript识别'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SmartLayoutRecognitionEngine.ai),
            child: const Text('AI识别'),
          ),
        ],
      ),
    );
  }

  void _showSmartLayoutProgress(
    ScaffoldMessengerState messenger,
    int completed,
    int total,
  ) {
    final progress = total <= 0 ? null : completed / total;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('识别中 $completed/$total'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
        ),
      ),
    );
  }

  String _smartLayoutMessage({required bool changed, Object? error}) {
    if (changed) return '智能排版已应用';
    if (error == null) return '智能排版失败，场景未修改';
    return '智能排版失败：${_readableError(error)}';
  }

  String _readableError(Object error) {
    final text = error is StateError ? error.message : error.toString();
    return text
        .replaceFirst(RegExp(r'^Bad state:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
  }
}
