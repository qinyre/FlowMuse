import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../features/account/view_models/account_view_model.dart';
import 'app_spacing.dart';
import 'app_shell.dart';

class SharedSidebar extends StatelessWidget {
  const SharedSidebar({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  final Widget? header;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: sharedSidebarWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
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
      child: Column(
        children: [
          header ?? const SharedSidebarHeader(),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: children),
          ),
          ?footer,
        ],
      ),
    );
  }
}

class SharedSidebarHeader extends StatelessWidget {
  const SharedSidebarHeader({
    super.key,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.sidebarInset,
      AppSpacing.sidebarInset,
      12,
      12,
    ),
  });

  final Widget? leading;
  final List<Widget>? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final actions = trailing ?? const [];

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          leading ?? const SharedSidebarAvatar(),
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
    );
  }
}

class SharedSidebarAvatar extends ConsumerWidget {
  const SharedSidebarAvatar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountViewModelProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final identity = account.collaborationIdentity;
    final label = identity.isGuest ? identity.username : identity.username;
    final initial = label.trim().isEmpty ? '匿' : label.trim().characters.first;

    return Tooltip(
      message: identity.isGuest ? '匿名协作身份' : '账户与协作',
      child: InkWell(
        onTap: () => context.go(AppRoutes.settings),
        customBorder: const CircleBorder(),
        child: CircleAvatar(
          radius: 17,
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: account.status == AccountStatus.loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Text(
                  initial,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
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
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      iconSize: 18,
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
                      (_, final String value, _) => SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Text(
                            value,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 11,
                              height: 1.0,
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
                        icon: Icon(
                          icon,
                          color: colorScheme.onSurfaceVariant,
                          size: 16,
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: expanded
          ? Column(key: ValueKey(childrenKey), children: children)
          : SizedBox.shrink(key: ValueKey(emptyKey)),
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
        icon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 15),
      ),
    );
  }
}
