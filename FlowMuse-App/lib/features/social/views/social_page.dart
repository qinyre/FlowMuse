import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/app_router.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/right_page.dart';
import '../../account/widgets/account_avatar.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/social_view_model.dart';
import '../widgets/add_friend_dialog.dart';
import '../widgets/conversation_panel.dart';
import '../widgets/device_security_dialog.dart';
import '../widgets/invitation_actions.dart';

class SocialPage extends ConsumerWidget {
  const SocialPage({super.key, this.onClose, this.inviteFriends = false});
  final VoidCallback? onClose;
  final bool inviteFriends;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socialViewModelProvider);
    return RightPageScaffold(
      title: inviteFriends ? '邀请好友' : '好友与消息',
      actions: [
        if (!inviteFriends && state.me?.invitations == true)
          IconButton(
            tooltip: '我的设备安全',
            icon: const Icon(LucideIcons.shieldCheck, size: 20),
            onPressed: () => showDeviceSecurity(context),
          ),
        if (state.status == SocialStatus.ready)
          IconButton(
            tooltip: '添加好友',
            icon: const Icon(LucideIcons.userPlus, size: 20),
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const AddFriendDialog(),
            ),
          ),
        IconButton(
          tooltip: '刷新好友与消息',
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          onPressed: () => ref.read(socialViewModelProvider.notifier).refresh(),
        ),
        if (onClose != null)
          IconButton(
            tooltip: inviteFriends ? '关闭好友列表' : '关闭消息',
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: onClose,
          ),
      ],
      body: switch (state.status) {
        SocialStatus.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        SocialStatus.guest => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.messagesSquare, size: 40),
              const SizedBox(height: 20),
              const Text('登录后，与好友交流新的想法'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push(AppRoutes.accountSettings),
                child: const Text('登录账号'),
              ),
            ],
          ),
        ),
        SocialStatus.disabled => const Center(child: Text('好友服务暂未开放，请稍后刷新。')),
        SocialStatus.failed => Center(child: Text(state.error ?? '加载失败，请刷新重试')),
        SocialStatus.ready =>
          inviteFriends && state.me?.invitations != true
              ? const Center(child: Text('好友邀请暂不可用，请复制房间码邀请协作者。'))
              : _SocialWorkspace(
                  key: ValueKey(ref.watch(socialSessionProvider)),
                  state: state,
                  inviteFriends: inviteFriends,
                ),
      },
    );
  }
}

class _SocialWorkspace extends ConsumerStatefulWidget {
  const _SocialWorkspace({
    super.key,
    required this.state,
    required this.inviteFriends,
  });
  final SocialState state;
  final bool inviteFriends;
  @override
  ConsumerState<_SocialWorkspace> createState() => _SocialWorkspaceState();
}

class _SocialWorkspaceState extends ConsumerState<_SocialWorkspace> {
  ({String id, SocialPerson person})? _selected;
  bool _busy = false;

  void _open(String id, SocialPerson person) {
    if (id.isNotEmpty) setState(() => _selected = (id: id, person: person));
  }

