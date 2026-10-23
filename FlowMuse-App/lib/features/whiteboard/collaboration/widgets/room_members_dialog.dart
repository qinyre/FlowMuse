import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_spacing.dart';
import '../models/room_collaborator.dart';

class RoomMembersDialog extends StatefulWidget {
  const RoomMembersDialog({
    super.key,
    required this.users,
    required this.initialUsers,
    required this.selfSocketId,
    required this.maxParticipants,
    required this.onRemove,
  });

  final Stream<List<RoomCollaborator>> users;
  final List<RoomCollaborator> initialUsers;
  final String? selfSocketId;
  final int maxParticipants;
  final Future<void> Function(String socketId) onRemove;

  @override
  State<RoomMembersDialog> createState() => _RoomMembersDialogState();
}

class _RoomMembersDialogState extends State<RoomMembersDialog> {
  String? _removing;
  String? _error;

  Future<void> _remove(RoomCollaborator user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出成员'),
        content: Text(
          '将“${user.username.isEmpty ? '匿名协作者' : user.username}”移出当前房间？对方会停止同步，已收到的画布仍可保存在本地。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _removing != null) return;
    setState(() {
      _removing = user.socketId;
      _error = null;
    });
    try {
      await widget.onRemove(user.socketId);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _removing = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('管理成员'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: StreamBuilder<List<RoomCollaborator>>(
        stream: widget.users,
        initialData: widget.initialUsers,
        builder: (context, snapshot) {
          final users = snapshot.data ?? const [];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.maxParticipants == 0
                    ? '在线 ${users.length} 人 · 不限人数'
                    : '在线 ${users.length} / ${widget.maxParticipants} 人（含房主）',
              ),
              const SizedBox(height: AppSpacing.listGap),
              if (users.isEmpty) const Text('暂无在线成员'),
              for (final user in users)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.username.isEmpty ? '匿名协作者' : user.username),
                  subtitle: Text(
                    user.socketId == widget.selfSocketId
                        ? '我 · 房主'
                        : user.role == 'owner'
                        ? '房主'
                        : user.isGuest
                        ? '访客'
                        : '成员',
                  ),
                  trailing:
                      user.socketId == widget.selfSocketId ||
                          user.role == 'owner'
                      ? null
                      : TextButton(
                          key: ValueKey('remove-${user.socketId}'),
                          onPressed: _removing == null
                              ? () => _remove(user)
                              : null,
                          child: Text(
                            _removing == user.socketId ? '移出中…' : '移出',
                          ),
                        ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: AppSpacing.listGap),
              const Text('移出仅断开当前连接，不会自动重连；对方仍可使用邀请链接主动再次加入。'),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
