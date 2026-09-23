import 'dart:convert';

import 'package:flow_muse/features/account/view_models/account_view_model.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';
import 'package:flow_muse/features/social/view_models/conversation_view_model.dart';
import 'package:flow_muse/features/social/view_models/social_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'social_view_model_test.dart' show TestSocialAccount, socialResponse;

class _Inbox extends SocialViewModel {
  @override
  SocialState build() => const SocialState(status: SocialStatus.ready);
  @override
  Future<void> refresh() async {}
  @override
  void setForeground(bool value) {
    state = state.copyWith(foreground: value);
  }
}

Map<String, Object?> _message(
  int seq, {
  String sender = 'B',
  String clientId = 'remote',
}) => {
  'id': 'm-$seq',
  'conversationId': 'chat',
  'seq': '$seq',
  'senderId': sender,
  'clientMessageId': clientId,
  'kind': 'text',
  'text': 'hello',
  'createdAt': seq,
};

void main() {
  test('发送确认不能跳过尚未补拉的消息，失败重试沿用 ID', () async {
    var sent = false, failedOnce = false;
    final clientIds = <String>[];
    final afterQueries = <String?>[];
    var reads = 0;
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test',
      client: MockClient((request) async {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map;
          clientIds.add(body['clientMessageId'] as String);
          if (!failedOnce) {
            failedOnce = true;
            return socialResponse({'code': 'unavailable'}, 503);
          }
          sent = true;
          return socialResponse(
            _message(3, sender: 'A', clientId: clientIds.last),
          );
        }
        if (request.method == 'PUT') {
          reads++;
          return socialResponse({}, 204);
        }
        afterQueries.add(request.url.queryParameters['afterSeq']);
        if (!sent) {
          return socialResponse({
            'items': [_message(1)],
            'hasMore': false,
          });
        }
        return socialResponse({
          'items': [
            _message(2),
            _message(3, sender: 'A', clientId: clientIds.last),
          ],
          'hasMore': false,
        });
      }),
    );
    addTearDown(repo.close);
    final container = ProviderContainer(
      overrides: [
        accountViewModelProvider.overrideWith(TestSocialAccount.new),
        socialRepositoryProvider.overrideWithValue(repo),
        socialViewModelProvider.overrideWith(_Inbox.new),
      ],
    );
    addTearDown(container.dispose);
    (container.read(accountViewModelProvider.notifier) as TestSocialAccount)
        .signIn('A');
    var subscription = container.listen(
      conversationViewModelProvider('chat'),
      (_, _) {},
    );
    addTearDown(() => subscription.close());
    final vm = container.read(conversationViewModelProvider('chat').notifier);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await vm.send('hello');
    final pending = container
        .read(conversationViewModelProvider('chat'))
        .pending
        .single;
    expect(pending.failed, isTrue);
    subscription.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    subscription = container.listen(
      conversationViewModelProvider('chat'),
      (_, _) {},
    );
    expect(
      container.read(conversationViewModelProvider('chat')).pending.single.id,
      pending.id,
    );
    await vm.send(pending.text, clientId: pending.id);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(clientIds, [pending.id, pending.id]);
    expect(afterQueries.contains('1'), isTrue);
    expect(afterQueries.contains('3'), isFalse);
    expect(
      container
          .read(conversationViewModelProvider('chat'))
          .messages
          .map((m) => m.seq.toString()),
      ['1', '2', '3'],
    );
    expect(
      container.read(conversationViewModelProvider('chat')).pending,
      isEmpty,
    );
    container.read(socialViewModelProvider.notifier).setForeground(false);
    await vm.markVisibleRead(BigInt.from(3));
    expect(reads, 0);
    container.read(socialViewModelProvider.notifier).setForeground(true);
    await vm.markVisibleRead(BigInt.from(3));
    await vm.markVisibleRead(BigInt.one);
    expect(reads, 1);
    (container.read(accountViewModelProvider.notifier) as TestSocialAccount)
        .signIn('B');
    expect(
      container.read(conversationViewModelProvider('chat')).messages,
      isEmpty,
    );
  });
}
