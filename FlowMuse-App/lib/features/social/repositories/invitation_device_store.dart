import 'dart:convert';
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:uuid/uuid.dart';
import '../models/invitation_models.dart';
import '../models/social_models.dart';
import 'social_repository.dart';

class LocalInvitationDevice {
  const LocalInvitationDevice(this.device, this.keyPair);
  final SocialDevice device;
  final SimpleKeyPair keyPair;
}

/// Private keys and trust pins are scoped to both service origin and account.
/// Logging out disposes memory; only explicit removal deletes the saved key.
class InvitationDeviceStore {
  InvitationDeviceStore({
    required String serverUrl,
    required this.userId,
    FlutterSecureStorage? storage,
  }) : origin = Uri.parse(serverUrl).origin,
       _storage = storage ?? const FlutterSecureStorage();
  final String origin, userId;
  final FlutterSecureStorage _storage;
  String get _prefix =>
      'flowmuse.social.v1.${hash.sha256.convert(utf8.encode(jsonEncode([origin, userId])))}';
  LocalInvitationDevice? _local;
  Future<LocalInvitationDevice>? _loading;
  bool _closed = false;
  void close() {
    _closed = true;
    _local = null;
    _loading = null;
  }

  void _check() {
    if (_closed) {
      throw const SocialException('cancelled', '账号已切换');
    }
  }

  static String fingerprint(String key) =>
      hash.sha256.convert(invitationBytes(key, length: 32)).toString();

  Future<LocalInvitationDevice> current({String label = '当前设备'}) {
    _check();
    if (_local != null) return Future.value(_local!);
    return _loading ??= _load(label).whenComplete(() => _loading = null);
  }

  Future<LocalInvitationDevice> _load(String label) async {
    final pointer = await _storage.read(key: '$_prefix.current');
    _check();
    if (pointer != null && pointer.length < 512) {
      try {
        final ids = (jsonDecode(pointer) as List).cast<String>();
        if (ids.length != 2 ||
            ids.any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id))) {
          throw const FormatException('Invalid device');
        }
        final raw = await _storage.read(key: '$_prefix.${ids[0]}.${ids[1]}');
        _check();
        if (raw != null && raw.length < 4096) {
          final record = jsonDecode(raw) as Map<String, dynamic>;
          if (record['origin'] != origin || record['userId'] != userId) {
            throw const FormatException('Invalid device scope');
          }
          final key = await X25519().newKeyPairFromSeed(
            invitationBytes(record['privateKey'], length: 32),
          );
          _check();
          final public = invitationBase64((await key.extractPublicKey()).bytes);
          _check();
          if (record['publicKey'] != public) {
            throw const FormatException('Invalid device key');
          }
          return _local = LocalInvitationDevice(
            SocialDevice(
              id: ids[0],
              userId: userId,
              keyId: ids[1],
              publicKey: public,
              fingerprint: fingerprint(public),
              label: record['label'] as String,
            ),
            key,
          );
        }
      } on FormatException {
        // Corrupt/missing local material creates a new identity, never a trusted
        // replacement. The old server device remains until explicitly revoked.
      } on TypeError {
        // Legacy/invalid local material follows the same new-device flow.
      }
    }
    final key = await X25519().newKeyPair();
    _check();
    final data = await key.extract();
    _check();
    final public = invitationBase64(data.publicKey.bytes);
    final id = const Uuid().v4(), keyId = const Uuid().v4();
    final record = jsonEncode({
      'origin': origin,
      'userId': userId,
      'privateKey': invitationBase64(data.bytes),
      'publicKey': public,
      'label': label,
    });
    await _storage.write(key: '$_prefix.$id.$keyId', value: record);
    _check();
    await _storage.write(
      key: '$_prefix.current',
      value: jsonEncode([id, keyId]),
    );
    _check();
    return _local = LocalInvitationDevice(
      SocialDevice(
        id: id,
        userId: userId,
        keyId: keyId,
        publicKey: public,
        fingerprint: fingerprint(public),
        label: label,
      ),
      key,
    );
  }

  Future<String> securityCard(String friendCode) async {
    final local = await current();
    _check();
    final d = local.device;
    return const JsonEncoder.withIndent('  ').convert({
      'kind': 'FlowMuseDevice',
      'version': 1,
      'origin': origin,
      'userId': userId,
      'friendCode': friendCode,
      'deviceId': d.id,
      'keyId': d.keyId,
      'publicKey': d.publicKey,
      'fingerprint': d.fingerprint,
    });
  }

  SocialDevice checkCard(
    String raw,
    SocialPerson peer,
    List<SocialDevice> directory,
  ) {
    _check();
    try {
      if (raw.length > 4096) throw const FormatException('Card too large');
      final card = jsonDecode(raw) as Map<String, dynamic>;
      if (card.length != 9 ||
          card['kind'] != 'FlowMuseDevice' ||
          card['version'] != 1 ||
          card['origin'] != origin ||
          card['userId'] != peer.id ||
          card['friendCode'] != peer.friendCode ||
          peer.friendCode.isEmpty) {
        throw const FormatException('Card context mismatch');
      }
      final candidates = directory.where(
        (d) =>
            d.id == card['deviceId'] &&
            d.keyId == card['keyId'] &&
            d.userId == peer.id &&
            d.revokedAt == 0,
      );
      if (candidates.length != 1) {
        throw const FormatException('Device no longer registered');
      }
      final d = candidates.single;
      if (d.publicKey != card['publicKey'] ||
          d.fingerprint != card['fingerprint'] ||
          fingerprint(d.publicKey) != d.fingerprint) {
        throw const FormatException('Fingerprint mismatch');
      }
      return d;
    } on Object {
      throw const SocialException(
        'invalid_card',
        '安全卡与该好友当前设备不符，请通过可信外部渠道重新核对',
      );
    }
  }

  Future<void> trust(SocialDevice device) async {
    _check();
    if (device.userId == userId ||
        device.revokedAt != 0 ||
        fingerprint(device.publicKey) != device.fingerprint) {
      throw const SocialException('invalid_card', '设备安全卡不匹配');
    }
    await _storage.write(
      key: '$_prefix.trust.${device.userId}.${device.id}.${device.keyId}',
      value: jsonEncode({
        'publicKey': device.publicKey,
        'fingerprint': device.fingerprint,
      }),
    );
    _check();
  }

  Future<bool> isTrusted(SocialDevice device) async {
    _check();
    if (device.revokedAt != 0 ||
        fingerprint(device.publicKey) != device.fingerprint) {
      return false;
    }
    final raw = await _storage.read(
      key: '$_prefix.trust.${device.userId}.${device.id}.${device.keyId}',
    );
    _check();
    if (raw == null || raw.length > 1024) return false;
    try {
      final pin = jsonDecode(raw);
      return pin['publicKey'] == device.publicKey &&
          pin['fingerprint'] == device.fingerprint;
    } on Object {
      return false;
    }
  }

  Future<void> forgetTrust(SocialDevice device) async {
    _check();
    await _storage.delete(
      key: '$_prefix.trust.${device.userId}.${device.id}.${device.keyId}',
    );
    _check();
  }

  Future<void> removeLocal(SocialDevice device) async {
    _check();
    if (device.userId != userId) return;
    final pointer = await _storage.read(key: '$_prefix.current');
    _check();
    if (pointer == jsonEncode([device.id, device.keyId])) {
      await _storage.delete(key: '$_prefix.current');
      _local = null;
      _check();
    }
    await _storage.delete(key: '$_prefix.${device.id}.${device.keyId}');
    _check();
  }
}
