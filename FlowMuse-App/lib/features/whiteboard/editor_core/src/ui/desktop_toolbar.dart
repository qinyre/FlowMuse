library;

import 'package:flutter/material.dart';
import 'package:flow_muse/shared/utils/ui_lifecycle.dart';
import '../../markdraw.dart' hide TextAlign;
import 'studio_rail_icon_button.dart';
import 'toolbar_palette_buttons.dart';

/// Desktop top toolbar with tool buttons and tool lock.
class DesktopToolbar extends StatelessWidget {
  final MarkdrawController controller;
  final VoidCallback? onImportImage;
  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;
  final VoidCallback? onCollapse;
  final bool useFlatBackground;
  final VoidCallback? onSpeechPressed;
  final bool speechActive;
  final bool speechAvailable;
  final VoidCallback? onAiPressed;

  const DesktopToolbar({
    super.key,
    required this.controller,
    this.onImportImage,
    this.dock = ToolbarDock.top,
    this.onDockChanged,
    this.onCollapse,
    this.useFlatBackground = false,
    this.onSpeechPressed,
    this.speechActive = false,
    this.speechAvailable = false,
    this.onAiPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeType = controller.editorState.activeToolType;
    final vertical = dock != ToolbarDock.top;
    return FocusTraversalGroup(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              _toolbarButton(
                cs: cs,
                icon: controller.toolLocked ? Icons.lock : Icons.lock_open,
                tooltip: '保持工具激活 (Q)',
                onPressed: controller.toggleToolLocked,
                isActive: controller.toolLocked,
              ),
              _toolbarDivider(context, vertical),
              _ToolButton(
                type: ToolType.hand,
                activeType: activeType,
                colorScheme: cs,
                useFlatBackground: useFlatBackground,
                onPressed: () => controller.switchTool(ToolType.hand),
              ),
              _ToolButton(
                type: ToolType.select,
                activeType: activeType,
                colorScheme: cs,
                useFlatBackground: useFlatBackground,
                onPressed: () => controller.switchTool(ToolType.select),
              ),
              BrushPaletteButton(controller: controller, dock: dock, size: 32),
              ShapePaletteButton(controller: controller, dock: dock, size: 32),
              _ToolButton(
                type: ToolType.text,
                activeType: activeType,
                colorScheme: cs,
                useFlatBackground: useFlatBackground,
                onPressed: () => controller.switchTool(ToolType.text),
              ),
              if (onImportImage != null)
                _toolbarButton(
                  cs: cs,
                  icon: Icons.add_photo_alternate,
                  tooltip: '导入图片 (9)',
                  onPressed: onImportImage!,
                ),
              _ToolButton(
                type: ToolType.eraser,
                activeType: activeType,
                colorScheme: cs,
                useFlatBackground: useFlatBackground,
                onPressed: () => controller.switchTool(ToolType.eraser),
              ),
              _ToolButton(
                type: ToolType.laser,
                activeType: activeType,
                colorScheme: cs,
                useFlatBackground: useFlatBackground,
                onPressed: () => controller.switchTool(ToolType.laser),
              ),
              _toolbarButton(
                cs: cs,
                icon: speechActive
                    ? Icons.stop_circle_outlined
                    : Icons.mic_none,
                tooltip: speechAvailable ? '语音转文字' : '当前设备不支持语音转文字',
                onPressed: speechAvailable ? onSpeechPressed : null,
                isActive: speechActive,
              ),
              if (onAiPressed != null)
                _toolbarButton(
                  cs: cs,
                  icon: Icons.auto_awesome,
                  tooltip: 'AI 笔记助手',
                  onPressed: onAiPressed,
                ),
              _toolbarDivider(context, vertical),
              _toolbarButton(
                cs: cs,
                icon: Icons.text_fields,
                tooltip: '文字识别模式',
                onPressed: controller.toggleInkRecognitionMode,
                isActive: controller.inkRecognitionMode,
              ),
              _toolbarButton(
                cs: cs,
                icon: Icons.auto_fix_high,
                tooltip: '智能排布模式',
                onPressed: controller.toggleSmartInkLayoutMode,
                isActive: controller.smartInkLayoutMode,
              ),
              _toolbarButton(
                cs: cs,
                icon: Icons.document_scanner_outlined,
                tooltip: '全局识别排版',
                onPressed: () {
                  _runGlobalSmartLayout(context);
                },
              ),
              _toolbarDivider(context, vertical),
              _DockMenuButton(dock: dock, onDockChanged: onDockChanged),
              if (onCollapse != null)
                _toolbarButton(
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

  Widget _toolbarButton({
    required ColorScheme cs,
    IconData? icon,
    Widget? iconWidget,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: isActive,
        size: dock == ToolbarDock.top ? 32 : 28,
        onPressed: onPressed,
        child:
            iconWidget ?? Icon(icon, size: dock == ToolbarDock.top ? 20 : 18),
      ),
    );
  }

  Widget _toolbarDivider(BuildContext context, bool vertical) {
    return Padding(
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: vertical ? 16 : 2,
        height: vertical ? 1 : 20,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(99),
        ),
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

class _DockMenuButton extends StatelessWidget {
  const _DockMenuButton({required this.dock, required this.onDockChanged});

  final ToolbarDock dock;
  final ValueChanged<ToolbarDock>? onDockChanged;

  @override
  Widget build(BuildContext context) {
    final icon = switch (dock) {
      ToolbarDock.top => const Icon(Icons.vertical_align_top, size: 20),
      ToolbarDock.left => const Icon(Icons.arrow_left, size: 24),
      ToolbarDock.right => const Icon(Icons.arrow_right, size: 24),
    };
    return StudioRailIconButton(
      tooltip: '工具栏位置',
      onPressed: () async {
        final selected = await showAnchoredPopupMenu<ToolbarDock>(
          context: context,
          placement: AnchoredPopupPlacement.below,
          items: [
            for (final option in ToolbarDock.values)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Icon(_dockIcon(option), size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_dockLabel(option))),
                    if (option == dock) const Icon(Icons.check, size: 18),
                  ],
                ),
              ),
          ],
        );
        if (selected != null) {
          onDockChanged?.call(selected);
        }
      },
      child: icon,
    );
  }

  IconData _dockIcon(ToolbarDock option) => switch (option) {
    ToolbarDock.top => Icons.vertical_align_top,
    ToolbarDock.left => Icons.arrow_left,
    ToolbarDock.right => Icons.arrow_right,
  };

  String _dockLabel(ToolbarDock option) => switch (option) {
    ToolbarDock.top => '顶部',
    ToolbarDock.left => '靠左',
    ToolbarDock.right => '靠右',
  };
}

/// 压感灵敏度滑块：仅在手写工具激活时显示。
///
/// 控制压力对线条粗细的影响：左边=均匀粗细, 右边=压感最大影响。
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.type,
    required this.activeType,
    required this.colorScheme,
    required this.useFlatBackground,
    required this.onPressed,
  });

  final ToolType type;
  final ToolType activeType;
  final ColorScheme colorScheme;
  final bool useFlatBackground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final shortcut = shortcutForToolType(type);
    final label = labelForToolType(type);
    final active = activeType == type;
    final tooltip = shortcut == null ? label : '$label ($shortcut)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: StudioRailIconButton(
        tooltip: tooltip,
        selected: active,
        emphasized: active,
        useFlatBackground: useFlatBackground,
        onPressed: onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            iconWidgetFor(
              type,
              color: active
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 20,
              isActive: active,
            ),
            if (shortcut != null)
              Positioned(
                right: -6,
                bottom: -3,
                child: Text(
                  shortcut,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: active
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
