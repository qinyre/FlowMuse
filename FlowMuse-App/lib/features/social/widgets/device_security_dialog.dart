import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/invitation_models.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/invitation_view_model.dart';
import '../view_models/social_view_model.dart';

Future<void> showDeviceSecurity(BuildContext context, {SocialPerson? peer}) =>
    showDialog<void>(
      context: context,
      builder: (_) => DeviceSecurityDialog(peer: peer),
    );

class DeviceSecurityDialog extends ConsumerStatefulWidget {
  const DeviceSecurityDialog({super.key, this.peer});
  final SocialPerson? peer;
  @override
  ConsumerState<DeviceSecurityDialog> createState() =>
      _DeviceSecurityDialogState();
}

class _DeviceSecurityDialogState extends ConsumerState<DeviceSecurityDialog> {
  final _input = TextEditingController();
  List<SocialDevice> _devices = [];
  Set<String> _trusted = {};
  String? _currentId, _card, _error;
  bool _busy = false;
  InvitationController? get _controller =>
      ref.read(invitationControllerProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _run(_load));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load(InvitationController controller) async {
    final directory = await controller.repo.devices(friendId: widget.peer?.id);
    final trusted = await controller.trusted(directory.devices);
    final current = widget.peer == null
        ? await controller.devices.current()
        : null;
    if (!mounted || _controller != controller) return;
    setState(() {
      _devices = directory.devices;
      _trusted = trusted.map((d) => d.id).toSet();
      _currentId = current?.device.id;
    });
  }

  Future<void> _run(
    Future<void> Function(InvitationController) operation,
  ) async {
    if (_busy || !mounted) return;
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation(controller);
    } catch (e) {
      if (mounted && _controller == controller) {
        if (e is SocialException) {
          ref.read(socialViewModelProvider.notifier).handleSessionFailure(e);
        }
        setState(
          () => _error = e is SocialException ? e.message : '设备操作失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _verify(InvitationController controller) async {
    final peer = widget.peer!;
    final device = await controller.checkCard(_input.text.trim(), peer);
    if (!mounted || _controller != controller) return;
    final confirmed = await _confirm(
      '确认好友设备',
      '${peer.name} · ${peer.formattedCode}\n${device.label}\n\n完整指纹：\n${device.fingerprint}\n\n请确认安全卡由好友通过当面或可信外部渠道提供。仅查看服务器设备列表不构成核验。',
      '已核对，信任此设备',
    );
    if (!confirmed || !mounted || _controller != controller) return;
    // Recheck the live directory after confirmation; do not pin a rotated key.
    final checked = await controller.checkCard(_input.text.trim(), peer);
    await controller.devices.trust(checked);
    if (mounted) _input.clear();
    await _load(controller);
  }

  Future<void> _copy(InvitationController controller) async {
    final me = ref.read(socialViewModelProvider).me;
    if (me == null) return;
    await controller.register();
    final card = await controller.devices.securityCard(me.person.friendCode);
    if (!mounted || _controller != controller) return;
    setState(() => _card = card);
    await Clipboard.setData(ClipboardData(text: card));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本机安全卡已复制，请通过可信渠道交给好友')));
    }
    await _load(controller);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(invitationControllerProvider, (before, after) {
      if (before != after && mounted) Navigator.pop(context);
    });
    final peer = widget.peer;
    return AlertDialog(
      title: Text(peer == null ? '我的设备安全' : '核验好友设备'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                peer == null
                    ? '每台设备只需登记一次。双方通过可信渠道互换安全卡并核验后，即可接收加密协作邀请。退出账号会保留本机密钥。'
                    : '${peer.name} · ${peer.formattedCode}\n新设备需要单独核验，旧设备的信任不会自动转移。',
              ),
              const SizedBox(height: 16),
              if (peer == null) ...[
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _run(_copy),
                  child: const Text('登记并复制本机安全卡'),
                ),
                if (_card != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _card!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ] else ...[
                TextField(
                  controller: _input,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 4096,
                  decoration: const InputDecoration(
                    labelText: '粘贴好友从可信渠道提供的安全卡',
                    alignLabelWithHint: true,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _run(_verify),
                  child: const Text('核对安全卡'),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                peer == null ? '已登记设备（最多 5 台有效设备）' : '好友的有效设备',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_devices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('尚未登记设备'),
                ),
              for (final device in _devices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${device.label}${device.id == _currentId ? ' · 本机' : ''} · ${device.revokedAt != 0
                            ? '已撤销'
                            : peer == null
                            ? '有效'
                            : _trusted.contains(device.id)
                            ? '已核验'
                            : '未核验'}',
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        device.fingerprint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (peer == null && device.revokedAt == 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run((controller) async {
                                    if (!await _confirm(
                                      '撤销此设备？',
                                      '撤销后不能再使用此设备领取邀请。已经解密的白板密钥不会被远程删除；本机设备会同时移除本地密钥。',
                                      '撤销设备',
                                    )) {
                                      return;
                                    }
                                    if (!mounted || _controller != controller) {
                                      return;
                                    }
                                    await controller.revoke(device);
                                    _card = null;
                                    await _load(controller);
                                  }),
                            child: const Text('撤销设备'),
                          ),
                        ),
                      if (peer != null && _trusted.contains(device.id))
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run((controller) async {
                                    await controller.devices.forgetTrust(
                                      device,
                                    );
                                    await _load(controller);
                                  }),
                            child: const Text('取消信任'),
                          ),
                        ),
                      if (peer == null &&
                          device.id == _currentId &&
                          device.revokedAt != 0)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _run((controller) async {
                                  await controller.devices.removeLocal(device);
                                  _card = null;
                                  await _load(controller);
                                }),
                          child: const Text('移除本机旧密钥，以便重新登记'),
                        ),
                    ],
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _run(_load),
          child: const Text('刷新'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
