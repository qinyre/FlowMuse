import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/account_user.dart';
import '../view_models/account_view_model.dart';

class AccountAvatar extends ConsumerWidget {
  const AccountAvatar({
    super.key,
    required this.label,
    this.user,
    this.avatarUrl,
    this.radius = 18,
  });

  final String label;
  final AccountUser? user;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final sourceUrl = avatarUrl ?? user?.avatarUrl ?? '';
    final resolvedUrl = sourceUrl.isEmpty
        ? ''
        : ref
              .read(accountViewModelProvider.notifier)
              .resolveAvatarUrl(sourceUrl);
    final initial = label.trim().isEmpty ? '匿' : label.trim().characters.first;
    final isSvg = resolvedUrl.toLowerCase().endsWith('.svg');

    if (isSvg) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
        child: ClipOval(
          child: SvgPicture.network(
            resolvedUrl,
            width: radius * 1.72,
            height: radius * 1.72,
            fit: BoxFit.contain,
            placeholderBuilder: (context) => Text(
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
