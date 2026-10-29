import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/social_notice_preferences.dart';
import '../models/system_notice.dart';
import '../services/system_notice_service.dart';

class SocialNoticeSettingsDialog extends ConsumerStatefulWidget {
  const SocialNoticeSettingsDialog({super.key});

  @override
  ConsumerState<SocialNoticeSettingsDialog> createState() =>
      _SocialNoticeSettingsState();
}

class _SocialNoticeSettingsState
    extends ConsumerState<SocialNoticeSettingsDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _setSystem(bool enabled, SocialNoticePreferences prefs) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Request directly from this gesture, before saving settings asynchronously.
      final status = enabled
          ? await ref
                .read(systemNoticeServiceProvider)
                .permission(request: true)
          : null;
      if (!mounted) return;
      ref.invalidate(systemNoticePermissionProvider);
      if (enabled && status != SystemNoticePermission.granted) {
        setState(
          () => _error = status == SystemNoticePermission.unsupported
              ? '此环境暂不支持系统通知，请使用 HTTPS 或本机地址打开'
              : '通知未获授权，请在系统或浏览器设置中允许通知后重试',
        );
        return;
      }
      await ref
          .read(socialNoticePreferencesProvider.notifier)
          .save(prefs.copyWith(systemEnabled: enabled));
    } catch (_) {
      if (mounted) setState(() => _error = '系统通知暂不可用，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(SocialNoticePreferences value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(socialNoticePreferencesProvider.notifier).save(value);
    } catch (_) {
      if (mounted) setState(() => _error = '未能保存提醒设置，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(socialNoticePreferencesProvider);
    final prefs = preferences.asData?.value;
    final permission = ref.watch(systemNoticePermissionProvider).asData?.value;
    return AlertDialog(
      title: const Text('消息提醒'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: prefs == null
              ? const LinearProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('应用打开时，以静默横幅提醒新消息、协作邀请和好友申请。'),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('应用内提醒'),
                      value: prefs.enabled,
                      onChanged: _busy
                          ? null
                          : (v) => _save(prefs.copyWith(enabled: v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('系统提醒'),
                      subtitle: Text(
                        permission == SystemNoticePermission.unsupported
                            ? '当前平台或浏览器暂不支持'
                            : prefs.systemEnabled &&
                                  permission == SystemNoticePermission.denied
                            ? '系统已阻止通知，请检查通知权限'
                            : '切到其他应用或标签页时，在系统通知栏提醒',
                      ),
                      value: prefs.systemEnabled,
                      onChanged:
                          _busy ||
                              (permission ==
                                      SystemNoticePermission.unsupported &&
                                  !prefs.systemEnabled)
                          ? null
                          : (v) => _setSystem(v, prefs),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示消息预览'),
                      subtitle: const Text('关闭后，横幅和系统通知隐藏正文与申请附言'),
                      value: prefs.preview,
                      onChanged:
                          _busy || (!prefs.enabled && !prefs.systemEnabled)
                          ? null
                          : (v) => _save(prefs.copyWith(preview: v)),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('免打扰'),
                      subtitle: const Text('暂停横幅与系统提醒，未读角标仍会更新'),
                      value: prefs.doNotDisturb,
                      onChanged:
                          _busy || (!prefs.enabled && !prefs.systemEnabled)
                          ? null
                          : (v) => _save(prefs.copyWith(doNotDisturb: v)),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      '设置仅在本机生效。系统提醒需要应用或浏览器仍在运行；进程被系统暂停或结束后无法继续接收。声音与展示方式遵循系统通知设置。',
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
