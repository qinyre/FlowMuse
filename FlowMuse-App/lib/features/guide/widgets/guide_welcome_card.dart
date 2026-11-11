import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../view_models/guide_welcome_view_model.dart';

class GuideWelcomeCard extends ConsumerWidget {
  const GuideWelcomeCard({
    super.key,
    required this.onStart,
    required this.onGuide,
  });
  final VoidCallback onStart, onGuide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(guideWelcomeProvider).asData?.value == true;
    final theme = Theme.of(context), colors = theme.colorScheme;
    void finish(VoidCallback action) {
      unawaited(ref.read(guideWelcomeProvider.notifier).dismiss());
      action();
    }

    return AnimatedSize(
      duration: AppMotion.resolve(context, AppMotion.standard),
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sectionGap),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sidebarInset),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              '欢迎来到 FlowMuse',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '不再显示欢迎介绍',
                          onPressed: () => unawaited(
                            ref.read(guideWelcomeProvider.notifier).dismiss(),
                          ),
                          icon: const Icon(LucideIcons.x, size: 18),
                        ),
                      ],
                    ),
                    Text(
                      '自然书写、PDF 批注，或和伙伴在同一页创作。先从一份笔记开始。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.listGap),
                    Wrap(
                      spacing: AppSpacing.controlGap,
                      runSpacing: AppSpacing.controlGap,
                      children: [
                        FilledButton(
                          onPressed: () => finish(onStart),
                          child: const Text('直接开始'),
                        ),
                        TextButton.icon(
                          onPressed: () => finish(onGuide),
                          icon: const Icon(LucideIcons.bookOpen, size: 18),
                          label: const Text('了解功能'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
