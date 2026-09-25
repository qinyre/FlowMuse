import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/account/models/account_user.dart';
import 'package:flow_muse/features/account/repositories/account_repository.dart';
import 'package:flow_muse/features/account/repositories/auth_token_store.dart';
import 'package:flow_muse/features/account/repositories/huawei_account_channel_ohos.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/account/views/verify_email_page.dart';
import 'package:flow_muse/features/settings/views/settings_page.dart';
import 'package:flow_muse/shared/widgets/app_shell.dart';
import 'package:flow_muse/features/library/repositories/library_repository.dart';
import 'package:flow_muse/features/whiteboard/collaboration/collaboration_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = CollaborationConfig(
  serverUrl: 'https://api.example.test',
  shareOrigin: 'https://app.example.test',
);
const _huawei = {
  'id': 'same-user',
  'email': '',
  'displayName': '华为用户',
  'huaweiLinked': true,
  'hasPassword': false,
  'emailVerified': false,
};
final _linked = {
  ..._huawei,
  'email': 'user@example.test',
  'emailVerified': true,
  'hasPassword': true,
};

class _MemoryTokens extends AuthTokenStore {
  String? value;
  @override
  Future<String?> readToken() async => value;
  @override
  Future<void> writeToken(String token) async {
    value = token;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

http.Response _response(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

class _ScreenAccount extends AccountViewModel {
  _ScreenAccount(this.initial);
  final AccountState initial;
  @override
  AccountState build() => initial;
  @override
  String resolveAvatarUrl(String avatarUrl) => '';
}

class _ScreenLibrary extends LibraryIndexNotifier {
  @override
  Future<LibraryIndex> build() async => const LibraryIndex();
}

class _ScreenShell extends ShellLayoutViewModel {
  @override
  bool build() => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flow_muse/huawei_account');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('账号页面按原生能力和登录方式展示入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final mode in ['android', 'harmony', 'huawei-only', 'email']) {
      final available = mode != 'android';
      final signedIn = mode == 'huawei-only' || mode == 'email';
      final user = mode == 'huawei-only'
          ? AccountUser.fromJson(_huawei)
          : AccountUser.fromJson({..._linked, 'huaweiLinked': false});
      final account = AccountState(
        status: signedIn ? AccountStatus.authenticated : AccountStatus.guest,
        user: signedIn ? user : null,
        token: signedIn ? 'test-session' : null,
      );
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(mode),
          overrides: [
            accountViewModelProvider.overrideWith(
              () => _ScreenAccount(account),
            ),
            shellLayoutViewModelProvider.overrideWith(_ScreenShell.new),
            libraryIndexProvider.overrideWith(_ScreenLibrary.new),
            huaweiAccountAvailableProvider.overrideWith(
              (ref) async => available,
            ),
          ],
          child: const MaterialApp(
            home: SettingsPage(initialSection: 'account'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('华为账号登录'),
        mode == 'harmony' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('绑定邮箱'),
        mode == 'huawei-only' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('修改密码'),
        mode == 'email' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('绑定华为账号'),
        mode == 'email' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('账号字段兼容无邮箱账号与旧服务端', () {
    final huawei = AccountUser.fromJson(_huawei);
    expect(huawei.huaweiLinked, isTrue);
    expect(huawei.hasPassword, isFalse);
    expect(huawei.emailVerified, isFalse);
    expect(
      AccountUser.fromJson({
        'id': 'old',
        'email': 'old@example.test',
        'displayName': '',
      }).hasPassword,
      isTrue,
    );
    expect(
      AccountUser.fromJson({
        ..._huawei,
        'email': null,
        'displayName': '',
      }).collaboratorName,
      isNotEmpty,
    );
  });

  test('华为登录与邮箱绑定沿用同一用户和业务会话', () async {
    final tokens = _MemoryTokens();
    final calls = <String>[];
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((request) async {
        calls.add(request.url.path);
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        switch (request.url.path) {
          case '/api/auth/huawei/login':
            expect(body.keys, ['code']);
            expect(request.headers.containsKey('Authorization'), isFalse);
            return _response(
              jsonEncode({'token': 'test-session', 'user': _huawei}),
              200,
            );
          case '/api/auth/email-binding/verify':
            expect(request.headers.containsKey('Authorization'), isFalse);
            return _response('', 204);
          case '/api/auth/email-binding/request':
            expect(request.headers['Authorization'], 'Bearer test-session');
            return _response(
              jsonEncode({
                'requestId': 'test-request',
                'email': 'user@example.test',
              }),
              201,
            );
          case '/api/auth/email-binding/complete':
            expect(request.headers['Authorization'], 'Bearer test-session');
            expect(body['requestId'], 'test-request');
            return _response(jsonEncode({'user': _linked}), 200);
          case '/api/auth/huawei/bind':
            expect(request.headers['Authorization'], 'Bearer test-session');
            return _response(jsonEncode({'user': _linked}), 200);
          case '/api/auth/me':
            expect(request.headers['Authorization'], 'Bearer test-session');
            expect(request.method, anyOf('GET', 'PUT'));
            return _response(jsonEncode({'user': _linked}), 200);
          default:
            throw StateError('Unexpected test endpoint');
        }
      }),
    );
    addTearDown(repository.close);
    final session = await repository.loginHuawei('test-code');
    expect(tokens.value, 'test-session');
    final id = await repository.requestEmailBinding('user@example.test');
    await repository.verifyEmailBinding('test-proof');
    expect(tokens.value, 'test-session');
    final bound = await repository.completeEmailBinding(id, 'test-password');
    expect(bound.id, session.user.id);
    expect(bound.hasPassword, isTrue);
    expect((await repository.bindHuawei('test-code')).id, session.user.id);
    expect((await repository.loadCurrentUser())?.id, session.user.id);
    await repository.updateProfile(displayName: 'Updated');
    expect(tokens.value, 'test-session');
    expect(calls.length, 7);
  });

  test('华为授权取消、缺失通道和平台错误安全处理', () async {
    final adapter = HuaweiAccountChannel();
    expect(await adapter.isAvailable(), isFalse);
    await expectLater(adapter.authorize(), throwsStateError);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isAvailable' ? true : null,
    );
    expect(await adapter.isAvailable(), isTrue);
    expect(await adapter.authorize(), isNull);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'network',
        message: 'upstream sensitive detail',
      ),
    );
    await expectLater(
      adapter.authorize(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'safe message',
          isNot(contains('sensitive')),
        ),
      ),
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'authorization_failed',
        details: 1001500001,
      ),
    );
    await expectLater(
      adapter.authorize(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          '签名配置提示',
          contains('证书指纹'),
        ),
      ),
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(
        code: 'authorization_failed',
        details: 1001502014,
      ),
    );
    await expectLater(
      adapter.authorize(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          '原生错误码',
          contains('1001502014'),
        ),
      ),
    );
  });

  test('绑定失败与取消华为授权保留已有登录状态', () async {
    final tokens = _MemoryTokens();
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return _response(
            jsonEncode({'token': 'test-session', 'user': _linked}),
            200,
          );
        }
        return _response(
          '登录方式已被占用',
          409,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      }),
    );
    addTearDown(repository.close);
    final container = ProviderContainer(
      overrides: [accountRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final vm = container.read(accountViewModelProvider.notifier);
    await vm.login(email: 'user@example.test', password: 'test-password');
    await expectLater(
      vm.requestEmailBinding('used@example.test'),
      throwsStateError,
    );
    expect(container.read(accountViewModelProvider).isAuthenticated, isTrue);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await vm.useHuawei(bind: true);
    expect(container.read(accountViewModelProvider).isAuthenticated, isTrue);
    expect(tokens.value, 'test-session');
  });

  test('旧的会话恢复请求不能删除新登录的凭证', () async {
    final tokens = _MemoryTokens()..value = 'old-test-session';
    final waiting = Completer<http.Response>();
    final started = Completer<void>();
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((_) {
        started.complete();
        return waiting.future;
      }),
    );
    addTearDown(repository.close);
    final restore = repository.loadCurrentUser();
    await started.future;
    tokens.value = 'new-test-session';
    waiting.complete(_response('', 401));
    expect(await restore, isNull);
    expect(tokens.value, 'new-test-session');
  });

  test('退出登录阻止晚到的华为登录重新写入凭证', () async {
    final tokens = _MemoryTokens();
    final waiting = Completer<http.Response>();
    final started = Completer<void>();
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((_) {
        started.complete();
        return waiting.future;
      }),
    );
    addTearDown(repository.close);
    final login = repository.loginHuawei('test-code');
    final rejected = expectLater(login, throwsStateError);
    await started.future;
    await repository.logout();
    waiting.complete(
      _response(
        jsonEncode({'token': 'late-test-session', 'user': _huawei}),
        200,
      ),
    );
    await rejected;
    expect(tokens.value, isNull);
  });

  test('断网退出仍清除本地凭证和登录状态', () async {
    final tokens = _MemoryTokens();
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return _response(
            jsonEncode({'token': 'test-session', 'user': _linked}),
            200,
          );
        }
        throw http.ClientException('test network unavailable');
      }),
    );
    addTearDown(repository.close);
    final container = ProviderContainer(
      overrides: [accountRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final vm = container.read(accountViewModelProvider.notifier);
    await vm.login(email: 'user@example.test', password: 'test-password');
    await expectLater(vm.logout(), throwsA(isA<http.ClientException>()));
    expect(tokens.value, isNull);
    expect(container.read(accountViewModelProvider).isAuthenticated, isFalse);
  });

  testWidgets('邮箱绑定验证页必须点击确认且不切换浏览器账号', (tester) async {
    var requests = 0;
    final tokens = _MemoryTokens()..value = 'existing-test-session';
    final repository = AccountRepository(
      config: _config,
      tokenStore: tokens,
      client: MockClient((request) async {
        requests++;
        expect(request.url.path, '/api/auth/email-binding/verify');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return _response('', 204);
      }),
    );
    addTearDown(repository.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: VerifyEmailPage(token: 'test-proof', binding: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.tap(find.text('确认此邮箱'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('邮箱已验证'), findsOneWidget);
    expect(find.textContaining('请回到发起绑定'), findsOneWidget);
    expect(tokens.value, 'existing-test-session');
  });
}
