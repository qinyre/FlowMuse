import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/storage/local_settings_repository.dart';
import '../../whiteboard/view_models/whiteboard_view_model.dart';
import '../models/account_user.dart';
import '../models/auth_session.dart';
import '../models/collaboration_identity.dart';
import '../repositories/account_repository.dart';
import '../repositories/huawei_account_channel_ohos.dart';

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
  late AccountRepository _repository;
  int _revision = 0;

  @override
  AccountState build() {
    _repository = ref.watch(accountRepositoryProvider);
    _restore(++_revision);
    return const AccountState();
  }

  Future<T?> _run<T>(
    Future<T> Function() request,
    void Function(T) apply, {
    bool signingIn = false,
  }) async {
    final revision = ++_revision;
    state = state.copyWith(
      status: signingIn ? AccountStatus.loading : null,
      clearError: true,
      clearMessage: true,
    );
    try {
      final result = await request();
      if (!ref.mounted || revision != _revision) return null;
      apply(result);
      return result;
    } catch (error) {
      if (!ref.mounted || revision != _revision) return null;
      state = state.copyWith(
        status: state.user != null && state.token != null
            ? AccountStatus.authenticated
            : AccountStatus.failed,
        error: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _run(
      () => _repository.register(
        email: email,
        password: password,
        displayName: displayName,
      ),
      (user) {
        state = state.copyWith(
          status: AccountStatus.verificationRequired,
          user: user,
          clearToken: true,
          message: '验证邮件已发送，请验证后登录',
        );
      },
      signingIn: true,
    );
  }

  Future<void> verifyEmail(String token) async {
    await _run(() => _repository.verifyEmail(token), (session) {
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        message: '邮箱已验证',
      );
    }, signingIn: true);
  }

  Future<void> login({required String email, required String password}) async {
    await _run(() => _repository.login(email: email, password: password), (
      session,
    ) {
      state = state.copyWith(
        status: AccountStatus.authenticated,
        user: session.user,
        token: session.token,
        message: '已登录',
      );
    }, signingIn: true);
  }

  Future<void> useHuawei({bool bind = false}) async {
    final revision = _revision + 1;
    await _run<Object?>(
      () async {
        final code = await ref.read(huaweiAccountChannelProvider).authorize();
        if (!ref.mounted || code == null || revision != _revision) return null;
        return bind
            ? await _repository.bindHuawei(code)
            : await _repository.loginHuawei(code);
      },
      (result) {
        if (result is AccountUser) {
          state = state.copyWith(user: result, message: '华为账号已绑定');
        } else if (result is AuthSession) {
          state = state.copyWith(
            status: AccountStatus.authenticated,
            user: result.user,
            token: result.token,
            message: '已通过华为账号登录',
          );
        }
      },
    );
  }

  Future<String?> requestEmailBinding(String email) =>
      _run(() => _repository.requestEmailBinding(email), (_) {
        state = state.copyWith(message: '请打开邮件确认邮箱，再回到这里设置密码');
      });

  Future<void> completeEmailBinding(String requestId, String password) async {
    await _run(() => _repository.completeEmailBinding(requestId, password), (
      user,
    ) {
      state = state.copyWith(user: user, message: '邮箱已绑定，可在安卓使用邮箱和密码登录');
    });
  }

  Future<void> resendVerification(String email) async {
    await _run(() => _repository.resendVerification(email), (_) {
      state = state.copyWith(message: '验证邮件已重新发送');
    });
  }

  Future<void> updateProfile({required String displayName}) async {
    await _run(() => _repository.updateProfile(displayName: displayName), (
      user,
    ) {
      state = state.copyWith(user: user, message: '资料已更新');
    });
  }

  Future<void> uploadAvatar({
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _run(
      () => _repository.uploadAvatar(bytes: bytes, mimeType: mimeType),
      (user) {
        state = state.copyWith(user: user, message: '头像已更新');
      },
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _run(
      () => _repository.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      ),
      (_) {
        state = state.copyWith(
          status: AccountStatus.guest,
          clearUser: true,
          message: '密码已修改，请重新登录',
        );
      },
    );
  }

  Future<void> requestPasswordReset(String email) async {
    await _run(() => _repository.requestPasswordReset(email), (_) {
      state = state.copyWith(message: '如果邮箱存在，重置邮件会发送到该邮箱');
    });
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _run(
      () => _repository.resetPassword(token: token, newPassword: newPassword),
      (_) {
        state = state.copyWith(
          status: AccountStatus.guest,
          clearUser: true,
          message: '密码已重置，请使用新密码登录',
        );
      },
    );
  }

  Future<void> logout() async {
    final revision = _revision + 1;
    try {
      await _run(_repository.logout, (_) {});
    } finally {
      if (ref.mounted && revision == _revision) {
        state = state.copyWith(
          status: AccountStatus.guest,
          clearUser: true,
          message: '已退出本机登录',
        );
      }
    }
  }

  String resolveAvatarUrl(String avatarUrl) =>
      _repository.resolveAvatarUrl(avatarUrl);

  Future<void> _restore(int revision) async {
    try {
      final guestName = await _loadGuestName();
      if (!ref.mounted || revision != _revision) return;
      state = state.copyWith(guestName: guestName);
      final token = await _repository.readToken();
      if (!ref.mounted || revision != _revision) return;
      final user = await _repository.loadCurrentUser();
      if (!ref.mounted || revision != _revision) return;
      state = state.copyWith(
        status: user != null && token != null
            ? AccountStatus.authenticated
            : AccountStatus.guest,
        user: user,
        token: token,
        clearUser: user == null || token == null,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted || revision != _revision) return;
      state = state.copyWith(
        status: AccountStatus.failed,
        clearUser: true,
        error: error.toString(),
      );
    }
  }

  Future<String> _loadGuestName() async {
    final settings = defaultLocalSettingsRepository;
    final existing = await settings.readString(_guestNameSettingsKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final name = _guestNameGenerator.next();
    await settings.writeString(_guestNameSettingsKey, name);
    return name;
  }
}

final huaweiAccountChannelProvider = Provider((ref) => HuaweiAccountChannel());
final huaweiAccountAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(huaweiAccountChannelProvider).isAvailable(),
);

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final repository = AccountRepository(
    config: ref.watch(collaborationConfigProvider),
  );
  ref.onDispose(repository.close);
  return repository;
});

final accountViewModelProvider =
    NotifierProvider<AccountViewModel, AccountState>(AccountViewModel.new);

const _guestNameSettingsKey = 'flowmuse.guest.username.v3';

final _guestNameGenerator = _ChineseGuestNameGenerator();

class _ChineseGuestNameGenerator {
  _ChineseGuestNameGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  // 固定版本且支持 CORS，避免 Web 头像被原站跨域策略拦截。
  static const _openMojiCdn =
      'https://cdn.jsdelivr.net/npm/openmoji@15.1.0/color/svg';
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
    return '$adjective${animal.name}#$seqId';
  }

  String avatarUrlFor(String username) {
    final normalizedName = username.replaceFirst(RegExp(r'#[A-Z0-9]{4}$'), '');
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
