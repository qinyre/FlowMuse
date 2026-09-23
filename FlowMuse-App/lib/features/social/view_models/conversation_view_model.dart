import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import 'social_view_model.dart';

final conversationViewModelProvider = NotifierProvider.autoDispose
    .family<ConversationViewModel, ConversationState, String>(
      ConversationViewModel.new,
    );

class PendingSocialMessage {
  const PendingSocialMessage(this.id, this.text, {this.failed = false});
  final String id, text;
  final bool failed;
}

class ConversationState {
  const ConversationState({
    this.messages = const [],
    this.pending = const [],
    this.loading = true,
    this.hasOlder = false,
    this.error,
  });
  final List<SocialMessage> messages;
  final List<PendingSocialMessage> pending;
  final bool loading, hasOlder;
  final String? error;
  ConversationState copyWith({
    List<SocialMessage>? messages,
    List<PendingSocialMessage>? pending,
    bool? loading,
    bool? hasOlder,
    String? error,
    bool clearError = false,
  }) => ConversationState(
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    loading: loading ?? this.loading,
    hasOlder: hasOlder ?? this.hasOlder,
    error: clearError ? null : error ?? this.error,
  );
}

class ConversationViewModel extends Notifier<ConversationState> {
  ConversationViewModel(this.conversationId);
  final String conversationId;
  SocialRepository? _repo;
  int _generation = 0;
  bool _fetching = false, _refreshAgain = false;
  BigInt _readThrough = BigInt.zero;
  BigInt _syncThrough = BigInt.zero;
  String? _userId;

  @override
  ConversationState build() {
    final generation = ++_generation;
    _repo = ref.watch(socialRepositoryProvider);
    _userId = ref.watch(socialSessionProvider)?.userId;
    _fetching = false;
    _refreshAgain = false;
    _readThrough = BigInt.zero;
    _syncThrough = BigInt.zero;
    ref.onDispose(() {
      _generation++;
    });
    ref.listen(
      socialViewModelProvider.select((s) => s.revision),
      (_, _) => unawaited(refresh()),
    );
    Future.microtask(() {
      if (_current(generation)) unawaited(refresh());
    });
    return ConversationState(loading: _repo != null);
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  void _merge(List<SocialMessage> incoming) {
    final messages = {
      for (final m in state.messages) m.seq: m,
      for (final m in incoming) m.seq: m,
    }.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
    final acknowledged = {
      for (final m in messages)
        if (m.senderId == _userId) m.clientMessageId,
    };
    state = state.copyWith(
      messages: List.unmodifiable(messages),
      pending: List.unmodifiable(
        state.pending.where((p) => !acknowledged.contains(p.id)),
      ),
      loading: false,
      clearError: true,
    );
  }

  Future<void> refresh({bool older = false}) async {
    final repo = _repo;
    if (repo == null) return;
    if (_fetching) {
      if (!older) _refreshAgain = true;
      return;
    }
    if (older && (!state.hasOlder || state.messages.isEmpty)) return;
    final generation = _generation;
    _fetching = true;
    try {
      var first = _syncThrough == BigInt.zero;
      do {
        final page = await repo.messages(
          conversationId,
          before: older ? state.messages.first.seq : null,
          after: older || first ? null : _syncThrough,
        );
        if (!_current(generation)) return;
        // Only contiguous HTTP pages advance synchronization, never send ACKs.
        if (!older && page.items.isNotEmpty) _syncThrough = page.items.last.seq;
        _merge(page.items);
        if (older || first) {
          state = state.copyWith(hasOlder: page.hasMore);
          break;
        }
        if (!page.hasMore || page.items.isEmpty) break;
        first = false;
      } while (true);
    } catch (error) {
      if (_current(generation)) _failure(error);
    } finally {
      if (_current(generation)) {
        _fetching = false;
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<void> send(String text, {String? clientId}) async {
    text = validateMessage(text);
    final repo = _repo;
    if (repo == null) return;
    final generation = _generation;
    final id = clientId ?? const Uuid().v4();
    final previous = state.pending.where((p) => p.id == id).firstOrNull;
    if (previous != null && (!previous.failed || previous.text != text)) return;
    if (state.pending.length >= 10 && previous == null) {
      throw const SocialException('pending_limit', '请先重试或移除待发送消息');
    }
    state = state.copyWith(
      pending: List.unmodifiable([
        ...state.pending.where((p) => p.id != id),
        PendingSocialMessage(id, text),
      ]),
      clearError: true,
    );
    try {
      final message = await repo.send(conversationId, id, text);
      if (!_current(generation)) return;
      _merge([message]);
      unawaited(refresh());
      unawaited(ref.read(socialViewModelProvider.notifier).refresh());
    } catch (error) {
      if (!_current(generation)) return;
      state = state.copyWith(
        pending: List.unmodifiable(
          state.pending.map(
            (p) =>
                p.id == id ? PendingSocialMessage(id, text, failed: true) : p,
          ),
        ),
      );
      _failure(error);
    }
  }

  void discardFailed(String id) {
    state = state.copyWith(
      pending: List.unmodifiable(
        state.pending.where((p) => p.id != id || !p.failed),
      ),
    );
  }

  Future<void> markVisibleRead(BigInt seq) async {
    final repo = _repo;
    final generation = _generation;
    if (repo == null ||
        !ref.read(socialViewModelProvider).foreground ||
        seq <= _readThrough ||
        seq > _syncThrough ||
        !state.messages.any((m) => m.seq == seq)) {
      return;
    }
    final previous = _readThrough;
    _readThrough = seq;
    try {
      await repo.markRead(conversationId, seq);
      if (_current(generation)) {
        unawaited(ref.read(socialViewModelProvider.notifier).refresh());
      }
    } catch (error) {
      if (_current(generation)) {
        if (_readThrough == seq) _readThrough = previous;
        _failure(error);
      }
    }
  }

  void _failure(Object error) {
    state = state.copyWith(
      loading: false,
      error: error is SocialException ? error.message : '加载消息失败，请重试',
    );
    if (error is SocialException && error.code == 'unauthorized') {
      ref.read(socialViewModelProvider.notifier).handleSessionFailure(error);
    }
  }
}
