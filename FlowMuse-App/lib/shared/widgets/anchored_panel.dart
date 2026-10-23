import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../utils/app_haptics.dart';

/// 面板从锚点哪一侧展开，决定进入动画的生长方向。
enum AnchoredPanelGrowth { down, right, left }

/// 统一锚点弹出面板路由：纸面容器 + 从锚点侧展开的方向性动画。
///
/// 所有下拉/弹出菜单收口到这里，保证六端观感一致；仍然渲染调用方传入的
/// [PopupMenuEntry]，菜单项的语义、禁用态与既有 widget 测试保持不变。
class AnchoredPanelRoute<T> extends PopupRoute<T> {
  AnchoredPanelRoute({
    required this.position,
    required this.items,
    this.growth = AnchoredPanelGrowth.down,
    this.capturedThemes,
    this.barrierLabel,
    super.settings,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final AnchoredPanelGrowth growth;
  final CapturedThemes? capturedThemes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  final String? barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);

  @override
  Animation<double> createAnimation() {
    return CurvedAnimation(
      parent: super.createAnimation(),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final page = Builder(
      builder: (context) => _buildPanelPage(context, animation),
    );
    return capturedThemes?.wrap(page) ?? page;
  }

  Widget _buildPanelPage(BuildContext context, Animation<double> animation) {
    final theme = Theme.of(context);
    // 与工具栏一致的纸面容器：亮底、大圆角、细边框与三层轻阴影。
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.17),
            blurRadius: 1,
          ),
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 3,
          ),
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(4),
          // 与框架 PopupMenu 相同的收缩组合：菜单按内容收缩（IntrinsicWidth），
          // 同时保住最小可用宽度；超长菜单在面板内滚动。
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 112, maxWidth: 420),
            child: IntrinsicWidth(
              child: SingleChildScrollView(child: ListBody(children: items)),
            ),
          ),
        ),
      ),
    );
    return CustomSingleChildLayout(
      delegate: _AnchoredPanelLayoutDelegate(
        position,
        growth,
        Directionality.of(context),
        MediaQuery.paddingOf(context),
        MediaQuery.viewInsetsOf(context),
      ),
      child: _animatePanel(
        context,
        animation,
        Semantics(
          role: SemanticsRole.menu,
          label: MaterialLocalizations.of(context).popupMenuLabel,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          child: panel,
        ),
      ),
    );
  }

  Widget _animatePanel(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final alignment = switch (growth) {
      AnchoredPanelGrowth.down => Alignment.topCenter,
      AnchoredPanelGrowth.right => Alignment.centerLeft,
      AnchoredPanelGrowth.left => Alignment.centerRight,
    };
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
        alignment: alignment,
        child: child,
      ),
    );
  }

  @override
  void didComplete(T? result) {
    if (result != null) AppHaptics.selection();
    super.didComplete(result);
  }
}

/// 将面板放进锚点矩形附近的可用空间内（参照框架 PopupMenu 的布局语义：
/// 先按 position 放置，越界时向内收缩，四周保留安全边距）。
class _AnchoredPanelLayoutDelegate extends SingleChildLayoutDelegate {
  _AnchoredPanelLayoutDelegate(
    this.position,
    this.growth,
    this.textDirection,
    this.padding,
    this.viewInsets,
  );

  final RelativeRect position;
  final AnchoredPanelGrowth growth;
  final TextDirection textDirection;
  final EdgeInsets padding;
  final EdgeInsets viewInsets;

  static const double _margin = 10.0;

  EdgeInsets get _insets => EdgeInsets.fromLTRB(
    _margin + math.max(padding.left, viewInsets.left),
    _margin + math.max(padding.top, viewInsets.top),
    _margin + math.max(padding.right, viewInsets.right),
    _margin + math.max(padding.bottom, viewInsets.bottom),
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).deflate(_insets);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final insets = _insets;
    var x = position.left;
    if (growth == AnchoredPanelGrowth.left ||
        (growth == AnchoredPanelGrowth.down &&
            (position.left > position.right ||
                (position.left == position.right &&
                    textDirection == TextDirection.rtl)))) {
      x = size.width - position.right - childSize.width;
    }
    return Offset(
      x.clamp(
        insets.left,
        math.max(insets.left, size.width - insets.right - childSize.width),
      ),
      position.top.clamp(
        insets.top,
        math.max(insets.top, size.height - insets.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_AnchoredPanelLayoutDelegate oldDelegate) {
    return position != oldDelegate.position ||
        growth != oldDelegate.growth ||
        textDirection != oldDelegate.textDirection ||
        padding != oldDelegate.padding ||
        viewInsets != oldDelegate.viewInsets;
  }
}
