import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account_user.dart';
import '../view_models/account_view_model.dart';

class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({
    super.key,
    required this.label,
    this.user,
    this.radius = 18,
  });

  final String label;
  final AccountUser? user;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarUrl = user?.avatarUrl ?? '';
    final resolvedUrl = avatarUrl.isEmpty
        ? ''
        : ref
              .read(accountViewModelProvider.notifier)
              .resolveAvatarUrl(avatarUrl);
    final initial = label.trim().isEmpty ? '匿' : label.trim().characters.first;

    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      foregroundImage: resolvedUrl.isEmpty ? null : NetworkImage(resolvedUrl),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
