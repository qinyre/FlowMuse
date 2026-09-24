import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../account/widgets/account_avatar.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../view_models/conversation_view_model.dart';
import '../view_models/social_view_model.dart';
import 'device_security_dialog.dart';
import 'invitation_actions.dart';
import 'invitation_card.dart';

class ConversationPanel extends ConsumerStatefulWidget {
  const ConversationPanel({
    super.key,
    required this.id,
    required this.person,
    required this.canSend,
    this.onBack,
  });
  final String id;
  final SocialPerson person;
  final bool canSend;
  final VoidCallback? onBack;

  @override
  ConsumerState<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends ConsumerState<ConversationPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _historyKey = GlobalKey();
  final _latestMessageKey = GlobalKey();
  bool _atBottom = true;

  ConversationViewModel get _vm =>
      ref.read(conversationViewModelProvider(widget.id).notifier);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    final bottom = _scroll.offset <= 8;
    if (bottom != _atBottom) setState(() => _atBottom = bottom);
    if (bottom) _markVisible();
  }

  void _markVisible() {
    if (!mounted ||
        !_atBottom ||
        !_scroll.hasClients ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final bubble = _latestMessageKey.currentContext?.findRenderObject();
    final history = _historyKey.currentContext?.findRenderObject();
    if (bubble is! RenderBox ||
        history is! RenderBox ||
        !bubble.hasSize ||
        !history.hasSize) {
      return;
    }
    final top = bubble.localToGlobal(Offset.zero, ancestor: history).dy;
    if (top >= history.size.height || top + bubble.size.height <= 0) return;
    final messages = ref
        .read(conversationViewModelProvider(widget.id))
        .messages;
    if (messages.isNotEmpty) unawaited(_vm.markVisibleRead(messages.last.seq));
  }

  Future<void> _send({PendingSocialMessage? retry}) async {
    if (!widget.canSend) return;
    try {
      final text = validateMessage(retry?.text ?? _text.text);
      if (retry == null &&
          ref.read(conversationViewModelProvider(widget.id)).pending.length >=
              10) {
        throw const SocialException('pending_limit', '请先重试或移除待发送消息');
      }
      if (retry == null) _text.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await _vm.send(text, clientId: retry?.id);
    } on SocialException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationViewModelProvider(widget.id));
    final mine = ref.watch(socialSessionProvider)?.userId;
    ref.watch(socialViewModelProvider.select((s) => s.foreground));
    final colors = Theme.of(context).colorScheme;
    final invitations =
        widget.canSend &&
        ref.watch(
          socialViewModelProvider.select((s) => s.me?.invitations == true),
        );
    final invitationActions = InvitationActions.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markVisible());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (widget.onBack != null)
                IconButton(
                  tooltip: '返回列表',
                  onPressed: widget.onBack,
                  icon: const Icon(LucideIcons.arrowLeft, size: 20),
                ),
              AccountAvatar(
                label: widget.person.name,
                avatarUrl: widget.person.avatarUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '私聊记录在云端保存',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新消息',
                onPressed: () => _vm.refresh(),
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
              if (widget.canSend &&
                  ref.watch(
                    socialViewModelProvider.select(
                      (s) => s.me?.invitations == true,
                    ),
                  ))
                IconButton(
                  tooltip: '设备核验（可选）',
                  icon: const Icon(LucideIcons.shieldCheck, size: 18),
                  onPressed: () =>
                      showDeviceSecurity(context, peer: widget.person),
                ),
              if (invitations && invitationActions != null)
                IconButton(
                  tooltip: '邀请协作当前白板',
                  icon: const Icon(Icons.add_to_photos_outlined, size: 18),
                  onPressed: () => invitationActions.send(widget.person, null),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(state.error!, style: TextStyle(color: colors.error)),
          ),
        Expanded(
          child: state.loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    ListView.builder(
                      key: _historyKey,
                      controller: _scroll,
                      reverse: true,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          state.messages.length + state.pending.length + 1,
                      itemBuilder: (context, index) {
                        if (index < state.pending.length) {
                          final pending =
                              state.pending[state.pending.length - index - 1];
                          return _bubble(
                            pending.text,
                            true,
                            footer: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.end,
                              children: [
                                Text(
                                  pending.failed ? '发送失败' : '发送中…',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                if (pending.failed) ...[
                                  TextButton(
                                    onPressed: widget.canSend
                                        ? () => _send(retry: pending)
                                        : null,
                                    child: const Text('重试'),
                                  ),
                                  IconButton(
                                    tooltip: '移除失败消息',
                                    onPressed: () =>
                                        _vm.discardFailed(pending.id),
                                    icon: const Icon(LucideIcons.x, size: 16),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }
                        final at =
                            state.messages.length -
                            (index - state.pending.length) -
                            1;
                        if (at < 0) {
                          return Center(
                            child: state.hasOlder
                                ? TextButton(
                                    onPressed: () => _vm.refresh(older: true),
                                    child: const Text('加载更早消息'),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      state.messages.isEmpty
                                          ? '聊聊新的想法吧'
                                          : '已显示全部消息',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                          );
                        }
                        final message = state.messages[at];
                        final date = message.createdAt.toLocal();
                        return KeyedSubtree(
                          key: at == state.messages.length - 1
                              ? _latestMessageKey
                              : null,
                          child: message.invitation != null
                              ? InvitationCard(
                                  invitation: message.invitation!,
                                  peer: widget.person,
                                  canInteract: invitations,
                                )
                              : _bubble(
                                  message.text,
                                  message.senderId == mine,
                                  footer: Text(
                                    '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                        );
                      },
                    ),
                    if (!_atBottom)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _scroll.jumpTo(0),
                          icon: const Icon(LucideIcons.arrowDown, size: 16),
                          label: const Text('回到最新'),
                        ),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        if (!widget.canSend)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('当前无法发送消息，已有记录仍可查看。'),
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _send,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _send,
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('message-input'),
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '写消息…',
                        counterText: '',
                        helperText: 'Ctrl + Enter 发送',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: IconButton.filled(
                      tooltip: '发送消息',
                      onPressed: _send,
                      icon: const Icon(LucideIcons.send, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(String text, bool mine, {required Widget footer}) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: FractionallySizedBox(
          widthFactor: .85,
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: mine
                      ? colors.primaryContainer
                      : colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      color: mine
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}
