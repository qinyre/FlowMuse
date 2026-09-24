import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../shared/network/native_http_client.dart';
import '../models/social_models.dart';
import '../models/invitation_models.dart';

class SocialException implements Exception {
  const SocialException(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

/// Bound to one immutable session; account changes dispose the client and calls.
class SocialRepository {
  SocialRepository({
    required this.serverUrl,
    required String token,
    http.Client? client,
  }) : _token = token,
       _client = client ?? HarmonyAwareHttpClient(readTimeoutMs: 20000);
  final String serverUrl, _token;
  final http.Client _client;
  bool _closed = false;

  void close() {
    _closed = true;
    _client.close();
  }

  Future<SocialJson> _request(
    String method,
    String path, {
    SocialJson? body,
    Map<String, String>? query,
  }) async {
    if (_closed) throw const SocialException('cancelled', '账号已切换');
    final uri = Uri.parse(
      serverUrl,
    ).resolve('/api/social/$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 20));
      if (_closed) throw const SocialException('cancelled', '账号已切换');
      if (response.statusCode == 204) return const {};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? code;
        try {
          code = socialJson(jsonDecode(response.body))['code'] as String?;
        } on FormatException {
          // Proxies can return HTML; only known error codes become user text.
        } on TypeError {
          // Ignore malformed error bodies without exposing their contents.
        }
        if (response.statusCode == 401) code = 'unauthorized';
        throw switch (code) {
          'invitations_disabled' => const SocialException(
            'invitations_disabled',
            '协作邀请暂未开放',
          ),
          'invitation_unavailable' => const SocialException(
            'invitation_unavailable',
            '邀请已失效、已撤销或房间已结束',
          ),
          'device_envelope_missing' => const SocialException(
            'device_envelope_missing',
            '这台设备尚未收到邀请，请让好友补发，也可直接分享协作码加入',
          ),
          'disabled' => const SocialException('disabled', '好友服务暂未开放'),
          'unauthorized' => const SocialException(
            'unauthorized',
            '登录已失效，请重新登录',
          ),
          'not_found' => const SocialException('not_found', '未找到该用户或记录'),
          'conflict' => const SocialException('conflict', '状态已更新，请刷新后重试'),
          'interaction_forbidden' => const SocialException(
            'interaction_forbidden',
            '当前关系不允许此操作',
          ),
          'limit_reached' => const SocialException(
            'limit_reached',
            '操作过于频繁或已达数量上限，请稍后重试',
          ),
          'invalid_input' => const SocialException(
            'invalid_input',
            '内容不符合要求，请检查后重试',
          ),
          _ => const SocialException('unavailable', '好友服务暂不可用，请稍后重试'),
        };
      }
      return socialJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } on SocialException {
      rethrow;
    } on TimeoutException {
      throw const SocialException('network', '网络超时，可稍后重试');
    } on Object {
      throw const SocialException('network', '连接失败，请检查网络后重试');
    }
  }

  Future<SocialMe> me() async => SocialMe.fromJson(await _request('GET', 'me'));
  Future<SocialLookup> lookup(String code) async => SocialLookup.fromJson(
    await _request('POST', 'people/lookup', body: {'friendCode': code}),
  );
  Future<SocialPageResult<SocialRelationship>> relationships(
    String status, {
    String cursor = '',
  }) async => SocialPageResult.fromJson(
    await _request(
      'GET',
      'relationships',
      query: {'state': status, 'cursor': cursor, 'limit': '100'},
    ),
    SocialRelationship.fromJson,
  );
  Future<SocialRelationship> requestFriend(
    SocialLookup person,
    String message,
    String clientId,
  ) async => SocialRelationship.fromJson(
    await _request(
      'POST',
      'relationships',
      body: {
        'friendCode': person.person.friendCode,
        'requestMessage': message,
        'clientRequestId': clientId,
        'expectedVersion': person.version.toString(),
      },
    ),
  );
  Future<SocialRelationship> action(
    SocialRelationship relationship,
    String action,
  ) async => SocialRelationship.fromJson(
    await _request(
      'POST',
      'relationships/${relationship.id}/actions',
      body: {
        'action': action,
        'expectedVersion': relationship.version.toString(),
      },
    ),
  );
  Future<List<SocialPerson>> blocks() async => SocialPageResult.fromJson(
    await _request('GET', 'blocks'),
    SocialPerson.fromJson,
  ).items;
  Future<void> block(String userId) async {
    await _request('POST', 'blocks', body: {'userId': userId});
  }

  Future<void> unblock(String userId) async {
    await _request('POST', 'blocks/$userId/remove', body: const {});
  }

  Future<SocialPageResult<SocialConversation>> conversations({
    String cursor = '',
  }) async => SocialPageResult.fromJson(
    await _request(
      'GET',
      'conversations',
      query: {'cursor': cursor, 'limit': '50'},
    ),
    SocialConversation.fromJson,
  );
  Future<SocialPageResult<SocialMessage>> messages(
    String id, {
    BigInt? before,
    BigInt? after,
  }) async => SocialPageResult.fromJson(
    await _request(
      'GET',
      'conversations/$id/messages',
      query: {
        'limit': '50',
        if (before != null) 'beforeSeq': before.toString(),
        if (after != null) 'afterSeq': after.toString(),
      },
    ),
    SocialMessage.fromJson,
  );
  Future<SocialMessage> send(String id, String clientId, String text) async {
    final normalized = validateMessage(text);
    return SocialMessage.fromJson(
      await _request(
        'POST',
        'conversations/$id/messages',
        body: {'clientMessageId': clientId, 'text': normalized},
      ),
    );
  }

  Future<void> markRead(String id, BigInt seq) async {
    await _request(
      'PUT',
      'conversations/$id/read',
      body: {'throughSeq': seq.toString()},
    );
  }

  String avatarUrl(String value) =>
      value.isEmpty ? '' : Uri.parse(serverUrl).resolve(value).toString();

  Future<SocialDevice> registerDevice(SocialDevice device) async =>
      SocialDevice.fromJson(
        await _request(
          'POST',
          'devices',
          body: {
            'id': device.id,
            'keyId': device.keyId,
            'publicKey': device.publicKey,
            'label': device.label,
          },
        ),
      );
  Future<SocialDeviceSet> devices({String? friendId}) async =>
      SocialDeviceSet.fromJson(
        await _request(
          'GET',
          friendId == null ? 'devices' : 'friends/$friendId/devices',
        ),
      );
  Future<void> revokeDevice(String id) async {
    await _request('POST', 'devices/$id/revoke', body: const {});
  }

  Future<SocialInvitation> invitation(String id) async =>
      SocialInvitation.fromJson(await _request('GET', 'invitations/$id'));
  Future<SocialPageResult<SocialInvitation>> invitations({
    String direction = 'received',
    String cursor = '',
  }) async => SocialPageResult.fromJson(
    await _request(
      'GET',
      'invitations',
      query: {'direction': direction, 'cursor': cursor, 'limit': '100'},
    ),
    SocialInvitation.fromJson,
  );
  Future<SocialInvitation> createInvitation(SocialJson request) async =>
      SocialInvitation.fromJson(
        await _request('POST', 'invitations', body: request),
      );
  Future<({SocialInvitation invitation, InvitationEnvelope envelope})>
  acceptInvitation(String id, SocialDevice device) async {
    final json = await _request(
      'POST',
      'invitations/$id/accept',
      body: {'deviceId': device.id, 'keyId': device.keyId},
    );
    return (
      invitation: SocialInvitation.fromJson(
        Map<String, dynamic>.from(json['invitation']! as Map),
      ),
      envelope: InvitationEnvelope.fromJson(
        Map<String, dynamic>.from(json['envelope']! as Map),
      ),
    );
  }

  Future<SocialInvitation> invitationAction(
    SocialInvitation invitation,
    String action,
  ) async => SocialInvitation.fromJson(
    await _request(
      'POST',
      'invitations/${invitation.id}/$action',
      body: {'expectedVersion': invitation.version.toString()},
    ),
  );
  Future<void> invitationJoined(String id) async {
    await _request('POST', 'invitations/$id/joined', body: const {});
  }

  Future<SocialInvitation> addEnvelopes(
    String id,
    BigInt version,
    List<InvitationEnvelope> envelopes,
  ) async => SocialInvitation.fromJson(
    await _request(
      'POST',
      'invitations/$id/envelopes',
      body: {
        'keysetVersion': version.toString(),
        'envelopes': envelopes.map((e) => e.toJson()).toList(),
      },
    ),
  );
}

String validateMessage(String text) {
  text = text.trim();
  if (text.isEmpty ||
      text.runes.length > 2000 ||
      utf8.encode(text).length > 8192 ||
      text.contains('\u0000')) {
    throw const SocialException('invalid_input', '请输入 1–2000 字的消息');
  }
  if (RegExp(
    r'((#|%23)room(=|%3d)|[a-z0-9_-]+,[a-z0-9_-]{22}([^a-z0-9_-]|$))',
    caseSensitive: false,
  ).hasMatch(text)) {
    throw const SocialException('room_secret', '协作链接含白板密钥，不能保存到云端私聊；请使用协作分享入口');
  }
  return text;
}
