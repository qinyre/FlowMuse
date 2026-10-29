import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/social_notice_preferences.dart';

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
                          : (v) => _save(
                              SocialNoticePreferences(
                                enabled: v,
                                preview: prefs.preview,
                                doNotDisturb: prefs.doNotDisturb,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('显示消息预览'),
                      subtitle: const Text('关闭后，横幅隐藏消息正文与申请附言'),
                      value: prefs.preview,
                      onChanged: _busy || !prefs.enabled
                          ? null
                          : (v) => _save(
                              SocialNoticePreferences(
                                enabled: prefs.enabled,
                                preview: v,
                                doNotDisturb: prefs.doNotDisturb,
                              ),
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('免打扰'),
                      subtitle: const Text('暂停横幅，未读角标仍会更新'),
                      value: prefs.doNotDisturb,
                      onChanged: _busy || !prefs.enabled
                          ? null
                          : (v) => _save(
                              SocialNoticePreferences(
                                enabled: prefs.enabled,
                                preview: prefs.preview,
                                doNotDisturb: v,
                              ),
                            ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: 12),
                    const Text('设置仅在本机生效；应用退到后台或关闭后暂不推送。'),
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
