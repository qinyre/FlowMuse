import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';
import '../../whiteboard/view_models/whiteboard_view_model.dart';
import '../models/account_user.dart';
import '../models/collaboration_identity.dart';
import '../repositories/account_repository.dart';

enum AccountStatus { loading, guest, authenticated, failed }

class AccountState {
  const AccountState({
    this.status = AccountStatus.loading,
    this.user,
    this.token,
    this.guestName = '匿名用户',
    this.error,
  });

  final AccountStatus status;
  final AccountUser? user;
  final String? token;
  final String guestName;
  final String? error;

  bool get isAuthenticated =>
      status == AccountStatus.authenticated && user != null;

  CollaborationIdentity get collaborationIdentity {
    final currentUser = user;
    final currentToken = token;
    if (currentUser != null && currentToken != null) {
      return CollaborationIdentity.fromUser(currentUser, currentToken);
    }
    return CollaborationIdentity.guest(guestName);
  }

  AccountState copyWith({
    AccountStatus? status,
    AccountUser? user,
    String? token,
    String? guestName,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AccountState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      token: clearUser ? null : token ?? this.token,
      guestName: guestName ?? this.guestName,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class AccountViewModel extends Notifier<AccountState> {
  late final AccountRepository _repository;

  @override
  AccountState build() {
    _repository = ref.watch(accountRepositoryProvider);
    _restore();
    return const AccountState();
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = state.copyWith(status: AccountStatus.loading, clearError: true);
    try {
      final session = await _repository.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        status: AccountStatus.failed,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(status: AccountStatus.loading, clearError: true);
    try {
      final session = await _repository.login(email: email, password: password);
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        status: AccountStatus.failed,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(
      status: AccountStatus.guest,
      clearUser: true,
      clearError: true,
    );
  }

  Future<void> _restore() async {
    final guestName = await _loadGuestName();
    if (state.status == AccountStatus.loading) {
      state = state.copyWith(guestName: guestName);
    }
    try {
      final token = await _repository.readToken();
      final user = await _repository.loadCurrentUser();
      if (user == null || token == null) {
        state = state.copyWith(
          status: AccountStatus.guest,
          guestName: guestName,
          clearUser: true,
          clearError: true,
        );
        return;
      }
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: user,
        token: token,
        guestName: guestName,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        status: AccountStatus.failed,
        guestName: guestName,
        clearUser: true,
        error: error.toString(),
      );
    }
  }

  Future<String> _loadGuestName() async {
    final settings = defaultLocalSettingsRepository;
    final existing = await settings.readString('flowmuse.guest.name');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final suffix = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
    final name = '匿名用户 $suffix';
    await settings.writeString('flowmuse.guest.name', name);
    return name;
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final config = ref.watch(collaborationConfigProvider);
  return AccountRepository(config: config);
});

final accountViewModelProvider =
    NotifierProvider<AccountViewModel, AccountState>(AccountViewModel.new);
