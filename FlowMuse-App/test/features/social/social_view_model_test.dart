import 'dart:async';
import 'dart:convert';

import 'package:flow_muse/features/account/models/account_user.dart';
import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';
import 'package:flow_muse/features/social/services/social_realtime_transport.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestSocialAccount extends AccountViewModel {
  @override
  AccountState build() => const AccountState(status: AccountStatus.guest);
  void signIn(String id) {
    state = AccountState(
      status: AccountStatus.authenticated,
      token: 'test-$id',
      user: AccountUser.fromJson({
        'id': id,
        'email': '',
        'displayName': id,
        'huaweiLinked': true,
      }),
    );
  }

  @override
  Future<void> logout() async {
    state = const AccountState(status: AccountStatus.guest);
  }
}

class TestSocialRealtime extends SocialRealtimeTransport {
  TestSocialRealtime(super.serverUrl, super.token);
  int starts = 0, closes = 0;
  void Function()? hint;
  @override
  void start({
    required void Function() onHint,
    required void Function() onRevoked,
    required void Function(bool) onConnection,
  }) {
    starts++;
    hint = onHint;
  }

  @override
  void close() {
    closes++;
  }
}

Map<String, Object?> meJson(String id) => {
  'person': {
    'id': id,
    'displayName': id,
    'friendCode': 'ABCD2345EFGH',
    'avatarUrl': '',
  },
  'unreadCount': 0,
  'pendingRequestCount': 0,
  'capabilities': {'friends': true, 'textMessages': true, 'invitations': false},
};
http.Response socialResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('刷新覆盖已加载的会话页并保持正确的后续游标', () async {
    var read = false;
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/me')) {
          return socialResponse(meJson('A'));
        }
        if (!request.url.path.endsWith('/conversations')) {
          return socialResponse({'items': []});
        }
        final second = request.url.queryParameters['cursor'] == 'second';
        return socialResponse({
          'items': [
            {
              'id': second ? 'two' : 'one',
              'person': meJson('B')['person'],
              'canSend': true,
              'lastSeq': '1',
              'readSeq': read ? '1' : '0',
              'unreadCount': read ? 0 : 1,
              'updatedAt': second ? 1 : 2,
            },
          ],
          'nextCursor': second ? 'third' : 'second',
        });
      }),
    );
    addTearDown(repo.close);
    final container = ProviderContainer(
      overrides: [
        socialSessionProvider.overrideWithValue((userId: 'A', token: 'test')),
        socialRepositoryProvider.overrideWithValue(repo),
        socialRealtimeFactoryProvider.overrideWithValue(TestSocialRealtime.new),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(socialViewModelProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await vm.loadMoreConversations();
    expect(container.read(socialViewModelProvider).nextCursor, 'third');
    read = true;
    await vm.refresh();
    final state = container.read(socialViewModelProvider);
    expect(state.nextCursor, 'third');
    expect(state.conversations.map((c) => c.unreadCount), [0, 0]);
  });
  test('A 的晚到请求不会污染 B，退出即清空内存和连接', () async {
    final late = Completer<http.Response>();
    final transports = <String, TestSocialRealtime>{};
    final container = ProviderContainer(
      overrides: [
        accountViewModelProvider.overrideWith(TestSocialAccount.new),
        socialRealtimeFactoryProvider.overrideWithValue(
          (url, token) => transports[token] = TestSocialRealtime(url, token),
        ),
        socialRepositoryProvider.overrideWith((ref) {
          final session = ref.watch(socialSessionProvider);
          if (session == null) return null;
          final repo = SocialRepository(
            serverUrl: 'https://example.test',
            token: session.token,
            client: MockClient((request) async {
              if (request.url.path.endsWith('/me')) {
                if (session.userId == 'A') return late.future;
                return socialResponse(meJson(session.userId));
              }
              return socialResponse({'items': [], 'nextCursor': ''});
            }),
          );
          ref.onDispose(repo.close);
          return repo;
        }),
      ],
    );
    addTearDown(container.dispose);
    final account =
        container.read(accountViewModelProvider.notifier) as TestSocialAccount;
    account.signIn('A');
    container.read(socialViewModelProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    account.signIn('B');
    container.read(socialViewModelProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(socialViewModelProvider).me?.person.id, 'B');
    late.complete(socialResponse(meJson('A')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(socialViewModelProvider).me?.person.id, 'B');
    await account.logout();
    expect(container.read(socialViewModelProvider).me, isNull);
    expect(transports['test-A']!.closes, greaterThan(0));
    expect(transports['test-B']!.closes, greaterThan(0));
  });

  test('模块关闭保留账号，重试与前后台切换可恢复', () async {
    var enabled = false;
    final transport = TestSocialRealtime('https://example.test', 'test');
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test',
      client: MockClient((request) async {
        if (!enabled) return socialResponse({'code': 'disabled'}, 503);
        return socialResponse(
          request.url.path.endsWith('/me')
              ? meJson('A')
              : {'items': [], 'nextCursor': ''},
        );
      }),
    );
    addTearDown(repo.close);
    final container = ProviderContainer(
      overrides: [
        accountViewModelProvider.overrideWith(TestSocialAccount.new),
        socialRepositoryProvider.overrideWithValue(repo),
        socialRealtimeFactoryProvider.overrideWithValue((_, _) => transport),
      ],
    );
    addTearDown(container.dispose);
    final account =
        container.read(accountViewModelProvider.notifier) as TestSocialAccount;
    account.signIn('A');
    final vm = container.read(socialViewModelProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      container.read(socialViewModelProvider).status,
      SocialStatus.disabled,
    );
    expect(container.read(accountViewModelProvider).isAuthenticated, isTrue);
    enabled = true;
    await vm.refresh();
    expect(container.read(socialViewModelProvider).status, SocialStatus.ready);
    vm.setForeground(false);
    expect(transport.closes, greaterThan(0));
    vm.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(transport.starts, greaterThan(1));
  });
}
