import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/invitation_models.dart';
import '../models/social_models.dart';
import '../repositories/invitation_device_store.dart';
import '../repositories/social_repository.dart';
import '../services/invitation_crypto.dart';
import 'social_view_model.dart';

final invitationControllerProvider = Provider<InvitationController?>((ref) {
  final repo = ref.watch(socialRepositoryProvider);
  final session = ref.watch(socialSessionProvider);
  if (repo == null || session == null) return null;
  final controller = InvitationController(
    repo,
    InvitationDeviceStore(serverUrl: repo.serverUrl, userId: session.userId),
  );
  ref.onDispose(controller.close);
  return controller;
});

final socialInvitationProvider = FutureProvider.autoDispose
    .family<SocialInvitation, String>((ref, id) async {
      ref.watch(socialViewModelProvider.select((s) => s.revision));
      final repo = ref.watch(socialRepositoryProvider);
      if (repo == null) throw const SocialException('unauthorized', '请先登录');
      return repo.invitation(id);
    });

/// Session-owned coordinator. Only encrypted requests survive an uncertain send;
/// plaintext room keys are returned to the caller and never cached here.
class InvitationController {
  InvitationController(this.repo, this.devices, {InvitationCrypto? crypto})
    : _crypto = crypto ?? InvitationCrypto();
  final SocialRepository repo;
  final InvitationDeviceStore devices;
  final InvitationCrypto _crypto;
  final _pending = <String, SocialJson>{};
  bool _closed = false;

  void close() {
    _closed = true;
    _pending.clear();
    devices.close();
  }

  void _check([bool Function()? stillCurrent]) {
    if (_closed) throw const SocialException('cancelled', '账号已切换');
    if (stillCurrent != null && !stillCurrent()) {
      throw const SocialException('room_changed', '当前白板房间已改变，请重新打开邀请');
    }
  }

  Future<LocalInvitationDevice> register() async {
    _check();
    final local = await devices.current(
      label: kIsWeb ? 'Web 浏览器' : defaultTargetPlatform.name,
    );
    _check();
    final registered = await repo.registerDevice(local.device);
    _check();
    final d = local.device;
    if (registered.revokedAt != 0) {
      throw const SocialException(
        'device_revoked',
        '本机设备已撤销，请在设备安全中移除本机密钥后重新登记',
      );
    }
    if (registered.id != d.id ||
        registered.userId != d.userId ||
        registered.keyId != d.keyId ||
        registered.publicKey != d.publicKey ||
        registered.fingerprint != d.fingerprint) {
      throw const SocialException('device_mismatch', '设备登记不匹配，请重新核验设备');
    }
    return local;
  }

  Future<SocialDevice> checkCard(String raw, SocialPerson peer) async {
    final directory = await repo.devices(friendId: peer.id);
    _check();
    return devices.checkCard(raw, peer, directory.devices);
  }

  Future<List<SocialDevice>> trusted(List<SocialDevice> directory) async {
    final result = <SocialDevice>[];
    for (final device in directory) {
      if (await devices.isTrusted(device)) result.add(device);
    }
    _check();
    return result;
  }

  Future<void> revoke(SocialDevice device) async {
    await repo.revokeDevice(device.id);
    _check();
    await devices.removeLocal(device);
    _pending.clear();
  }

