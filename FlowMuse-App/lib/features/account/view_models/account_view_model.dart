import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';
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
    return CollaborationIdentity.guest(
      guestName,
      avatarUrl: _guestNameGenerator.avatarUrlFor(guestName),
    );
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
    final settings = defaultLocalSettingsRepository;
    final existing = await settings.readString(_guestNameSettingsKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final name = _guestNameGenerator.next();
    await settings.writeString(_guestNameSettingsKey, name);
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

const _guestNameSettingsKey = 'flowmuse.guest.username.v2';

final _guestNameGenerator = _ChineseGuestNameGenerator();

class _ChineseGuestNameGenerator {
  _ChineseGuestNameGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const _openMojiCdn = 'https://openmoji.org/data/color/svg';
  static const _seqAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static const _adjectives = [
    '活泼',
    '敏捷',
    '勇敢',
    '聪慧',
    '温柔',
    '沉稳',
    '灵巧',
    '可靠',
    '明亮',
    '快乐',
    '优雅',
    '好奇',
    '专注',
    '自在',
    '友善',
    '坚定',
    '从容',
    '机敏',
    '灿烂',
    '安静',
    '热忱',
    '清醒',
    '坦率',
    '轻快',
  ];

  static const _animals = [
    _GuestAnimal('猫', '1F408'),
    _GuestAnimal('狗', '1F415'),
    _GuestAnimal('狐狸', '1F98A'),
    _GuestAnimal('熊猫', '1F43C'),
    _GuestAnimal('狮子', '1F981'),
    _GuestAnimal('老虎', '1F405'),
    _GuestAnimal('狼', '1F43A'),
    _GuestAnimal('小鹿', '1F98C'),
    _GuestAnimal('骏马', '1F40E'),
    _GuestAnimal('独角兽', '1F984'),
    _GuestAnimal('斑马', '1F993'),
    _GuestAnimal('长颈鹿', '1F992'),
    _GuestAnimal('大象', '1F418'),
    _GuestAnimal('犀牛', '1F98F'),
    _GuestAnimal('河马', '1F99B'),
    _GuestAnimal('袋鼠', '1F998'),
    _GuestAnimal('考拉', '1F428'),
    _GuestAnimal('兔子', '1F407'),
    _GuestAnimal('仓鼠', '1F439'),
    _GuestAnimal('海豚', '1F42C'),
    _GuestAnimal('鲸鱼', '1F40B'),
    _GuestAnimal('海豹', '1F9AD'),
    _GuestAnimal('企鹅', '1F427'),
    _GuestAnimal('鸭子', '1F986'),
    _GuestAnimal('天鹅', '1F9A2'),
    _GuestAnimal('鹦鹉', '1F99C'),
    _GuestAnimal('猫头鹰', '1F989'),
    _GuestAnimal('蝴蝶', '1F98B'),
    _GuestAnimal('蜜蜂', '1F41D'),
    _GuestAnimal('章鱼', '1F419'),
    _GuestAnimal('乌龟', '1F422'),
    _GuestAnimal('螃蟹', '1F980'),
    _GuestAnimal('龙虾', '1F99E'),
  ];

  String next() {
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];
    final animal = _animals[_random.nextInt(_animals.length)];
    final seqId = String.fromCharCodes(
      List.generate(
        4,
        (_) => _seqAlphabet.codeUnitAt(_random.nextInt(_seqAlphabet.length)),
      ),
    );
    return '$adjective的${animal.name}$seqId';
  }

  String avatarUrlFor(String username) {
    final normalizedName = username.replaceFirst(RegExp(r'[A-Z0-9]{4}$'), '');
    for (final animal in _animals) {
      if (normalizedName.endsWith(animal.name)) {
        return '$_openMojiCdn/${animal.openMojiCodepoint}.svg';
      }
    }
    return '';
  }
}

class _GuestAnimal {
  const _GuestAnimal(this.name, this.openMojiCodepoint);

  final String name;
  final String openMojiCodepoint;
}
