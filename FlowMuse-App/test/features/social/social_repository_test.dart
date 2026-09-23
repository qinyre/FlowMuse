import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';

void main() {
  test('邀请卡保留类型与大整数版本，设备接口只发送公钥', () async {
    final invite = {
      'id': 'invite',
      'roomId': 'room',
      'senderId': 'a',
      'recipientId': 'b',
      'conversationId': 'c',
      'status': 'pending',
      'version': '9007199254740993',
      'expiresAt': 2000000000000,
    };
    final message = SocialMessage.fromJson({
      'id': 'm',
      'conversationId': 'c',
      'seq': '1',
      'senderId': 'a',
      'clientMessageId': 'client',
      'kind': 'invitation',
      'createdAt': 0,
      'invitation': invite,
    });
    expect(message.invitation!.version.toString(), '9007199254740993');
    expect(message.text, '协作白板');
    final calls = <String>[];
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        calls.add(request.url.path);
        expect(request.url.queryParameters.containsKey('token'), isFalse);
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/devices')) {
          expect(body.keys.toSet(), {'id', 'keyId', 'publicKey', 'label'});
          return http.Response(
            jsonEncode({...body, 'userId': 'a', 'fingerprint': 'fp'}),
            200,
          );
        }
        expect(body, {'expectedVersion': '9007199254740993'});
        return http.Response(jsonEncode({...invite, 'status': 'revoked'}), 200);
      }),
    );
    await repo.registerDevice(
      const SocialDevice(
        id: 'd',
        userId: 'a',
        keyId: 'k',
        publicKey: 'public',
        fingerprint: 'fp',
        label: 'test',
      ),
    );
    final revoked = await repo.invitationAction(message.invitation!, 'revoke');
    expect(revoked.status, 'revoked');
    expect(calls, [
      '/api/social/devices',
      '/api/social/invitations/invite/revoke',
    ]);
    repo.close();
  });
  test('消息序号跨越 Web 安全整数仍精确保留', () async {
    const seq = '9007199254740993';
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test-token',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body)['throughSeq'], seq);
        expect(request.url.queryParameters.containsKey('token'), isFalse);
        return http.Response('', 204);
      }),
    );
    final message = SocialMessage.fromJson({
      'id': 'm',
      'conversationId': 'c',
      'seq': seq,
      'senderId': 'a',
      'clientMessageId': 'client',
      'kind': 'text',
      'text': 'hi',
      'createdAt': 0,
    });
    expect(message.seq.toString(), seq);
    await repo.markRead('c', message.seq);
    repo.close();
  });
  test('取消账号会话后丢弃晚到响应', () async {
    final pending = Completer<http.Response>();
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test-token',
      client: MockClient((_) => pending.future),
    );
    final future = repo.me();
    await Future<void>.delayed(Duration.zero);
    repo.close();
    pending.complete(http.Response('{}', 200));
    await expectLater(
      future,
      throwsA(
        isA<SocialException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
  });
  test('失败响应只显示已知错误，不泄漏代理返回正文', () async {
    final repo = SocialRepository(
      serverUrl: 'https://example.test',
      token: 'test-token',
      client: MockClient(
        (_) async => http.Response('private upstream diagnostic', 503),
      ),
    );
    await expectLater(
      repo.me(),
      throwsA(
        isA<SocialException>().having(
          (e) => e.message,
          'message',
          '好友服务暂不可用，请稍后重试',
        ),
      ),
    );
    repo.close();
  });
  test('私聊校验 Emoji、长度及白板密钥误传', () {
    expect(validateMessage('  你好😀  '), '你好😀');
    expect(validateMessage(List.filled(2000, '😀').join()).runes.length, 2000);
    for (final text in [
      '',
      List.filled(2001, '字').join(),
      'https://example.test/#room=any,secret',
      'short,${'b' * 22}',
      'https://example.test/%23room%3Dany%2Csecret',
    ]) {
      expect(() => validateMessage(text), throwsA(isA<SocialException>()));
    }
  });
}
