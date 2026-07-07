import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                if (index > 0) const SizedBox(width: 4),
                actions[index],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SharedSidebarAvatar extends StatelessWidget {
  const SharedSidebarAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.12),
      child: Icon(
        LucideIcons.sparkles,
        color: Theme.of(context).colorScheme.primary,
        size: 19,
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
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
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
    this.leadingAction = false,
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
  final bool leadingAction;
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
            padding: EdgeInsets.fromLTRB(14 + level * 18, 0, 10, 0),
            child: Row(
              children: [
                Icon(icon, color: foreground.withValues(alpha: 0.78), size: 16),
                const SizedBox(width: 9),
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
                      if (leadingAction && actionIcon != null) ...[
                        const SizedBox(width: 6),
                        SharedSidebarActionButton(
                          tooltip: '新建$label',
                          icon: actionIcon!,
                          onPressed: onActionTap,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!leadingAction && actionIcon != null) ...[
                  SharedSidebarActionButton(
                    tooltip: '新建$label',
                    icon: actionIcon!,
                    onPressed: onActionTap,
                  ),
                  const SizedBox(width: 8),
                ],
                if (count != null)
                  Text(
                    count!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.0,
                    ),
                  ),
                if (emptyLabel != null)
                  Text(
                    emptyLabel!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.78,
                      ),
                      fontSize: 11,
                      height: 1.0,
                    ),
                  ),
                if (trailingIcon != null)
                  IconButton(
                    tooltip: '$label展开收起',
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: onTrailingTap,
                    icon: Icon(
                      trailingIcon,
                      color: colorScheme.onSurfaceVariant,
                      size: 16,
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 15),
    );
  }
}
