import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../whiteboard/view_models/whiteboard_view_model.dart';
import '../models/account_user.dart';
import '../models/collaboration_identity.dart';
import '../repositories/account_repository.dart';

enum AccountStatus {
  loading,
  guest,
  authenticated,
  verificationRequired,
  failed,
}

class AccountState {
  const AccountState({
    this.status = AccountStatus.loading,
    this.user,
    this.token,
    this.guestName = '匿名用户',
    this.error,
    this.message,
  });

  final AccountStatus status;
  final AccountUser? user;
  final String? token;
  final String guestName;
  final String? error;
  final String? message;

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
    String? message,
    bool clearUser = false,
    bool clearToken = false,
    bool clearError = false,
    bool clearMessage = false,
  }) {
    return AccountState(
      status: status ?? this.status,
      user: clearUser ? null : user ?? this.user,
      token: clearUser || clearToken ? null : token ?? this.token,
      guestName: guestName ?? this.guestName,
      error: clearError ? null : error ?? this.error,
      message: clearMessage ? null : message ?? this.message,
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
    state = state.copyWith(
      status: AccountStatus.loading,
      clearError: true,
      clearMessage: true,
    );
    try {
      final user = await _repository.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      state = state.copyWith(
        status: AccountStatus.verificationRequired,
        user: user,
        clearToken: true,
        clearError: true,
        message: '验证邮件已发送，请验证后登录',
      );
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> verifyEmail(String token) async {
    state = state.copyWith(
      status: AccountStatus.loading,
      clearError: true,
      clearMessage: true,
    );
    try {
      final session = await _repository.verifyEmail(token);
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        clearError: true,
        message: '邮箱已验证',
      );
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> resendVerification(String email) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      await _repository.resendVerification(email);
      state = state.copyWith(message: '验证邮件已重新发送');
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = state.copyWith(
      status: AccountStatus.loading,
      clearError: true,
      clearMessage: true,
    );
    try {
      final session = await _repository.login(email: email, password: password);
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        clearError: true,
        message: '已登录',
      );
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> updateProfile({required String displayName}) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      final user = await _repository.updateProfile(displayName: displayName);
      state = state.copyWith(user: user, message: '资料已更新');
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> uploadAvatar({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      final user = await _repository.uploadAvatar(
        bytes: bytes,
        mimeType: mimeType,
      );
      state = state.copyWith(user: user, message: '头像已更新');
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      await _repository.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(
        status: AccountStatus.guest,
        clearUser: true,
        message: '密码已修改，请重新登录',
      );
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> requestPasswordReset(String email) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      await _repository.requestPasswordReset(email);
      state = state.copyWith(message: '如果邮箱存在，重置邮件会发送到该邮箱');
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    state = state.copyWith(clearError: true, clearMessage: true);
    try {
      await _repository.resetPassword(token: token, newPassword: newPassword);
      state = state.copyWith(
        status: AccountStatus.guest,
        clearUser: true,
        message: '密码已重置，请使用新密码登录',
      );
    } catch (error) {
      _fail(error);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = state.copyWith(
      status: AccountStatus.guest,
      clearUser: true,
      clearError: true,
      message: '已退出登录',
    );
  }

  String resolveAvatarUrl(String avatarUrl) {
    return _repository.resolveAvatarUrl(avatarUrl);
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
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('flowmuse.guest.name');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final suffix = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
    final name = '匿名用户 $suffix';
    await prefs.setString('flowmuse.guest.name', name);
    return name;
  }

  void _fail(Object error) {
    state = state.copyWith(
      status: AccountStatus.failed,
      error: error.toString(),
    );
  }
}

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final config = ref.watch(collaborationConfigProvider);
  return AccountRepository(config: config);
});

final accountViewModelProvider =
    NotifierProvider<AccountViewModel, AccountState>(AccountViewModel.new);
