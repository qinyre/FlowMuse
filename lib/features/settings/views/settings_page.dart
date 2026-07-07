import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../app/app_theme_preset.dart';
import '../../../app/view_models/theme_view_model.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/shared_sidebar.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedPreset = ref.watch(themeViewModelProvider);
    final themeViewModel = ref.read(themeViewModelProvider.notifier);

    return AppShell(
      section: ShellSection.settings,
      showSidebar: false,
      child: Row(
        children: [
          _SettingsSidebar(onBack: () => context.go(AppRoutes.library)),
          Expanded(
            child: _SettingsContent(
              selectedPreset: selectedPreset,
              onPresetChanged: themeViewModel.changePreset,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SharedSidebar(
      header: SharedSidebarHeader(
        leading: SharedSidebarIconButton(
          tooltip: '返回',
          onPressed: onBack,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        trailing: [
          Text(
            '设置',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        child: SharedSidebarBlock(
          children: [
            SharedSidebarItem(
              icon: LucideIcons.circleHelp,
              label: '帮助与反馈',
              onTap: () {},
            ),
          ],
        ),
      ),
      children: [
        SharedSidebarBlock(
          children: const [
            _SettingsNavItem(
              icon: LucideIcons.download,
              label: '本地备份',
              selected: true,
            ),
            _SettingsNavItem(icon: LucideIcons.database, label: '网盘备份'),
            _SettingsNavItem(icon: LucideIcons.palette, label: '主题设置'),
            _SettingsNavItem(icon: LucideIcons.fileCog, label: '文档设置'),
            _SettingsNavItem(icon: LucideIcons.wrench, label: '工具设置'),
            _SettingsNavItem(icon: LucideIcons.penLine, label: '手写笔设置'),
            _SettingsNavItem(icon: LucideIcons.hand, label: '手势设置'),
            _SettingsNavItem(
              icon: LucideIcons.wandSparkles,
              label: 'StarNote 实验室',
              trailing: 'Beta AI',
            ),
            _SettingsNavItem(icon: LucideIcons.shield, label: '隐私设置'),
            _SettingsNavItem(icon: LucideIcons.ellipsis, label: '其他设置'),
          ],
        ),
      ],
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return SharedSidebarItem(
      icon: icon,
      label: label,
      selected: selected,
      emptyLabel: trailing,
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.selectedPreset,
    required this.onPresetChanged,
  });

  final AppThemePreset selectedPreset;
  final ValueChanged<AppThemePreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = Theme.of(context).colorScheme.primary;

    return ColoredBox(
      color: selectedColor.withValues(alpha: 0.035),
      child: Column(
        children: [
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
            ),
            child: Text(
              '本地备份',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(34, 36, 36, 0),
              children: [
                Text(
                  '上次备份时间:2026-05-28 09:29:49',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _SettingsCard(
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 26),
                    value: true,
                    onChanged: (_) {},
                    title: const Text('自动备份'),
                  ),
                ),
                const SizedBox(height: 20),
                _SettingsCard(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 26),
                    title: const Text('手动备份'),
                    trailing: Text(
                      '马上备份',
                      style: TextStyle(
                        color: selectedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const _SectionCaption(
                  title: '本地导入',
                  subtitle: '从本地备份导入的文件不会覆盖现有笔记',
                ),
                const SizedBox(height: 20),
                _SettingsCard(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 26),
                    title: const Text('导入备份'),
                    trailing: Text(
                      '导入',
                      style: TextStyle(
                        color: selectedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const _SectionCaption(title: '备份路径'),
                const SizedBox(height: 20),
                _SettingsCard(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 26),
                    title: const Text('内部储存'),
                    trailing: Icon(LucideIcons.check, color: selectedColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '路径：/storage/emulated/0/Documents/StarNote/backup',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 34),
                _ThemePresetSection(
                  selectedPreset: selectedPreset,
                  onPresetChanged: onPresetChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(height: 74, child: Center(child: child)),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: mutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: mutedColor),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemePresetSection extends StatelessWidget {
  const _ThemePresetSection({
    required this.selectedPreset,
    required this.onPresetChanged,
  });

  final AppThemePreset selectedPreset;
  final ValueChanged<AppThemePreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionCaption(
          title: '主题设置',
          subtitle: '主题是一整套视觉方案，包含明暗、强调色和背景',
        ),
        const SizedBox(height: 20),
        _ThemePresetGroup(
          title: '基础主题',
          presets: appThemePresets.take(3).toList(),
          selectedPreset: selectedPreset,
          onPresetChanged: onPresetChanged,
        ),
        const SizedBox(height: 20),
        _ThemePresetGroup(
          title: '特色主题',
          presets: appThemePresets.skip(3).toList(),
          selectedPreset: selectedPreset,
          onPresetChanged: onPresetChanged,
        ),
      ],
    );
  }
}

class _ThemePresetGroup extends StatelessWidget {
  const _ThemePresetGroup({
    required this.title,
    required this.presets,
    required this.selectedPreset,
    required this.onPresetChanged,
  });

  final String title;
  final List<AppThemePreset> presets;
  final AppThemePreset selectedPreset;
  final ValueChanged<AppThemePreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in presets)
                    _ThemePresetChip(
                      preset: preset,
                      selected: preset.id == selectedPreset.id,
                      onSelected: () => onPresetChanged(preset),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePresetChip extends StatelessWidget {
  const _ThemePresetChip({
    required this.preset,
    required this.selected,
    required this.onSelected,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;

    return Tooltip(
      message: preset.description,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 112,
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            color: selected
                ? preset.seedColor.withValues(alpha: 0.10)
                : Theme.of(context).cardTheme.color,
          ),
          child: Row(
            children: [
              _ThemeSwatch(preset: preset),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  preset.label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.preset});

  final AppThemePreset preset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            preset.backgroundStart,
            preset.seedColor,
            preset.backgroundEnd,
          ],
        ),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const SizedBox(width: 22, height: 22),
    );
  }
}
