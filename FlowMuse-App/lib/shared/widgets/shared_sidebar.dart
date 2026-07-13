import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../app/app_theme_preset.dart';
import '../../app/view_models/theme_view_model.dart';
import '../../features/account/view_models/account_view_model.dart';
import '../../features/account/widgets/account_avatar.dart';
import 'app_spacing.dart';
import 'app_shell.dart';

class SharedSidebar extends ConsumerWidget {
  static const _wallpaperHeight = 180.0;

  const SharedSidebar({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.showWallpaper = true,
  });

  final Widget? header;
  final List<Widget> children;
  final Widget? footer;
  final bool showWallpaper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final preset = effectiveAppThemePreset(
      ref.watch(themeViewModelProvider),
      MediaQuery.platformBrightnessOf(context),
    );
    final hasSidebarWallpaper = showWallpaper && preset.hasWallpaper;

    return Container(
      width: sharedSidebarWidth,
      decoration: BoxDecoration(
        gradient: hasSidebarWallpaper
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.035),
                  colorScheme.primary.withValues(alpha: 0.11),
                ],
              ),
        border: Border(
          right: BorderSide(color: colorScheme.primary.withValues(alpha: 0.14)),
        ),
      ),
      child: Material(
        color: colorScheme.surfaceContainer,
        child: Stack(
          children: [
            Column(
              children: [
                header ?? const SharedSidebarHeader(),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(
                      bottom: hasSidebarWallpaper ? _wallpaperHeight : 0,
                    ),
                    children: children,
                  ),
                ),
                ?footer,
              ],
            ),
            if (hasSidebarWallpaper)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _wallpaperHeight,
                child: IgnorePointer(
                  child: Container(
                    key: const ValueKey('sidebar-bottom-wallpaper'),
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(preset.wallpaperAsset!),
                        fit: BoxFit.cover,
                        alignment: Alignment.bottomRight,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.surfaceContainer,
                            colorScheme.surfaceContainer.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SharedSidebarHeader extends StatelessWidget {
  const SharedSidebarHeader({
    super.key,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.sidebarInset, 0, 12, 0),
  });

  final Widget? leading;
  final List<Widget>? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final actions = trailing ?? const [];

    return SizedBox(
      height: AppSpacing.shellHeaderHeight,
      child: Padding(
        padding: padding,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: leading ?? const SharedSidebarAvatar(),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 0),
                    actions[index],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SharedSidebarAvatar extends ConsumerWidget {
  const SharedSidebarAvatar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountViewModelProvider);
    final identity = account.collaborationIdentity;
    final label = identity.username;
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: identity.isGuest ? '匿名协作身份' : '账户与协作',
      child: InkWell(
        onTap: () => context.push(AppRoutes.accountSettings),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: account.status == AccountStatus.loading
            ? const SizedBox(
                height: AppSpacing.shellHeaderIconButtonSize,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: AppSpacing.shellHeaderIconSize,
                      height: AppSpacing.shellHeaderIconSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ),
              )
            : SizedBox(
                height: AppSpacing.shellHeaderIconButtonSize,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccountAvatar(
                      label: label,
                      user: account.user,
                      avatarUrl: identity.avatarUrl,
                      radius: AppSpacing.shellHeaderIconSize / 2,
                    ),
                    const SizedBox(width: AppSpacing.controlGap),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontSize: 13,
                          height: 1.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class SharedSidebarIconButton extends StatelessWidget {
  const SharedSidebarIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.shellHeaderIconButtonSize,
        height: AppSpacing.shellHeaderIconButtonSize,
      ),
      padding: EdgeInsets.zero,
      iconSize: AppSpacing.shellHeaderIconSize,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: icon,
    );
  }
}

class SharedSidebarBlock extends StatelessWidget {
  const SharedSidebarBlock({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class SharedSidebarItem extends StatelessWidget {
  const SharedSidebarItem({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.count,
    this.trailingIcon,
    this.actionIcon,
    this.emptyLabel,
    this.onActionTap,
    this.onTrailingTap,
    this.onTap,
    this.level = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? count;
  final IconData? trailingIcon;
  final IconData? actionIcon;
  final String? emptyLabel;
  final VoidCallback? onActionTap;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onTap;
  final int level;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected ? colorScheme.primary : colorScheme.onSurface;

    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: colorScheme.primary.withValues(alpha: 0.12),
        highlightColor: colorScheme.primary.withValues(alpha: 0.06),
        child: SizedBox(
          height: level == 0 ? 40 : 36,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sidebarInset + level * AppSpacing.sidebarItemIndent,
              0,
              12,
              0,
            ),
            child: Row(
              children: [
                Icon(icon, color: foreground.withValues(alpha: 0.78), size: 16),
                const SizedBox(width: AppSpacing.controlGap),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: foreground,
                                fontSize: level == 0 ? 13 : 12,
                                height: 1.12,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ),
                      if (actionIcon != null) ...[
                        const SizedBox(width: 0),
                        SharedSidebarActionButton(
                          tooltip: '新建$label',
                          icon: actionIcon!,
                          onPressed: onActionTap,
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(
                  width: 64,
                  height: 32,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: switch ((emptyLabel, count, trailingIcon)) {
                      (final String label, _, _) => Text(
                        label,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.78,
                          ),
                          fontSize: 11,
                          height: 1.0,
                        ),
                      ),
                      (_, final String value, _) => Transform.translate(
                        offset: const Offset(-8, 0),
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(
                              value,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 11,
                                    height: 1.0,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      (_, _, final IconData icon) => IconButton(
                        tooltip: '$label展开收起',
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onTrailingTap,
                        icon: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.88,
                                  end: 1,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            icon,
                            key: ValueKey(icon),
                            color: colorScheme.onSurfaceVariant,
                            size: 16,
                          ),
                        ),
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SharedSidebarChildren extends StatelessWidget {
  const SharedSidebarChildren({
    super.key,
    required this.expanded,
    required this.emptyKey,
    required this.childrenKey,
    required this.children,
  });

  final bool expanded;
  final String emptyKey;
  final String childrenKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    final duration = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 300);

    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        reverseDuration: animationsDisabled
            ? Duration.zero
            : const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: animationsDisabled
              ? Duration.zero
              : const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.04),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: expanded
              ? Column(key: ValueKey(childrenKey), children: children)
              : SizedBox.shrink(key: ValueKey(emptyKey)),
        ),
      ),
    );
  }
}

class SharedSidebarActionButton extends StatelessWidget {
  const SharedSidebarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.offset = Offset.zero,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
          size: 15,
        ),
      ),
    );
  }
}
