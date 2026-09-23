import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../account/widgets/account_avatar.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/social_view_model.dart';

class AddFriendDialog extends ConsumerStatefulWidget {
  const AddFriendDialog({super.key});

  @override
  ConsumerState<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends ConsumerState<AddFriendDialog> {
  final _code = TextEditingController();
  final _message = TextEditingController();
  SocialLookup? _person;
  String? _error, _submittedMessage;
  String _requestId = const Uuid().v4();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _code.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z2-7]{12}$').hasMatch(code)) {
      setState(() => _error = '请输入完整的 12 位好友码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _person = null;
      _submittedMessage = null;
      _requestId = const Uuid().v4();
    });
    try {
      final person = await ref
          .read(socialViewModelProvider.notifier)
          .lookup(code);
      if (mounted) setState(() => _person = person);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is SocialException ? e.message : '查找失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    final person = _person!;
    _submittedMessage ??= _message.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(socialViewModelProvider.notifier)
          .perform(
            (repo) =>
                repo.requestFriend(person, _submittedMessage!, _requestId),
          );
      if (mounted && result != null) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is SocialException ? e.message : '发送失败，可重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(socialSessionProvider, (previous, next) {
      if (previous != next && mounted) Navigator.of(context).pop();
    });
    final person = _person;
    final mine = ref.watch(socialSessionProvider)?.userId;
    final status = person?.relationship?.status;
    final canRequest =
        person != null &&
        person.person.id != mine &&
        status != 'accepted' &&
        status != 'pending';
    return AlertDialog(
      title: const Text('添加好友'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('输入对方的好友码，确认身份后发送申请。'),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: '好友码',
                  hintText: 'ABCD-EFGH-2345',
                ),
                onChanged: (_) => setState(() {
                  _person = null;
                  _error = null;
                }),
                onSubmitted: (_) => _lookup(),
              ),
              if (person != null) ...[
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AccountAvatar(
                    label: person.person.name,
                    avatarUrl: person.person.avatarUrl,
                  ),
                  title: Text(person.person.name),
                  subtitle: Text(person.person.formattedCode),
                ),
                if (canRequest)
                  TextField(
                    controller: _message,
                    enabled: !_busy && _submittedMessage == null,
                    maxLength: 100,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '申请留言（选填）',
                      hintText: '介绍一下自己',
                    ),
                  )
                else
                  Text(
                    person.person.id == mine
                        ? '这是你自己的好友码'
                        : status == 'accepted'
                        ? '你们已经是好友'
                        : '已有待处理的申请，请到“新的好友”查看',
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _busy
              ? null
              : person == null
              ? _lookup
              : canRequest
              ? _request
              : null,
          child: Text(
            _busy
                ? '处理中…'
                : person == null
                ? '查找'
                : '发送申请',
          ),
        ),
      ],
    );
  }
}
