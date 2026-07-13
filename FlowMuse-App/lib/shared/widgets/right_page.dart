import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_router.dart';
import 'app_shell.dart';
import 'app_spacing.dart';

const _headerEnterDuration = Duration(milliseconds: 340);
const _headerExitDuration = Duration(milliseconds: 260);

Duration _headerMotionDuration(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : _headerEnterDuration;
}

Duration _headerReverseDuration(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : _headerExitDuration;
}

class RightPageScaffold extends StatelessWidget {
  const RightPageScaffold({
    super.key,
    this.title,
    this.header,
    this.leadingActions = const [],
    this.actions = const [],
    this.topContent = const [],
    this.forceCenterTitle = false,
    required this.body,
  }) : assert(title != null || header != null);

  final String? title;
  final Widget? header;
  final List<Widget> leadingActions;
  final List<Widget> actions;
  final List<Widget> topContent;
  final bool forceCenterTitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final chrome = AppShellScope.maybeOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            chrome?.compact ?? constraints.maxWidth < shellCompactBreakpoint;

        final pagePadding = AppSpacing.pagePadding(compact: compact);

        return Padding(
          padding: pagePadding.copyWith(top: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RightPageHeader(
                title: title,
                header: header,
                leadingActions: leadingActions,
                actions: actions,
                forceCenterTitle: forceCenterTitle,
              ),
              for (final child in topContent) child,
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: body,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RightPageHeader extends StatelessWidget {
  const RightPageHeader({
    super.key,
    this.title,
    this.header,
    this.leadingActions = const [],
    this.actions = const [],
    this.forceCenterTitle = false,
  }) : assert(title != null || header != null);

  final String? title;
  final Widget? header;
  final List<Widget> leadingActions;
  final List<Widget> actions;
  final bool forceCenterTitle;

  static const _controlWidth =
      AppSpacing.shellHeaderIconButtonSize * 2 + AppSpacing.controlGap;

  @override
  Widget build(BuildContext context) {
    final chrome = AppShellScope.maybeOf(context);
    final showSidebarControls = chrome?.showSidebarControls ?? false;
    final centerTitle = forceCenterTitle || (chrome?.contentFullWidth ?? false);
    final sidebarLeading = showSidebarControls
        ? _RightPageSidebarControls(onOpenSidebar: chrome?.openSidebar)
        : null;
    final leading = _RightPageActions(actions: leadingActions);
    final trailing = _RightPageActions(actions: actions);

    if (header != null) {
      return SizedBox(
        height: AppSpacing.shellHeaderHeight,
        child: Row(
          children: [
            _AnimatedHeaderSlot(
              visible: sidebarLeading != null,
              width: _controlWidth + AppSpacing.controlGap,
              child: SizedBox(width: _controlWidth, child: sidebarLeading),
            ),
            if (leadingActions.isNotEmpty) ...[
              leading,
              const SizedBox(width: AppSpacing.controlGap),
            ],
            Expanded(
              child: Align(alignment: Alignment.center, child: header!),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.controlGap),
              trailing,
            ],
          ],
        ),
      );
    }

    final sidebarReserve = showSidebarControls
        ? _controlWidth + AppSpacing.controlGap
        : 0.0;
    final leadingReserve = leadingActions.isEmpty
        ? 0.0
        : _actionsWidth(leadingActions.length) + AppSpacing.controlGap;
    final trailingReserve = actions.isEmpty
        ? 0.0
        : _actionsWidth(actions.length) + AppSpacing.controlGap;
    final leftReserve = sidebarReserve + leadingReserve;
    final symmetricReserve = leftReserve > trailingReserve
        ? leftReserve
        : trailingReserve;
    final titlePadding = EdgeInsets.only(
      left: centerTitle ? symmetricReserve : leftReserve,
      right: centerTitle ? symmetricReserve : trailingReserve,
    );

    return SizedBox(
      height: AppSpacing.shellHeaderHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                _AnimatedHeaderSlot(
                  visible: sidebarLeading != null,
                  width: _controlWidth + AppSpacing.controlGap,
                  child: SizedBox(width: _controlWidth, child: sidebarLeading),
                ),
                if (leadingActions.isNotEmpty) leading,
              ],
            ),
          ),
          Positioned.fill(
            child: AnimatedPadding(
              duration: _headerMotionDuration(context),
              curve: Curves.easeOutCubic,
              padding: titlePadding,
              child: AnimatedAlign(
                duration: _headerMotionDuration(context),
                curve: Curves.easeOutCubic,
                alignment: centerTitle
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: _AnimatedRightPageTitle(
                  title: title!,
                  textAlign: centerTitle ? TextAlign.center : null,
                ),
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Positioned.fill(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
        ],
      ),
    );
  }

  static double _actionsWidth(int count) {
    if (count == 0) {
      return 0;
    }
    return count * AppSpacing.shellHeaderIconButtonSize +
        (count - 1) * AppSpacing.controlGap;
  }
}

class _RightPageIconButtonTheme extends StatelessWidget {
  const _RightPageIconButtonTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconTheme.merge(
      data: const IconThemeData(size: AppSpacing.shellHeaderIconSize),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(
              Size.square(AppSpacing.shellHeaderIconButtonSize),
            ),
            minimumSize: const WidgetStatePropertyAll(
              Size.square(AppSpacing.shellHeaderIconButtonSize),
            ),
            maximumSize: const WidgetStatePropertyAll(
              Size.square(AppSpacing.shellHeaderIconButtonSize),
            ),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            iconSize: const WidgetStatePropertyAll(
              AppSpacing.shellHeaderIconSize,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _AnimatedHeaderSlot extends StatelessWidget {
  const _AnimatedHeaderSlot({
    required this.visible,
    required this.width,
    required this.child,
  });

  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedContainer(
        width: visible ? width : 0,
        duration: _headerMotionDuration(context),
        curve: Curves.easeOutCubic,
        child: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: _headerMotionDuration(context),
            reverseDuration: _headerReverseDuration(context),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(-0.08, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: visible
                ? KeyedSubtree(key: const ValueKey('visible'), child: child)
                : SizedBox(key: const ValueKey('hidden'), width: width),
          ),
        ),
      ),
    );
  }
}

class _AnimatedRightPageTitle extends StatelessWidget {
  const _AnimatedRightPageTitle({required this.title, this.textAlign});

  final String title;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _headerMotionDuration(context),
      reverseDuration: _headerReverseDuration(context),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.02, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: _RightPageTitle(
        key: ValueKey(title),
        title: title,
        textAlign: textAlign,
      ),
    );
  }
}

class _RightPageTitle extends StatelessWidget {
  const _RightPageTitle({super.key, required this.title, this.textAlign});

  final String title;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _RightPageSidebarControls extends StatelessWidget {
  const _RightPageSidebarControls({required this.onOpenSidebar});

  final VoidCallback? onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    return _RightPageIconButtonTheme(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '打开侧边栏',
            onPressed: onOpenSidebar,
            icon: const Icon(LucideIcons.panelLeftOpen),
          ),
          const SizedBox(width: AppSpacing.controlGap),
          IconButton(
            tooltip: '设置',
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(LucideIcons.settings),
          ),
        ],
      ),
    );
  }
}

class _RightPageActions extends StatelessWidget {
  const _RightPageActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return _RightPageIconButtonTheme(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.controlGap),
            actions[index],
          ],
        ],
      ),
    );
  }
}
