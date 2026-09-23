import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/view_models/account_view_model.dart';
import '../../whiteboard/view_models/whiteboard_view_model.dart';
import '../models/social_models.dart';
import '../repositories/social_repository.dart';
import '../services/social_realtime_transport.dart';

final socialSessionProvider = Provider(
  (ref) => ref.watch(
    accountViewModelProvider.select(
      (s) => s.isAuthenticated && s.token != null
          ? (userId: s.user!.id, token: s.token!)
          : null,
    ),
  ),
);

final socialRepositoryProvider = Provider<SocialRepository?>((ref) {
  final session = ref.watch(socialSessionProvider);
  if (session == null) return null;
  final repo = SocialRepository(
    serverUrl: ref.watch(collaborationConfigProvider).serverUrl,
    token: session.token,
  );
  ref.onDispose(repo.close);
  return repo;
});

final socialRealtimeFactoryProvider = Provider(
  (ref) => SocialRealtimeTransport.new,
);
final socialViewModelProvider = NotifierProvider<SocialViewModel, SocialState>(
  SocialViewModel.new,
);

enum SocialStatus { guest, loading, ready, disabled, failed }

class SocialState {
  const SocialState({
    this.status = SocialStatus.guest,
    this.me,
    this.friends = const [],
    this.requests = const [],
    this.blocks = const [],
    this.conversations = const [],
    this.nextCursor = '',
    this.connected = false,
    this.foreground = true,
    this.revision = 0,
    this.error,
  });
  final SocialStatus status;
  final SocialMe? me;
  final List<SocialRelationship> friends, requests;
  final List<SocialPerson> blocks;
  final List<SocialConversation> conversations;
  final String nextCursor;
  final bool connected, foreground;
  final int revision;
  final String? error;
  int get badgeCount => (me?.unreadCount ?? 0) + (me?.pendingRequestCount ?? 0);
  SocialState copyWith({
    SocialStatus? status,
    SocialMe? me,
    List<SocialRelationship>? friends,
    List<SocialRelationship>? requests,
    List<SocialPerson>? blocks,
    List<SocialConversation>? conversations,
    String? nextCursor,
    bool? connected,
    bool? foreground,
    int? revision,
    String? error,
    bool clearError = false,
  }) => SocialState(
    status: status ?? this.status,
    me: me ?? this.me,
    friends: friends ?? this.friends,
    requests: requests ?? this.requests,
    blocks: blocks ?? this.blocks,
    conversations: conversations ?? this.conversations,
    nextCursor: nextCursor ?? this.nextCursor,
    connected: connected ?? this.connected,
    foreground: foreground ?? this.foreground,
    revision: revision ?? this.revision,
    error: clearError ? null : error ?? this.error,
  );
}

class SocialViewModel extends Notifier<SocialState> {
  SocialRepository? _repo;
  SocialRealtimeTransport? _realtime;
  Timer? _poll, _debounce;
  int _generation = 0;
  int _conversationPages = 1;
  bool _loadingMore = false;
  bool _refreshing = false, _refreshAgain = false, _foreground = true;

