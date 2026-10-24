import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_spacing.dart';

class CollaborationViewNotice extends StatelessWidget {
  const CollaborationViewNotice({
    super.key,
    required this.label,
    required this.actionLabel,
    required this.onAction,
    this.onDismiss,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.listGap,
          vertical: 4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.controlGap),
              child: Text(
                label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
            Wrap(
              spacing: AppSpacing.controlGap,
              children: [
                TextButton(onPressed: onAction, child: Text(actionLabel)),
                if (onDismiss != null)
                  TextButton(onPressed: onDismiss, child: const Text('忽略')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
