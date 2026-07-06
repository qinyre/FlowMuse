import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../app/view_models/theme_view_model.dart';
import '../../../shared/widgets/app_shell.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedColor = ref.watch(themeViewModelProvider);
    final themeViewModel = ref.read(themeViewModelProvider.notifier);

    return AppShell(
      section: ShellSection.settings,
      showSidebar: false,
      child: Row(
        children: [
          SizedBox(
            width: sharedSidebarWidth,
            child: _SettingsSidebar(
              selectedColor: selectedColor,
              onBack: () => context.go(AppRoutes.library),
            ),
          ),
          Expanded(
            child: _SettingsContent(
              selectedColor: selectedColor,
              onColorChanged: themeViewModel.changeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({required this.selectedColor, required this.onBack});

  final Color selectedColor;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFFCFEFD),
        border: Border(right: BorderSide(color: Color(0xFFE8EFEA))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 56),
            child: IconButton(
              tooltip: '返回',
              onPressed: onBack,
              icon: const Icon(LucideIcons.chevronLeft, size: 30),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '设置',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2624),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _SettingsNavItem(
                  icon: LucideIcons.download,
                  label: '本地备份',
                  selected: true,
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.database,
                  label: '网盘备份',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.palette,
                  label: '主题设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.fileCog,
                  label: '文档设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.wrench,
                  label: '工具设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.penLine,
                  label: '手写笔设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.hand,
                  label: '手势设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.wandSparkles,
                  label: 'StarNote 实验室',
                  trailing: 'Beta  AI',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.shield,
                  label: '隐私设置',
                  selectedColor: selectedColor,
                ),
                _SettingsNavItem(
                  icon: LucideIcons.ellipsis,
                  label: '其他设置',
                  selectedColor: selectedColor,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: Row(
              children: [
                Icon(LucideIcons.circleHelp, color: selectedColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  '帮助与反馈',
                  style: TextStyle(
                    color: selectedColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.selectedColor,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color selectedColor;
  final bool selected;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? selectedColor : const Color(0xFF202827);

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      color: selected ? selectedColor.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 26),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: selectedColor.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  trailing!,
                  style: TextStyle(color: selectedColor, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.selectedColor,
    required this.onColorChanged,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: selectedColor.withValues(alpha: 0.035),
      child: Column(
        children: [
          Container(
            height: 96,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE7F0EC))),
            ),
            child: Text(
              '本地备份',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1F2624),
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
                    color: const Color(0xFFA5AFAA),
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
                    color: const Color(0xFFA5AFAA),
                  ),
                ),
                const SizedBox(height: 34),
                _ThemeColorSection(
                  selectedColor: selectedColor,
                  onColorChanged: onColorChanged,
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
      color: const Color(0xFFFCFEFD),
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
    return Padding(
      padding: const EdgeInsets.only(left: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: const Color(0xFFA5AFAA),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFA5AFAA)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeColorSection extends StatelessWidget {
  const _ThemeColorSection({
    required this.selectedColor,
    required this.onColorChanged,
  });

  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Row(
          children: [
            const Expanded(child: Text('主题设置')),
            IconButton(
              tooltip: '选择主题色',
              onPressed: () => _showThemeColorDialog(context),
              icon: DecoratedBox(
                decoration: BoxDecoration(
                  color: selectedColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2ECE7)),
                ),
                child: const SizedBox(width: 34, height: 34),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThemeColorDialog(BuildContext context) async {
    var pendingColor = selectedColor;

    final nextColor = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('主题色'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: selectedColor,
              onColorChanged: (color) => pendingColor = color,
              enableAlpha: false,
              labelTypes: const [],
              pickerAreaBorderRadius: BorderRadius.circular(8),
              hexInputBar: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(pendingColor),
              child: const Text('应用'),
            ),
          ],
        );
      },
    );

    if (nextColor != null) {
      onColorChanged(nextColor);
    }
  }
}