  @override
  SocialState build() {
    final generation = ++_generation;
    _repo = ref.watch(socialRepositoryProvider);
    final session = ref.watch(socialSessionProvider);
    _refreshing = false;
    _refreshAgain = false;
    _conversationPages = 1;
    _loadingMore = false;
    ref.onDispose(() {
      _generation++;
      _poll?.cancel();
      _debounce?.cancel();
      _realtime?.close();
      _realtime = null;
    });
    if (_repo == null || session == null) return const SocialState();
    _realtime = ref.read(socialRealtimeFactoryProvider)(
      _repo!.serverUrl,
      session.token,
    );
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(refresh());
    });
    Future.microtask(() {
      if (_current(generation)) unawaited(refresh());
    });
    return SocialState(status: SocialStatus.loading, foreground: _foreground);
  }

  bool _current(int generation) => ref.mounted && generation == _generation;

  void _startRealtime() {
    if (!_foreground || state.status != SocialStatus.ready) return;
    final generation = _generation;
    _realtime?.start(
      onHint: () {
        if (!_current(generation)) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 180), () {
          if (_current(generation)) unawaited(refresh());
        });
      },
      onRevoked: () {
        if (_current(generation)) {
          _handleError(const SocialException('unauthorized', '登录已失效'));
        }
      },
      onConnection: (connected) {
        if (_current(generation)) state = state.copyWith(connected: connected);
      },
    );
  }

  void setForeground(bool value) {
    _foreground = value;
    state = state.copyWith(foreground: value, connected: value ? null : false);
    if (value) {
      unawaited(refresh());
    } else {
      _realtime?.close();
      _debounce?.cancel();
    }
  }

  Future<List<SocialRelationship>> _relationships(
    SocialRepository repo,
    String status,
  ) async {
    final all = <SocialRelationship>[];
    var cursor = '';
    do {
      final page = await repo.relationships(status, cursor: cursor);
      all.addAll(page.items);
      cursor = page.nextCursor;
    } while (cursor.isNotEmpty);
    return List.unmodifiable(all);
  }

  Future<void> refresh() async {
    final repo = _repo;
    if (repo == null) return;
    if (_refreshing || _loadingMore) {
      _refreshAgain = true;
      return;
    }
    final generation = _generation;
    _refreshing = true;
    try {
      final me = await repo.me();
      if (!_current(generation)) return;
      final values = await Future.wait<Object>([
        _relationships(repo, 'accepted'),
        _relationships(repo, 'pending'),
        repo.blocks(),
        _conversationWindow(repo),
      ]);
      if (!_current(generation)) return;
      final page = values[3] as SocialPageResult<SocialConversation>;
      state = state.copyWith(
        status: SocialStatus.ready,
        me: me,
        friends: values[0] as List<SocialRelationship>,
        requests: values[1] as List<SocialRelationship>,
        blocks: values[2] as List<SocialPerson>,
        conversations: page.items,
        nextCursor: page.nextCursor,
        revision: state.revision + 1,
        clearError: true,
      );
      _startRealtime();
    } catch (error) {
      if (_current(generation)) _handleError(error);
    } finally {
      if (_current(generation)) {
        _refreshing = false;
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }

  Future<SocialPageResult<SocialConversation>> _conversationWindow(
    SocialRepository repo,
  ) async {
    final conversations = <String, SocialConversation>{};
    var cursor = '';
    for (var i = 0; i < _conversationPages; i++) {
      final page = await repo.conversations(cursor: cursor);
      for (final item in page.items) {
        conversations[item.id] = item;
      }
      cursor = page.nextCursor;
      if (cursor.isEmpty) break;
    }
    return SocialPageResult(
      List.unmodifiable(conversations.values),
      nextCursor: cursor,
    );
  }

  void _handleError(Object error) {
    final code = error is SocialException ? error.code : 'network';
    if (code == 'unauthorized') {
      _realtime?.close();
      _poll?.cancel();
      state = const SocialState(
        status: SocialStatus.guest,
        error: '登录已失效，请重新登录',
      );
      // Guard against a stale request signing out a different account.
      final session = ref.read(socialSessionProvider);
      if (session != null) {
        unawaited(
          ref.read(accountViewModelProvider.notifier).logout().catchError((
            Object _,
          ) {
            // logout clears local credentials even when its remote call fails.
          }),
        );
      }
    } else if (code == 'disabled') {
      _realtime?.close();
      state = SocialState(
        status: SocialStatus.disabled,
        foreground: _foreground,
      );
    } else {
      state = state.copyWith(
        status: state.me == null ? SocialStatus.failed : null,
        error: error is SocialException ? error.message : '加载失败，请重试',
      );
    }
  }

  void handleSessionFailure(SocialException error) {
    if (error.code == 'unauthorized') _handleError(error);
  }

  Future<T?> perform<T>(Future<T> Function(SocialRepository) operation) async {
    final repo = _repo;
    final generation = _generation;
    if (repo == null) return null;
    try {
      final result = await operation(repo);
      if (!_current(generation)) return null;
      await refresh();
      return _current(generation) ? result : null;
    } catch (error) {
      if (!_current(generation)) return null;
      _handleError(error);
      rethrow;
    }
  }

  Future<SocialLookup?> lookup(String code) async {
    final repo = _repo;
    final generation = _generation;
    if (repo == null) return null;
    try {
      final result = await repo.lookup(code);
      return _current(generation) ? result : null;
    } catch (error) {
      if (!_current(generation)) return null;
      _handleError(error);
      rethrow;
    }
  }

  Future<void> loadMoreConversations() async {
    final repo = _repo;
    final generation = _generation;
    final cursor = state.nextCursor;
    if (repo == null || cursor.isEmpty || _loadingMore || _refreshing) return;
    _loadingMore = true;
    try {
      final page = await repo.conversations(cursor: cursor);
      if (!_current(generation) || cursor != state.nextCursor) return;
      _conversationPages++;
      final all = {
        for (final c in state.conversations) c.id: c,
        for (final c in page.items) c.id: c,
      }.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = state.copyWith(
        conversations: List.unmodifiable(all),
        nextCursor: page.nextCursor,
      );
    } catch (error) {
      if (_current(generation)) _handleError(error);
    } finally {
      if (_current(generation)) {
        _loadingMore = false;
        if (_refreshAgain) {
          _refreshAgain = false;
          unawaited(refresh());
        }
      }
    }
  }
}