  Future<SocialInvitation> send({
    required String roomId,
    required String roomKey,
    required String recipientId,
    required bool Function() stillCurrent,
    SocialInvitation? supplement,
    SocialDevice? target,
  }) async {
    _check(stillCurrent);
    final slot = '${supplement?.id ?? roomId}:$recipientId:${target?.id ?? ''}';
    var request = _pending[slot];
    if (request != null) {
      final local = await devices.current();
      final directory = await repo.devices(friendId: recipientId);
      final verified = await trusted(directory.devices);
      final valid = (request['envelopes']! as List).every((value) {
        final e = InvitationEnvelope.fromJson(
          Map<String, dynamic>.from(value as Map),
        ).context;
        return e.senderDeviceId == local.device.id &&
            e.senderKeyId == local.device.keyId &&
            verified.any(
              (d) => d.id == e.recipientDeviceId && d.keyId == e.keyId,
            );
      });
      if (!valid) {
        _pending.remove(slot);
        throw const SocialException('trust_required', '设备或信任已改变，请重新核验后发送');
      }
      _check(stillCurrent);
    }
    if (request == null) {
      if (_pending.length >= 20) {
        throw const SocialException('pending_limit', '待确认邀请过多，请先重试已有邀请');
      }
      final sender = await register();
      final directory = await repo.devices(friendId: recipientId);
      final verified = await trusted(directory.devices);
      _check(stillCurrent);
      final recipients = target == null
          ? verified
          : verified
                .where((d) => d.id == target.id && d.keyId == target.keyId)
                .toList();
      if (recipients.isEmpty) {
        throw const SocialException(
          'trust_required',
          '请先让好友登记设备，并在「核验好友设备」中核对安全卡',
        );
      }
      if (supplement != null &&
          (target == null ||
              supplement.roomId != roomId ||
              supplement.senderId != devices.userId ||
              supplement.recipientId != recipientId ||
              !supplement.canAccept ||
              supplement.expiresAt <= DateTime.now().millisecondsSinceEpoch)) {
        throw const SocialException('invitation_unavailable', '原邀请已失效，请创建新邀请');
      }
      final id = supplement?.id ?? const Uuid().v4();
      final expiry =
          supplement?.expiresAt ??
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
      final envelopes = <InvitationEnvelope>[];
      for (final receiver in recipients) {
        if (receiver.userId != recipientId) {
          throw const SocialException('device_mismatch', '好友设备登记不匹配');
        }
        envelopes.add(
          await _crypto.seal(
            context: InvitationContext(
              inviteId: id,
              roomId: roomId,
              senderId: devices.userId,
              recipientId: recipientId,
              senderDeviceId: sender.device.id,
              senderKeyId: sender.device.keyId,
              recipientDeviceId: receiver.id,
              keyId: receiver.keyId,
              expiresAt: expiry,
            ),
            roomKey: roomKey,
            sender: sender.keyPair,
            recipientPublicKey: receiver.publicKey,
          ),
        );
        _check(stillCurrent);
      }
      request = {
        if (supplement == null) ...{
          'inviteId': id,
          'clientInviteId': const Uuid().v4(),
          'roomId': roomId,
          'recipientId': recipientId,
          'expiresAt': expiry,
        },
        'keysetVersion': directory.version.toString(),
        'envelopes': envelopes.map((e) => e.toJson()).toList(),
      };
      _pending[slot] = request;
    }
    _check(stillCurrent);
    try {
      final result = supplement == null
          ? await repo.createInvitation(request)
          : await repo.addEnvelopes(
              supplement.id,
              BigInt.parse(request['keysetVersion']! as String),
              (request['envelopes']! as List)
                  .map(
                    (e) => InvitationEnvelope.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ),
                  )
                  .toList(),
            );
      _pending.remove(slot);
      _check(stillCurrent);
      return result;
    } on SocialException catch (e) {
      // Network/5xx can hide a committed transaction: retain exactly the same
      // nonce, ciphertext and idempotency key until the server resolves it.
      if (e.code != 'network' && e.code != 'unavailable') _pending.remove(slot);
      rethrow;
    }
  }

  Future<({SocialInvitation invitation, String roomKey})> accept(
    String id,
  ) async {
    final local = await register();
    final accepted = await repo.acceptInvitation(id, local.device);
    _check();
    final invite = accepted.invitation;
    if (invite.id != id ||
        invite.recipientId != devices.userId ||
        !invite.canAccept) {
      throw const SocialException('invitation_unavailable', '邀请与当前账号不匹配');
    }
    final envelope = accepted.envelope;
    final directory = await repo.devices(friendId: invite.senderId);
    final candidates = directory.devices
        .where(
          (d) =>
              d.userId == invite.senderId &&
              d.id == envelope.context.senderDeviceId &&
              d.keyId == envelope.context.senderKeyId &&
              d.revokedAt == 0,
        )
        .toList();
    _check();
    if (candidates.length != 1 || !await devices.isTrusted(candidates.single)) {
      throw const SocialException(
        'trust_required',
        '请先在聊天中的「核验好友设备」核对发送者安全卡，再重新接受邀请',
      );
    }
    final sender = candidates.single;
    try {
      final key = await _crypto.open(
        envelope: envelope,
        expected: InvitationContext(
          inviteId: id,
          roomId: invite.roomId,
          senderId: invite.senderId,
          recipientId: devices.userId,
          senderDeviceId: sender.id,
          senderKeyId: sender.keyId,
          recipientDeviceId: local.device.id,
          keyId: local.device.keyId,
          expiresAt: invite.expiresAt,
        ),
        recipient: local.keyPair,
        trustedSenderPublicKey: sender.publicKey,
      );
      _check();
      return (invitation: invite, roomKey: key);
    } on SocialException {
      rethrow;
    } on Object {
      throw const SocialException('invalid_envelope', '邀请无法安全解密，请重新核验设备并联系发送者');
    }
  }
}
