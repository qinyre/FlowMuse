import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../app/social_overlay.dart';
import '../../../shared/widgets/app_motion.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/widgets/shared_sidebar.dart';
import '../models/guide_topic.dart';
import '../widgets/guide_illustration.dart';

class UserGuidePage extends ConsumerStatefulWidget {
  const UserGuidePage({super.key, required this.topic});
  final GuideTopic topic;

  @override
  ConsumerState<UserGuidePage> createState() => _UserGuidePageState();
}

class _UserGuidePageState extends ConsumerState<UserGuidePage> {
  final _scroll = ScrollController();

  void _select(GuideTopic topic) {
    if (topic != widget.topic) {
      context.replace(AppRoutes.guideTopicPath(topic.name));
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.library);
    }
  }

  void _openAction(GuideAction action) {
    final location = switch (action) {
      GuideAction.createNote => AppRoutes.createNote,
      GuideAction.library => AppRoutes.library,
      GuideAction.social => null,
      GuideAction.stylus => '${AppRoutes.settings}?section=stylus',
      GuideAction.ai => '${AppRoutes.settings}?section=lab',
      GuideAction.backup => '${AppRoutes.settings}?section=localBackup',
    };
    // Push keeps the originating notebook/settings route and its state alive.
    if (location != null) {
      context.push(location);
      return;
    }
    final openFromBoard = ref
        .read(socialInboxPresenterProvider)
        .openInboxFromWhiteboard;
    if (openFromBoard != null) {
      openFromBoard();
    } else {
      showSocialOverlay(context);
    }
  }

  @override
  void didUpdateWidget(covariant UserGuidePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topic != widget.topic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final article = guideArticles[widget.topic]!;
    return AppShell(
      section: ShellSection.settings,
      showSidebar: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 1000 &&
              MediaQuery.textScalerOf(context).scale(16) < 24;
          return Row(
            children: [
              if (wide)
                SharedSidebar(
                  showWallpaper: false,
                  header: SharedSidebarHeader(
                    leading: Text(
                      '使用指南',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  footer: Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSpacing.sidebarInset,
                    ),
                    child: SharedSidebarItem(
                      icon: LucideIcons.arrowLeft,
                      label: '返回应用',
                      onTap: _back,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sidebarInset),
                      child: Text(
                        '记录、理解、一起创作',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final topic in GuideTopic.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.controlGap,
                          vertical: 2,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radius,
                          ),
                          child: SharedSidebarItem(
                            icon: _topicIcon(topic),
                            label: topic.label,
                            selected: topic == widget.topic,
                            onTap: () => _select(topic),
                          ),
                        ),
                      ),
                  ],
                ),
              Expanded(
                child: RightPageScaffold(
                  title: widget.topic.label,
                  leadingActions: [
                    IconButton(
                      tooltip: '返回应用',
                      onPressed: _back,
                      icon: const Icon(LucideIcons.arrowLeft),
                    ),
                  ],
                  actions: [
                    if (!wide)
                      IconButton(
                        tooltip: '指南目录',
                        icon: const Icon(LucideIcons.list),
                        onPressed: () async {
                          final topic = await showModalBottomSheet<GuideTopic>(
                            context: context,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (context) => SafeArea(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.sidebarInset,
                                      ),
                                      child: Text(
                                        '使用指南目录',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                    ),
                                    for (final topic in GuideTopic.values)
                                      ListTile(
                                        leading: Icon(_topicIcon(topic)),
                                        title: Text(topic.label),
                                        selected: topic == widget.topic,
                                        selectedTileColor:
                                            colors.primaryContainer,
                                        onTap: () =>
                                            Navigator.pop(context, topic),
                                      ),
                                    const SizedBox(
                                      height: AppSpacing.sidebarInset,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                          if (topic != null && mounted) _select(topic);
                        },
                      ),
                  ],
                  body: AnimatedSwitcher(
                    duration: AppMotion.resolve(context, AppMotion.standard),
                    layoutBuilder: (child, _) =>
                        child ?? const SizedBox.shrink(),
                    child: ListView(
                      key: ValueKey(widget.topic),
                      controller: _scroll,
                      padding: const EdgeInsets.only(
                        bottom: AppSpacing.pageInset,
                      ),
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1040),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _GuideHero(
                                  topic: widget.topic,
                                  article: article,
                                ),
                                const SizedBox(height: AppSpacing.sectionGap),
                                Wrap(
                                  spacing: AppSpacing.controlGap,
                                  runSpacing: AppSpacing.controlGap,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () =>
                                          _openAction(article.action),
                                      icon: const Icon(
                                        LucideIcons.arrowUpRight,
                                        size: 18,
                                      ),
                                      label: Text(article.actionLabel),
                                    ),
                                    if (widget.topic != GuideTopic.start)
                                      TextButton(
                                        onPressed: () =>
                                            _select(GuideTopic.start),
                                        child: const Text('回到快速开始'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.pageInset),
                                for (
                                  var i = 0;
                                  i < article.sections.length;
                                  i++
                                ) ...[
                                  _GuideSectionView(
                                    index: i + 1,
                                    section: article.sections[i],
                                  ),
                                  const SizedBox(height: AppSpacing.sectionGap),
                                ],
                                Container(
                                  padding: const EdgeInsets.all(
                                    AppSpacing.sidebarInset,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radius,
                                    ),
                                    border: Border(
                                      left: BorderSide(
                                        color: colors.primary,
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '使用前了解',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(
                                        height: AppSpacing.controlGap,
                                      ),
                                      Text(
                                        article.note,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              height: 1.65,
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.sectionGap),
                                if (widget.topic == GuideTopic.start) ...[
                                  Text(
                                    '继续了解',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: AppSpacing.listGap),
                                  for (final topic in GuideTopic.values.skip(1))
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(_topicIcon(topic)),
                                      title: Text(topic.label),
                                      subtitle: Text(topic.headline),
                                      trailing: const Icon(
                                        LucideIcons.chevronRight,
                                        size: 18,
                                      ),
                                      onTap: () => _select(topic),
                                    ),
                                ] else
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '按自己的节奏探索，随时可以回来。',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: AppSpacing.controlGap,
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _select(
                                          GuideTopic
                                              .values[(widget.topic.index + 1) %
                                              GuideTopic.values.length],
                                        ),
                                        icon: const Icon(
                                          LucideIcons.arrowRight,
                                          size: 16,
                                        ),
                                        label: Text(
                                          widget.topic == GuideTopic.values.last
                                              ? '快速开始'
                                              : '下一章',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideHero extends StatelessWidget {
  const _GuideHero({required this.topic, required this.article});
  final GuideTopic topic;
  final GuideArticle article;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FLOWMUSE  /  ${topic.index + 1} · ${GuideTopic.values.length}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            topic.headline,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sidebarInset),
        Text(
          article.summary,
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.75,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 760 &&
            MediaQuery.textScalerOf(context).scale(16) < 24) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 6, child: copy),
              const SizedBox(width: AppSpacing.pageInset),
              Expanded(flex: 5, child: GuideIllustration(topic: topic)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copy,
            const SizedBox(height: AppSpacing.sectionGap),
            GuideIllustration(topic: topic),
          ],
        );
      },
    );
  }
}

class _GuideSectionView extends StatelessWidget {
  const _GuideSectionView({required this.index, required this.section});
  final int index;
  final GuideSection section;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  section.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.listGap),
        for (var i = 0; i < section.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(
              left: 32,
              bottom: AppSpacing.listGap,
            ),
            child: Text(
              section.steps[i],
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
            ),
          ),
      ],
    );
  }
}

IconData _topicIcon(GuideTopic topic) => switch (topic) {
  GuideTopic.start => LucideIcons.bookOpen,
  GuideTopic.writing => LucideIcons.penLine,
  GuideTopic.pdf => LucideIcons.fileText,
  GuideTopic.collaboration => LucideIcons.users,
  GuideTopic.smart => LucideIcons.sparkles,
  GuideTopic.library => LucideIcons.notebook,
  GuideTopic.backup => LucideIcons.archive,
  GuideTopic.messages => LucideIcons.messagesSquare,
};
