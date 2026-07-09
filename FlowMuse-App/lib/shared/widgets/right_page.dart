import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/app_router.dart';
import 'app_shell.dart';
import 'app_spacing.dart';

class RightPageScaffold extends StatelessWidget {
  const RightPageScaffold({
    super.key,
    this.title,
    this.header,
    this.actions = const [],
    this.topContent = const [],
    this.forceCenterTitle = false,
    required this.body,
  }) : assert(title != null || header != null);

  final String? title;
  final Widget? header;
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

        return Padding(
          padding: AppSpacing.pagePadding(compact: compact),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RightPageHeader(
                title: title,
                header: header,
                actions: actions,
                forceCenterTitle: forceCenterTitle,
              ),
              const SizedBox(height: AppSpacing.headerToContent),
              for (final child in topContent) child,
              Expanded(child: body),
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
    this.actions = const [],
    this.forceCenterTitle = false,
  }) : assert(title != null || header != null);

  final String? title;
  final Widget? header;
  final List<Widget> actions;
  final bool forceCenterTitle;

  static const _controlWidth = 88.0;

  @override
  Widget build(BuildContext context) {
    final chrome = AppShellScope.maybeOf(context);
    final showSidebarControls = chrome?.showSidebarControls ?? false;
    final centerTitle = forceCenterTitle || (chrome?.contentFullWidth ?? false);
    final leading = showSidebarControls
        ? _RightPageSidebarControls(onOpenSidebar: chrome?.openSidebar)
        : null;
    final trailing = _RightPageActions(actions: actions);

    if (header != null) {
      return SizedBox(
        height: AppSpacing.shellHeaderHeight,
        child: Row(
          children: [
            if (leading != null) ...[
              SizedBox(width: _controlWidth, child: leading),
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

    if (centerTitle) {
      final leftReserve = showSidebarControls ? _controlWidth : 0.0;
      final rightReserve = _actionsWidth(actions.length);
      final horizontalReserve =
          (leftReserve > rightReserve ? leftReserve : rightReserve) +
          AppSpacing.controlGap;

      return SizedBox(
        height: AppSpacing.shellHeaderHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (leading != null)
              Positioned(
                left: 0,
                child: SizedBox(width: _controlWidth, child: leading),
              ),
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalReserve),
                child: _RightPageTitle(
                  title: title!,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (actions.isNotEmpty) Positioned(right: 0, child: trailing),
          ],
        ),
      );
    }

    return SizedBox(
      height: AppSpacing.shellHeaderHeight,
      child: Row(
        children: [
          if (leading != null) ...[
            SizedBox(width: _controlWidth, child: leading),
            const SizedBox(width: AppSpacing.controlGap),
          ],
          Expanded(child: _RightPageTitle(title: title!)),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.controlGap),
            trailing,
          ],
        ],
      ),
    );
  }

  static double _actionsWidth(int count) {
    if (count == 0) {
      return 0;
    }
    return count * 48.0 + (count - 1) * AppSpacing.controlGap;
  }
}

class _RightPageTitle extends StatelessWidget {
  const _RightPageTitle({required this.title, this.textAlign});

  final String title;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: const Color(0xFF1F2624),
      ),
    );
  }
}

class _RightPageSidebarControls extends StatelessWidget {
  const _RightPageSidebarControls({required this.onOpenSidebar});

  final VoidCallback? onOpenSidebar;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          onPressed: () => context.go(AppRoutes.settings),
          icon: const Icon(LucideIcons.settings),
        ),
      ],
    );
  }
}

class _RightPageActions extends StatelessWidget {
  const _RightPageActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.controlGap),
          actions[index],
        ],
      ],
    );
  }
}