  Future<void> _invite(SocialPerson peer) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await InvitationActions.of(context)?.send(peer, null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(
    Future<Object?> Function(SocialRepository) action,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(socialViewModelProvider.notifier).perform(action);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is SocialException ? e.message : '操作失败，请重试'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manage(SocialRelationship friend, String action) async {
    final block = action == 'block';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${block ? '屏蔽' : '删除好友'}「${friend.person.name}」？'),
        content: Text(
          block
              ? '屏蔽后，双方不能再查找、申请或发送消息。已有聊天记录保留。解除屏蔽不会自动恢复好友关系。'
              : '删除后无法继续私聊，已有聊天记录保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(block ? '屏蔽' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action((repo) async {
        if (block) {
          await repo.block(friend.person.id);
        } else {
          await repo.action(friend, 'remove');
        }
        return null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inviteFriends) return _friends();
    final state = widget.state;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= shellCompactBreakpoint;
        final selection = _selected;
        final chat = selection == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.messagesSquare,
                      size: 44,
                      color: colors.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '从一段对话开始',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('选择好友，一起交流灵感。'),
                  ],
                ),
              )
            : ConversationPanel(
                key: ValueKey(selection.id),
                id: selection.id,
                person: selection.person,
                canSend:
                    state.me?.textMessages == true &&
                    state.friends.any((f) => f.conversationId == selection.id),
                onBack: wide ? null : () => setState(() => _selected = null),
              );
        final list = Column(
          children: [
            if (state.me != null) SocialFriendCode(person: state.me!.person),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [
                        Tab(
                          text:
                              '消息${state.me?.unreadCount == 0 ? '' : ' · ${state.me?.unreadCount ?? 0}'}',
                        ),
                        Tab(text: '好友 · ${state.friends.length}'),
                        Tab(
                          text:
                              '新的好友${state.me?.pendingRequestCount == 0 ? '' : ' · ${state.me?.pendingRequestCount ?? 0}'}',
                        ),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [_conversations(), _friends(), _requests()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    state.connected
                        ? LucideIcons.circleCheck
                        : LucideIcons.clock,
                    size: 12,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      state.connected ? '消息已连接' : '定时同步中',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  TextButton(onPressed: _blocks, child: const Text('屏蔽管理')),
                ],
              ),
            ),
          ],
        );
        return PopScope(
          canPop: wide || selection == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && mounted) setState(() => _selected = null);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: wide
                  ? Row(
                      children: [
                        SizedBox(width: 330, child: list),
                        VerticalDivider(width: 1, color: colors.outlineVariant),
                        Expanded(child: chat),
                      ],
                    )
                  : selection == null
                  ? list
                  : chat,
            ),
          ),
        );
      },
    );
  }

  Widget _conversations() {
    final state = widget.state;
    if (state.conversations.isEmpty) {
      return const Center(
        child: Text('还没有对话，添加好友后开始交流。', textAlign: TextAlign.center),
      );
    }
    return ListView(
      children: [
        for (final c in state.conversations)
          ListTile(
            selected: _selected?.id == c.id,
            leading: AccountAvatar(
              label: c.person.name,
              avatarUrl: c.person.avatarUrl,
            ),
            title: Text(
              c.person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              c.lastMessage?.text ?? '打个招呼吧',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: c.unreadCount > 0
                ? Badge(
                    label: Text(
                      c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                    ),
                  )
                : null,
            onTap: () => _open(c.id, c.person),
          ),
        if (state.nextCursor.isNotEmpty)
          TextButton(
            onPressed: () => ref
                .read(socialViewModelProvider.notifier)
                .loadMoreConversations(),
            child: const Text('加载更多会话'),
          ),
      ],
    );
  }

  Widget _friends() {
    final friends = widget.state.friends.toList()
      ..sort((a, b) => a.person.name.compareTo(b.person.name));
    if (friends.isEmpty) {
      return const Center(
        child: Text('分享你的好友码，或点击右上角添加好友。', textAlign: TextAlign.center),
      );
    }
    return ListView(
      children: [
        for (final f in friends)
          ListTile(
            leading: AccountAvatar(
              label: f.person.name,
              avatarUrl: f.person.avatarUrl,
            ),
            title: Text(
              f.person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(f.person.formattedCode),
            onTap: widget.inviteFriends
                ? (_busy ? null : () => _invite(f.person))
                : () => _open(f.conversationId, f.person),
            trailing: widget.inviteFriends
                ? const Icon(LucideIcons.chevronRight, size: 20)
                : PopupMenuButton<String>(
                    tooltip: '管理好友',
                    enabled: !_busy,
                    onSelected: (action) => _manage(f, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remove', child: Text('删除好友')),
                      PopupMenuItem(value: 'block', child: Text('屏蔽')),
                    ],
                  ),
          ),
      ],
    );
  }

  Widget _requests() {
    final requests = widget.state.requests;
    if (requests.isEmpty) return const Center(child: Text('没有待处理的好友申请'));
    final mine = widget.state.me?.person.id;
    return ListView(
      children: [
        for (final r in requests)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AccountAvatar(
                    label: r.person.name,
                    avatarUrl: r.person.avatarUrl,
                  ),
                  title: Text(r.person.name),
                  subtitle: Text(
                    r.message.isEmpty
                        ? (r.requesterId == mine ? '等待对方接受' : '希望添加你为好友')
                        : r.message,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    if (r.requesterId == mine)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _action((repo) => repo.action(r, 'cancel')),
                        child: const Text('撤回'),
                      )
                    else ...[
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _action((repo) => repo.action(r, 'decline')),
                        child: const Text('拒绝'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _action((repo) => repo.action(r, 'accept')),
                        child: const Text('接受'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _blocks() => showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        ref.listen(socialSessionProvider, (before, after) {
          if (before != after && context.mounted) Navigator.pop(context);
        });
        final blocks = ref.watch(
          socialViewModelProvider.select((s) => s.blocks),
        );
        return AlertDialog(
          title: const Text('屏蔽管理'),
          content: SizedBox(
            width: 380,
            height: 360,
            child: blocks.isEmpty
                ? const Center(child: Text('没有已屏蔽的用户'))
                : ListView(
                    children: [
                      for (final p in blocks)
                        ListTile(
                          title: Text(p.name),
                          subtitle: Text(p.formattedCode),
                          trailing: TextButton(
                            onPressed: () => _action((repo) async {
                              await repo.unblock(p.id);
                              return null;
                            }),
                            child: const Text('解除'),
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    ),
  );
}

class SocialFriendCode extends StatelessWidget {
  const SocialFriendCode({super.key, required this.person});
  final SocialPerson person;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text('我的好友码', style: Theme.of(context).textTheme.labelMedium),
    subtitle: Text(
      person.formattedCode,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(letterSpacing: 1.5),
    ),
    trailing: IconButton(
      tooltip: '复制好友码',
      icon: const Icon(LucideIcons.copy, size: 18),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: person.formattedCode));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('好友码已复制')));
        }
      },
    ),
  );
}
