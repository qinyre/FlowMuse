library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 悬停提示气泡：鼠标/触控笔悬停时显示，气泡本身不参与命中测试。
///
/// 不能直接用 Material [Tooltip]：其气泡外层是命中不透明的 MouseRegion
/// （见 flutter/packages/flutter/lib/src/widgets/raw_tooltip.dart 的
/// _ExclusiveMouseRegion），气泡覆盖到的控件收不到指针事件。垂直排列的
/// 按钮/属性面板中，悬停上层按钮的气泡恰好盖住下层控件的中心，导致
/// 第一次点击被吞掉（issue #31）。
///
/// 这里自绘 Overlay 气泡并包一层 [IgnorePointer]：只负责显示，永不拦截
/// 指针事件，因此任何排布下点击都直达目标控件。
class HoverTooltip extends StatefulWidget {
  const HoverTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<HoverTooltip> createState() => _HoverTooltipState();
}

class _HoverTooltipState extends State<HoverTooltip> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _hide();
    super.dispose();
  }

  // 与 Material Tooltip 一致：任意按下事件立即收起气泡（如点击后弹层已打开）。
  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _hide();
    }
  }

  void _show() {
    if (_entry != null || !mounted) return;
    final overlay = Overlay.maybeOf(context);
    final box = context.findRenderObject();
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || box is! RenderBox || overlayBox is! RenderBox) {
      return;
    }
    final anchor = overlayBox.globalToLocal(
      box.localToGlobal(box.size.center(Offset.zero)),
    );
    final entry = OverlayEntry(
      builder: (_) =>
          _HoverTooltipBubble(anchor: anchor, message: widget.message),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    // 保留 Material Tooltip 的语义：为无标签控件（如对齐按钮、样式 chips）
    // 提供无障碍 tooltip 描述。
    return Semantics(
      tooltip: widget.message,
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _hide(),
        child: widget.child,
      ),
    );
  }
}

class _HoverTooltipBubble extends StatelessWidget {
  const _HoverTooltipBubble({required this.anchor, required this.message});

  /// 触发控件的中心点（overlay 局部坐标）。
  final Offset anchor;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = switch (theme.platform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows => true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS ||
      TargetPlatform.ohos => false,
    };
    // 外观复刻 Material Tooltip 默认样式，避免视觉跳变。
    final fontSize = isDesktop ? 12.0 : 14.0;
    final (TextStyle textStyle, BoxDecoration decoration) =
        theme.brightness == Brightness.dark
        ? (
            theme.textTheme.bodyMedium!.copyWith(
              color: Colors.black,
              fontSize: fontSize,
            ),
            BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
          )
        : (
            theme.textTheme.bodyMedium!.copyWith(
              color: Colors.white,
              fontSize: fontSize,
            ),
            BoxDecoration(
              color: Colors.grey[700]!.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
          );
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _HoverTooltipLayout(anchor: anchor),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: isDesktop ? 24 : 32),
            child: Container(
              decoration: decoration,
              padding: isDesktop
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(message, style: textStyle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverTooltipLayout extends SingleChildLayoutDelegate {
  const _HoverTooltipLayout({required this.anchor});

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: anchor,
    verticalOffset: 24,
    preferBelow: true,
  );

  @override
  bool shouldRelayout(_HoverTooltipLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
