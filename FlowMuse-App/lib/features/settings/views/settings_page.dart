import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../app/app_theme_preset.dart';
import '../../../app/view_models/theme_view_model.dart';
import '../../../shared/storage/local_database_path.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/app_spacing.dart';
import '../../../shared/widgets/right_page.dart';
import '../../../shared/widgets/shared_sidebar.dart';
import '../../../shared/widgets/theme_hero.dart';
import '../../account/view_models/account_view_model.dart';
import '../../account/widgets/account_avatar.dart';
import '../../library/models/note_item.dart';
import '../../library/repositories/library_repository.dart';
import '../../whiteboard/ai_assistant/repositories/ai_agent_config_store.dart';
import '../../whiteboard/editor_core/flow_muse_whiteboard_editor.dart';
import '../../whiteboard/models/editor_preferences.dart';
import '../../whiteboard/view_models/editor_preferences_view_model.dart';
import '../repositories/local_backup_repository.dart';
import '../services/cache_cleaner.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  /// Optional initial section id (the enum [name]) to open directly, e.g.
  /// passed from the `/settings?section=theme` route query parameter.
  final String? initialSection;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late _SettingsSection _section;

  @override
  void initState() {
    super.initState();
    _section = _SettingsSection.fromName(widget.initialSection);
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
            onBack: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(AppRoutes.library);
            },
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
  document(LucideIcons.fileCog, '文档设置', '自动保存与新建文档默认值'),
  tools(LucideIcons.wrench, '工具设置', '默认工具与每种笔形的颜色、粗细'),
  stylus(LucideIcons.penLine, '手写笔设置', '压感曲线与防误触'),
  gestures(LucideIcons.hand, '手势设置', '缩放和平移手势'),
  lab(LucideIcons.wandSparkles, 'StarNote 实验室', 'Beta AI'),
  privacy(LucideIcons.shield, '隐私设置', '查看本地数据存储位置与权限说明'),
  other(LucideIcons.ellipsis, '其他设置', '关于应用、版本信息与缓存清理');

  const _SettingsSection(this.icon, this.label, this.description);

  final IconData icon;
  final String label;
  final String description;

  /// Resolves a section by its Dart enum [name], falling back to [account]
  /// when [value] is null or does not match any section.  Used to honour the
  /// `/settings?section=xxx` route query parameter.
  static _SettingsSection fromName(String? value) {
    if (value == null) return _SettingsSection.account;
    for (final section in _SettingsSection.values) {
      if (section.name == value) return section;
    }
    return _SettingsSection.account;
  }
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
      showWallpaper: false,
      header: SharedSidebarHeader(
        leading: SharedSidebarIconButton(
          tooltip: '返回',
          onPressed: onBack,
          icon: const Icon(LucideIcons.chevronLeft),
        ),
        trailing: [
          Text(
            '设置',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
              onTap: () => onSelected(_SettingsSection.other),
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
        topContent: [
          if (section == _SettingsSection.theme) ...[
            const ThemeHero(semanticLabel: '当前主题背景'),
            const SizedBox(height: AppSpacing.controlGap),
          ],
        ],
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
          _SettingsSection.document => const _DocumentSettingsSection(),
          _SettingsSection.tools => const _ToolsSettingsSection(),
          _SettingsSection.stylus => const _StylusSettingsSection(),
          _SettingsSection.gestures => const _GestureSettingsSection(),
          _SettingsSection.lab => const _AiSettingsSection(),
          _SettingsSection.privacy => const _PrivacySettingsSection(),
          _SettingsSection.other => const _OtherSettingsSection(),
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
      Uint8List? bytes;
      if (defaultTargetPlatform == TargetPlatform.ohos) {
        try {
          final files = await pickFilesViaOhosChannel(
            suffixFilters: const ['JSON文件(.json)|.json'],
          );
          bytes = files.first.bytes;
        } on PlatformException {
          if (mounted) {
            setState(() => _backupMessage = '已取消导入');
          }
          return;
        }
      } else {
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
        bytes = result.files.single.bytes;
      }
      if (bytes == null) {
        throw StateError('未读取到备份文件内容');
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      await defaultLocalBackupRepository.importBackup(decoded);
      if (!mounted) {
        return;
      }
      await ref.read(themeViewModelProvider.notifier).restoreSavedPreset();
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
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _resetEmailController = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _resetEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountViewModelProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final selectedColor = colorScheme.primary;

    if (account.isAuthenticated) {
      final user = account.user!;
      if (_displayNameController.text.isEmpty) {
        _displayNameController.text = user.displayName;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: _busy ? null : _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: AccountAvatar(
                      label: user.collaboratorName,
                      user: user,
                      radius: 34,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.email,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user.emailVerified ? '邮箱已验证' : '邮箱未验证',
                          style: TextStyle(
                            color: user.emailVerified
                                ? selectedColor
                                : colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(labelText: '昵称'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: AppSpacing.controlGap,
                          runSpacing: AppSpacing.controlGap,
                          children: [
                            FilledButton(
                              onPressed: _busy ? null : _updateProfile,
                              child: const Text('保存资料'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _pickAvatar,
                              icon: const Icon(LucideIcons.imageUp),
                              label: const Text('上传头像'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '修改密码',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _oldPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '旧密码'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '新密码'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _changePassword,
                    child: const Text('修改密码并重新登录'),
                  ),
                ],
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
          if (account.error != null || account.message != null) ...[
            const SizedBox(height: 12),
            _AccountMessage(
              message: account.error ?? account.message!,
              isError: account.error != null,
            ),
          ],
        ],
      );
    }

    final identity = account.collaborationIdentity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: AccountAvatar(
              label: identity.username,
              avatarUrl: identity.avatarUrl,
              radius: 22,
            ),
            title: Text(identity.username),
            subtitle: Text(
              account.status == AccountStatus.verificationRequired
                  ? '验证邮件已发送，请验证后登录'
                  : '当前使用匿名协作身份，可通过链接加入房间',
            ),
            trailing: Text(
              account.status == AccountStatus.verificationRequired
                  ? '待验证'
                  : '访客',
            ),
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
                  _AccountMessage(message: account.error!, isError: true),
                ],
                if (account.message != null) ...[
                  const SizedBox(height: 12),
                  _AccountMessage(message: account.message!, isError: false),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: AppSpacing.controlGap,
                  runSpacing: AppSpacing.controlGap,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? '处理中'
                            : _registerMode
                            ? '注册'
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
                    TextButton(
                      onPressed: _busy ? null : _requestPasswordReset,
                      child: const Text('忘记密码'),
                    ),
                    if (account.status == AccountStatus.verificationRequired)
                      TextButton(
                        onPressed: _busy ? null : _resendVerification,
                        child: const Text('重发验证邮件'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '找回密码邮箱',
                    hintText: '为空时使用上方邮箱',
                  ),
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

  Future<void> _updateProfile() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(accountViewModelProvider.notifier)
          .updateProfile(displayName: _displayNameController.text.trim());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    setState(() => _busy = true);
    try {
      Uint8List? bytes;
      String? extension;
      if (defaultTargetPlatform == TargetPlatform.ohos) {
        try {
          final files = await pickFilesViaOhosChannel(
            suffixFilters: const [
              '图片(.png,.jpg,.jpeg,.webp,.gif)|.png,.jpg,.jpeg,.webp,.gif',
            ],
          );
          final picked = files.first;
          bytes = picked.bytes;
          extension = picked.name.split('.').last;
        } on PlatformException {
          return;
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: '选择头像',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) {
          return;
        }
        final file = result.files.single;
        bytes = file.bytes;
        extension = file.extension;
      }
      if (bytes == null) {
        throw StateError('未读取到头像文件内容');
      }
      await ref
          .read(accountViewModelProvider.notifier)
          .uploadAvatar(
            bytes: bytes,
            mimeType: _mimeTypeForAvatar(extension ?? ''),
          );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changePassword() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(accountViewModelProvider.notifier)
          .changePassword(
            oldPassword: _oldPasswordController.text,
            newPassword: _newPasswordController.text,
          );
      _oldPasswordController.clear();
      _newPasswordController.clear();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _requestPasswordReset() async {
    setState(() => _busy = true);
    try {
      final email = _resetEmailController.text.trim().isEmpty
          ? _emailController.text.trim()
          : _resetEmailController.text.trim();
      await ref
          .read(accountViewModelProvider.notifier)
          .requestPasswordReset(email);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resendVerification() async {
    setState(() => _busy = true);
    try {
      final email = accountEmail();
      await ref
          .read(accountViewModelProvider.notifier)
          .resendVerification(email);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String accountEmail() {
    final userEmail = ref.read(accountViewModelProvider).user?.email;
    if (userEmail != null && userEmail.isNotEmpty) {
      return userEmail;
    }
    return _emailController.text.trim();
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

  String _mimeTypeForAvatar(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/png';
    }
  }
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Application version metadata.  Kept as constants rather than read at runtime
/// via `package_info_plus` to avoid an extra dependency; bump these together
/// with `pubspec.yaml`'s `version:` field when releasing.
class _AppVersion {
  static const String version = '1.0.0';
  static const String buildNumber = '1';
  static const String displayName = 'FlowMuse';
}

/// "Other settings" — about, version info, licenses, and cache cleanup.
class _OtherSettingsSection extends StatefulWidget {
  const _OtherSettingsSection();

  @override
  State<_OtherSettingsSection> createState() => _OtherSettingsSectionState();
}

class _OtherSettingsSectionState extends State<_OtherSettingsSection> {
  bool _clearing = false;

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      final result = await clearRebuildableCache();
      if (!mounted) return;
      final message = result.filesRemoved > 0
          ? '已清除 ${result.formattedBytes}（${result.filesRemoved} 个文件）'
          : '缓存已是最新';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('清除缓存失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.penLine,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _AppVersion.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本 ${_AppVersion.version}（构建 ${_AppVersion.buildNumber}）',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        _SettingsCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.globe),
                title: const Text('官方网站'),
                subtitle: const Text('即将上线'),
              ),
              ListTile(
                leading: const Icon(LucideIcons.scrollText),
                title: const Text('开源许可'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: _AppVersion.displayName,
                    applicationVersion: _AppVersion.version,
                  );
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.mail),
                title: const Text('帮助与反馈'),
                subtitle: const Text('即将上线'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        _SettingsCard(
          child: ListTile(
            leading: _clearing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.trash2),
            title: const Text('清除缓存'),
            subtitle: Text(
              '清理分享与导出的临时文件，不影响你的笔记和白板',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: _clearing ? null : _clearCache,
          ),
        ),
      ],
    );
  }
}

/// "Privacy settings" — data-storage explanation, storage location, permission
/// notes (static), and a privacy-policy link.
class _PrivacySettingsSection extends StatefulWidget {
  const _PrivacySettingsSection();

  @override
  State<_PrivacySettingsSection> createState() =>
      _PrivacySettingsSectionState();
}

class _PrivacySettingsSectionState extends State<_PrivacySettingsSection> {
  String? _dbPath;
  bool _loadingPath = true;

  @override
  void initState() {
    super.initState();
    _loadDbPath();
  }

  Future<void> _loadDbPath() async {
    try {
      final path = await localDatabaseDirectory();
      if (mounted) {
        setState(() {
          _dbPath = path;
          _loadingPath = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPath = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.database, size: 18, color: muted),
                    const SizedBox(width: 8),
                    Text(
                      '数据存储',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '你的白板内容、笔记本、标签与主题设置均保存在本机 SQLite 数据库，默认不会上传服务器。参与协作时，场景数据会通过加密通道同步；主动使用 AI 助手时，当前标题和文本元素会发送到你配置的模型服务。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        _SettingsCard(
          child: ListTile(
            leading: const Icon(LucideIcons.folderOpen),
            title: const Text('数据存储位置'),
            subtitle: Text(
              _loadingPath ? '正在读取…' : (_dbPath ?? '无法获取路径'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.shieldCheck, size: 18, color: muted),
                    const SizedBox(width: 8),
                    Text(
                      '权限说明',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PermissionRow(
                  icon: LucideIcons.wifi,
                  name: '网络访问（INTERNET）',
                  purpose: '用于账号登录、实时协作与用户主动发起的 AI 请求',
                ),
                const SizedBox(height: 8),
                _PermissionRow(
                  icon: LucideIcons.activity,
                  name: '网络状态（GET_NETWORK_INFO）',
                  purpose: '用于检测当前网络连接状态（鸿蒙端）',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.listGap),
        _SettingsCard(
          child: ListTile(
            leading: const Icon(LucideIcons.fileText),
            title: const Text('隐私政策'),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => context.push(AppRoutes.privacyPolicy),
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.name,
    required this.purpose,
  });

  final IconData icon;
  final String name;
  final String purpose;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 2),
              Text(
                purpose,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToolsSettingsSection extends ConsumerWidget {
  const _ToolsSettingsSection();

  static const _colors = [
    '#1e1e1e',
    '#e03131',
    '#1971c2',
    '#2f9e44',
    '#f08c00',
    '#7048e8',
    '#ffff00',
  ];
  static const _colorLabels = {
    '#1e1e1e': '黑色',
    '#e03131': '红色',
    '#1971c2': '蓝色',
    '#2f9e44': '绿色',
    '#f08c00': '橙色',
    '#7048e8': '紫色',
    '#ffff00': '黄色',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _editorPreferencesBody(ref, (preferences, notifier) {
      final brush = preferences.defaultBrush;
      final brushState = preferences.brushState(brush);
      return Column(
        children: [
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(LucideIcons.mousePointer2),
                  title: const Text('默认工具'),
                  subtitle: const Text('打开白板时自动选择'),
                  trailing: _SettingsPopupMenu<ToolType>(
                    value: preferences.defaultTool,
                    options: _defaultTools,
                    label: _toolLabel,
                    onSelected: (value) =>
                        unawaited(notifier.setDefaultTool(value)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: const Icon(LucideIcons.penTool),
                  title: const Text('默认笔形'),
                  subtitle: const Text('颜色和粗细会按每支笔分别记忆'),
                  trailing: _SettingsPopupMenu<BrushType>(
                    value: brush,
                    options: BrushType.values,
                    label: _brushLabel,
                    onSelected: (value) =>
                        unawaited(notifier.setDefaultBrush(value)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.listGap),
          _SettingsCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_brushLabel(brush)}颜色',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.controlGap),
                  Wrap(
                    spacing: AppSpacing.controlGap,
                    runSpacing: AppSpacing.controlGap,
                    children: [
                      for (final color in _colors)
                        ChoiceChip(
                          selected: brushState.strokeColor == color,
                          avatar: CircleAvatar(
                            backgroundColor: _colorFromHex(color),
                          ),
                          label: Text(_colorLabels[color]!),
                          onSelected: (_) {
                            unawaited(
                              notifier.updateBrushState(
                                brush,
                                brushState.copyWith(strokeColor: color),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  Text(
                    '笔触粗细 ${brushState.strokeWidth?.toStringAsFixed(0) ?? '2'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Slider(
                    value: (brushState.strokeWidth ?? 2).clamp(
                      brushState.strokeWidthMin,
                      brushState.strokeWidthMax,
                    ),
                    min: brushState.strokeWidthMin,
                    max: brushState.strokeWidthMax,
                    divisions:
                        ((brushState.strokeWidthMax -
                                    brushState.strokeWidthMin) /
                                brushState.strokeWidthStep)
                            .round(),
                    label: brushState.strokeWidth?.toStringAsFixed(0),
                    onChanged: (value) {
                      unawaited(
                        notifier.updateBrushState(
                          brush,
                          brushState.copyWith(strokeWidth: value),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _SettingsPopupMenu<T extends Object> extends StatelessWidget {
  const _SettingsPopupMenu({
    required this.value,
    required this.options,
    required this.label,
    this.onSelected,
  });

  final T value;
  final List<T> options;
  final String Function(T value) label;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final enabled = onSelected != null;
    final color = enabled
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);

    return PopupMenuButton<T>(
      enabled: enabled,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(value: option, child: Text(label(option))),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label(value), style: TextStyle(color: color)),
          Icon(Icons.arrow_drop_down, color: color),
        ],
      ),
    );
  }
}

class _DocumentSettingsSection extends ConsumerWidget {
  const _DocumentSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _editorPreferencesBody(ref, (preferences, notifier) {
      return _SettingsCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.save),
              title: const Text('自动保存间隔'),
              subtitle: Text(
                preferences.autosaveInterval == AutosaveInterval.off
                    ? '仅在退出或切换到后台时保存；强制结束应用可能丢失修改'
                    : '编辑后自动保存草稿的等待时间',
              ),
              trailing: _SettingsPopupMenu<AutosaveInterval>(
                value: preferences.autosaveInterval,
                options: AutosaveInterval.values,
                label: _autosaveIntervalLabel,
                onSelected: (value) =>
                    unawaited(notifier.setAutosaveInterval(value)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.fileText),
              title: const Text('默认文档类型'),
              subtitle: const Text('新建笔记时预先选择'),
              trailing: _SettingsPopupMenu<CanvasLayoutType>(
                value: preferences.defaultLayoutType,
                options: CanvasLayoutType.values,
                label: _layoutTypeLabel,
                onSelected: (value) =>
                    unawaited(notifier.setDefaultLayoutType(value)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.layoutTemplate),
              title: const Text('默认页面模板'),
              subtitle: const Text('仅用于以后新建的文档'),
              trailing: _SettingsPopupMenu<CanvasPageTemplate>(
                value: preferences.defaultPageTemplate,
                options: CanvasPageTemplate.values,
                label: _pageTemplateLabel,
                onSelected: (value) =>
                    unawaited(notifier.setDefaultPageTemplate(value)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.rows3),
              title: const Text('默认页面排列'),
              subtitle: const Text('分页文档的新页面排列方向'),
              trailing: _SettingsPopupMenu<CanvasPageFlow>(
                value: preferences.defaultPageFlow,
                options: CanvasPageFlow.values,
                label: _pageFlowLabel,
                onSelected: (value) =>
                    unawaited(notifier.setDefaultPageFlow(value)),
              ),
            ),
          ],
        ),
      );
    });
  }
}

String _layoutTypeLabel(CanvasLayoutType type) => switch (type) {
  CanvasLayoutType.paged => '分页',
  CanvasLayoutType.unbounded => '无限画布',
};

String _pageTemplateLabel(CanvasPageTemplate template) => PageTemplate.values
    .firstWhere(
      (value) => value.name == template.name,
      orElse: () => PageTemplate.blank,
    )
    .displayName;

String _pageFlowLabel(CanvasPageFlow flow) => switch (flow) {
  CanvasPageFlow.topToBottom => '上下排列',
  CanvasPageFlow.rightToLeft => '从右向左',
};

String _autosaveIntervalLabel(AutosaveInterval interval) {
  switch (interval) {
    case AutosaveInterval.halfSecond:
      return '0.5 秒';
    case AutosaveInterval.oneSecond:
      return '1 秒';
    case AutosaveInterval.threeSeconds:
      return '3 秒';
    case AutosaveInterval.fiveSeconds:
      return '5 秒';
    case AutosaveInterval.off:
      return '关闭';
  }
}

class _StylusSettingsSection extends ConsumerWidget {
  const _StylusSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _editorPreferencesBody(ref, (preferences, notifier) {
      return _SettingsCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(LucideIcons.gauge),
              title: const Text('启用压感'),
              subtitle: const Text('关闭后使用速度模拟笔触粗细'),
              value: preferences.pressureEnabled,
              onChanged: (value) {
                unawaited(notifier.setPressureEnabled(value));
              },
            ),
            const Divider(height: 1),
            ListTile(
              enabled: preferences.pressureEnabled,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: const Icon(LucideIcons.activity),
              title: const Text('压感曲线'),
              subtitle: const Text('控制轻压和重压之间的变化幅度'),
              trailing: _SettingsPopupMenu<PressureCurvePreset>(
                value: preferences.pressureCurve,
                options: PressureCurvePreset.values,
                label: _pressureCurveLabel,
                onSelected: preferences.pressureEnabled
                    ? (value) => unawaited(notifier.setPressureCurve(value))
                    : null,
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(LucideIcons.hand),
              title: const Text('防误触'),
              subtitle: const Text('手写笔落下时忽略手掌产生的触摸点'),
              value: preferences.palmRejectionEnabled,
              onChanged: (value) {
                unawaited(notifier.setPalmRejectionEnabled(value));
              },
            ),
          ],
        ),
      );
    });
  }
}

class _GestureSettingsSection extends ConsumerWidget {
  const _GestureSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _editorPreferencesBody(ref, (preferences, notifier) {
      return _SettingsCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(LucideIcons.zoomIn),
              title: const Text('双指缩放'),
              subtitle: const Text('双指捏合缩放并移动画布'),
              value: preferences.twoFingerZoomEnabled,
              onChanged: (value) {
                unawaited(notifier.setTwoFingerZoomEnabled(value));
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              secondary: const Icon(LucideIcons.move),
              title: const Text('单指平移'),
              subtitle: const Text('非抓手模式下，手指拖动画布；关闭后手指使用当前工具'),
              value: preferences.singleFingerPanEnabled,
              onChanged: (value) {
                unawaited(notifier.setSingleFingerPanEnabled(value));
              },
            ),
          ],
        ),
      );
    });
  }
}

Widget _editorPreferencesBody(
  WidgetRef ref,
  Widget Function(
    EditorPreferences preferences,
    EditorPreferencesViewModel notifier,
  )
  builder,
) {
  final value = ref.watch(editorPreferencesProvider);
  return value.when(
    data: (preferences) =>
        builder(preferences, ref.read(editorPreferencesProvider.notifier)),
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => _SettingsCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        leading: const Icon(LucideIcons.triangleAlert),
        title: const Text('无法读取编辑器设置'),
        subtitle: Text('$error'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(editorPreferencesProvider),
          child: const Text('重试'),
        ),
      ),
    ),
  );
}

const _defaultTools = [
  ToolType.select,
  ToolType.freedraw,
  ToolType.eraser,
  ToolType.hand,
  ToolType.line,
  ToolType.rectangle,
  ToolType.ellipse,
  ToolType.diamond,
  ToolType.arrow,
];

String _toolLabel(ToolType type) => switch (type) {
  ToolType.select => '选择',
  ToolType.freedraw => '自由绘制',
  ToolType.eraser => '橡皮擦',
  ToolType.hand => '抓手',
  ToolType.line => '直线',
  ToolType.rectangle => '矩形',
  ToolType.ellipse => '圆形',
  ToolType.diamond => '菱形',
  ToolType.arrow => '箭头',
  _ => type.name,
};

String _brushLabel(BrushType type) => switch (type) {
  BrushType.pencil => '铅笔',
  BrushType.ballpoint => '圆珠笔',
  BrushType.fountainPen => '钢笔',
  BrushType.brushPen => '毛笔',
  BrushType.highlighter => '荧光笔',
};

String _pressureCurveLabel(PressureCurvePreset value) => switch (value) {
  PressureCurvePreset.soft => '柔和',
  PressureCurvePreset.standard => '标准',
  PressureCurvePreset.firm => '明显',
};

Color _colorFromHex(String value) =>
    Color(int.parse('ff${value.substring(1)}', radix: 16));

class _AiSettingsSection extends StatefulWidget {
  const _AiSettingsSection();

  @override
  State<_AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<_AiSettingsSection> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hideApiKey = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await defaultAiAgentConfigStore.read();
      if (config != null) {
        _baseUrlController.text = config.baseUrl;
        _apiKeyController.text = config.apiKey;
        _modelController.text = config.model;
      }
    } catch (error) {
      _error = '读取 AI 配置失败：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await defaultAiAgentConfigStore.write(
        AiAgentConfig(
          baseUrl: _baseUrlController.text,
          apiKey: _apiKeyController.text,
          model: _modelController.text,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 接口配置已保存')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'OpenAI 兼容接口',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Base URL 可省略 /chat/completions；API Key 保存在本机。Web 端的密钥保护受浏览器限制，目标服务还必须允许 CORS。',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.openai.com/v1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _hideApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hideApiKey ? '显示' : '隐藏',
                  onPressed: () => setState(() => _hideApiKey = !_hideApiKey),
                  icon: Icon(
                    _hideApiKey ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'gpt-4.1-mini',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存配置'),
              ),
            ),
          ],
        ),
      ),
    );
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Center(child: child),
      ),
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
      child: Semantics(
        button: true,
        selected: selected,
        label: '${preset.label} ${preset.isDark ? '深色' : '浅色'}',
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
                Icon(
                  preset.isDark ? LucideIcons.moon : LucideIcons.sun,
                  size: 14,
                ),
              ],
            ),
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
        color: preset.usesMonochromeBackground ? preset.backgroundEnd : null,
        gradient: preset.hasWallpaper || preset.usesMonochromeBackground
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  preset.backgroundStart,
                  preset.seedColor,
                  preset.backgroundEnd,
                ],
              ),
        image: preset.hasWallpaper
            ? DecorationImage(
                image: AssetImage(preset.wallpaperAsset!),
                fit: BoxFit.cover,
              )
            : null,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const SizedBox(width: 22, height: 22),
    );
  }
}
