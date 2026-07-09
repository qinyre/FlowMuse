import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../app/app_theme_preset.dart';
import '../../../app/view_models/theme_view_model.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/widgets/shared_sidebar.dart';
import '../../account/view_models/account_view_model.dart';
import '../../library/repositories/library_repository.dart';
import '../repositories/local_backup_repository.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.showAccountFirst});

  final bool? showAccountFirst;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late _SettingsSection _section;

  @override
  void initState() {
    super.initState();
    _section = _initialSectionFor(widget.showAccountFirst);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showAccountFirst != widget.showAccountFirst) {
      _section = _initialSectionFor(widget.showAccountFirst);
    }
  }

  _SettingsSection _initialSectionFor(bool? showAccountFirst) {
    return showAccountFirst == true
        ? _SettingsSection.account
        : _SettingsSection.localBackup;
  }

  @override
  Widget build(BuildContext context) {
    final selectedPreset = ref.watch(themeViewModelProvider);
    final themeViewModel = ref.read(themeViewModelProvider.notifier);

    return AppShell(
      section: ShellSection.settings,
      showSidebar: false,
      child: Row(
        children: [
          _SettingsSidebar(
            selected: _section,
            onSelected: (section) => setState(() => _section = section),
            onBack: () => context.go(AppRoutes.library),
          ),
          Expanded(
            child: _SettingsContent(
              section: _section,
              selectedPreset: selectedPreset,
              onPresetChanged: themeViewModel.changePreset,
            ),
          ),
        ],
      ),
    );
  }
}

enum _SettingsSection {
  account(LucideIcons.userRound, '账户与协作', '邮箱账号、匿名身份与协作房间身份'),
  localBackup(LucideIcons.download, '本地备份', '导出和恢复本机库索引、白板场景与主题设置'),
  cloudBackup(LucideIcons.database, '网盘备份', '云端同步入口预留'),
  theme(LucideIcons.palette, '主题设置', '切换当前工作区视觉主题'),
  document(LucideIcons.fileCog, '文档设置', '默认文档行为预留'),
  tools(LucideIcons.wrench, '工具设置', '绘图工具偏好预留'),
  stylus(LucideIcons.penLine, '手写笔设置', '压感与笔输入预留'),
  gestures(LucideIcons.hand, '手势设置', '触控手势预留'),
  lab(LucideIcons.wandSparkles, 'StarNote 实验室', 'Beta AI'),
  privacy(LucideIcons.shield, '隐私设置', '本地数据与权限预留'),
  other(LucideIcons.ellipsis, '其他设置', '通用设置预留');

  const _SettingsSection(this.icon, this.label, this.description);

  final IconData icon;
  final String label;
  final String description;
}

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.selected,
    required this.onSelected,
    required this.onBack,
  });

  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;
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
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.controlGap, 0, 16),
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
          children: [
            for (final section in _SettingsSection.values)
              _SettingsNavItem(
                icon: section.icon,
                label: section.label,
                selected: section == selected,
                trailing: section == _SettingsSection.lab ? 'Beta AI' : null,
                onTap: () => onSelected(section),
              ),
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
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SharedSidebarItem(
      icon: icon,
      label: label,
      selected: selected,
      emptyLabel: trailing,
      onTap: onTap,
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.section,
    required this.selectedPreset,
    required this.onPresetChanged,
  });

  final _SettingsSection section;
  final AppThemePreset selectedPreset;
  final ValueChanged<AppThemePreset> onPresetChanged;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;

    return ColoredBox(
      color: selectedColor.withValues(alpha: 0.035),
      child: RightPageScaffold(
        title: section.label,
        forceCenterTitle: true,
        body: _SettingsSectionBody(
          section: section,
          selectedPreset: selectedPreset,
          onPresetChanged: onPresetChanged,
        ),
      ),
    );
  }
}

class _SettingsSectionBody extends ConsumerStatefulWidget {
  const _SettingsSectionBody({
    required this.section,
    required this.selectedPreset,
    required this.onPresetChanged,
  });

  final _SettingsSection section;
  final AppThemePreset selectedPreset;
  final ValueChanged<AppThemePreset> onPresetChanged;

  @override
  ConsumerState<_SettingsSectionBody> createState() =>
      _SettingsSectionBodyState();
}

class _SettingsSectionBodyState extends ConsumerState<_SettingsSectionBody> {
  bool _backupBusy = false;
  String? _backupMessage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageInset,
        0,
        AppSpacing.pageInset,
        0,
      ),
      children: [
        _SectionCaption(
          title: widget.section.label,
          subtitle: widget.section.description,
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        switch (widget.section) {
          _SettingsSection.account => const _AccountSettingsSection(),
          _SettingsSection.localBackup => _LocalBackupSection(
            busy: _backupBusy,
            message: _backupMessage,
            onExport: _exportBackup,
            onImport: _importBackup,
          ),
          _SettingsSection.theme => _ThemePresetSection(
            selectedPreset: widget.selectedPreset,
            onPresetChanged: widget.onPresetChanged,
          ),
          _ => _PlaceholderSettingsSection(section: widget.section),
        },
      ],
    );
  }

  Future<void> _exportBackup() async {
    setState(() {
      _backupBusy = true;
      _backupMessage = null;
    });
    try {
      final payload = await defaultLocalBackupRepository.exportBackup();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 FlowMuse 备份',
        fileName: 'flowmuse-backup.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _backupMessage = path == null ? '已取消导出' : '备份已导出';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupMessage = '导出失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<void> _importBackup() async {
    setState(() {
      _backupBusy = true;
      _backupMessage = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '导入 FlowMuse 备份',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) {
          setState(() => _backupMessage = '已取消导入');
        }
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('未读取到备份文件内容');
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      await defaultLocalBackupRepository.importBackup(decoded);
      if (!mounted) {
        return;
      }
      ref.invalidate(libraryIndexProvider);
      setState(() {
        _backupMessage = '备份已导入';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _backupMessage = '导入失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }
}

class _LocalBackupSection extends StatelessWidget {
  const _LocalBackupSection({
    required this.busy,
    required this.message,
    required this.onExport,
    required this.onImport,
  });

  final bool busy;
  final String? message;
  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(LucideIcons.download),
            title: const Text('导出本地备份'),
            subtitle: const Text('包含库索引、白板场景和主题设置'),
            trailing: Text(
              busy ? '处理中' : '导出',
              style: TextStyle(
                color: busy ? mutedColor : selectedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: busy ? null : onExport,
          ),
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(LucideIcons.upload),
            title: const Text('导入本地备份'),
            subtitle: const Text('会恢复备份文件中的本地数据键'),
            trailing: Text(
              busy ? '处理中' : '导入',
              style: TextStyle(
                color: busy ? mutedColor : selectedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: busy ? null : onImport,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.controlGap),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(
              message!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: mutedColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountSettingsSection extends ConsumerStatefulWidget {
  const _AccountSettingsSection();

  @override
  ConsumerState<_AccountSettingsSection> createState() =>
      _AccountSettingsSectionState();
}

class _AccountSettingsSectionState
    extends ConsumerState<_AccountSettingsSection> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountViewModelProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;

    if (account.isAuthenticated) {
      final user = account.user!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: CircleAvatar(
                backgroundColor: selectedColor.withValues(alpha: 0.12),
                child: Text(
                  user.collaboratorName.characters.first,
                  style: TextStyle(
                    color: selectedColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(user.collaboratorName),
              subtitle: Text(user.email),
              trailing: Text(
                '已登录',
                style: TextStyle(
                  color: selectedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.usersRound),
              title: const Text('协作身份'),
              subtitle: const Text('创建协作房间时会记录房主，访客仍可通过链接加入'),
              trailing: Text(
                user.collaboratorName,
                style: TextStyle(
                  color: selectedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.logOut),
              title: const Text('退出登录'),
              subtitle: const Text('退出后继续使用匿名协作身份'),
              trailing: const Text('退出'),
              onTap: _busy ? null : _logout,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(LucideIcons.userRound),
            title: Text(account.collaborationIdentity.username),
            subtitle: const Text('当前使用匿名协作身份，可通过链接加入房间'),
            trailing: const Text('访客'),
          ),
        ),
        const SizedBox(height: 16),
        Card.outlined(
          color: colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _registerMode ? '注册邮箱账号' : '登录邮箱账号',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: '邮箱'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                if (_registerMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(labelText: '昵称'),
                  ),
                ],
                if (account.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    account.error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? '处理中'
                            : _registerMode
                            ? '注册并登录'
                            : '登录',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.controlGap),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                setState(() => _registerMode = !_registerMode),
                      child: Text(_registerMode ? '已有账号，去登录' : '注册新账号'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final viewModel = ref.read(accountViewModelProvider.notifier);
      if (_registerMode) {
        await viewModel.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _displayNameController.text.trim(),
        );
      } else {
        await viewModel.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await ref.read(accountViewModelProvider.notifier).logout();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _PlaceholderSettingsSection extends StatelessWidget {
  const _PlaceholderSettingsSection({required this.section});

  final _SettingsSection section;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: Icon(section.icon),
        title: Text(section.label),
        subtitle: const Text('该设置分区已接入导航，具体配置项待后续实现'),
        trailing: const Text('未启用'),
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
      child: SizedBox(height: 72, child: Center(child: child)),
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
      padding: const EdgeInsets.only(left: 24),
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
            const SizedBox(height: AppSpacing.controlGap),
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
        const SizedBox(height: 16),
        _ThemePresetGroup(
          title: '基础主题',
          presets: appThemePresets.take(3).toList(),
          selectedPreset: selectedPreset,
          onPresetChanged: onPresetChanged,
        ),
        const SizedBox(height: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.controlGap,
                runSpacing: AppSpacing.controlGap,
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
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Container(
          width: 116,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            color: selected
                ? preset.seedColor.withValues(alpha: 0.10)
                : Theme.of(context).cardTheme.color,
          ),
          child: Row(
            children: [
              _ThemeSwatch(preset: preset),
              const SizedBox(width: AppSpacing.controlGap),
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
