import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flow_muse/features/social/models/invitation_models.dart';
import 'package:flow_muse/features/social/models/social_models.dart';
import 'package:flow_muse/features/social/repositories/invitation_device_store.dart';
import 'package:flow_muse/features/social/repositories/social_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('设备密钥跨登录保留，并按服务器和账号隔离', () async {
    final a = InvitationDeviceStore(serverUrl: 'https://one.test', userId: 'a');
    final both = await Future.wait([a.current(), a.current()]);
    expect(both[0].device.id, both[1].device.id);
    final first = both[0].device;
    a.close();
    final again = InvitationDeviceStore(
      serverUrl: 'https://one.test/',
      userId: 'a',
    );
    expect((await again.current()).device.id, first.id);
    expect(
      (await InvitationDeviceStore(
            serverUrl: 'https://one.test',
            userId: 'b',
          ).current()).device.id !=
          first.id,
      isTrue,
    );
    expect(
      (await InvitationDeviceStore(
            serverUrl: 'https://two.test',
            userId: 'a',
          ).current()).device.id !=
          first.id,
      isTrue,
    );
    await again.removeLocal(first);
    expect((await again.current()).device.id != first.id, isTrue);
  });
  test('目录不自动建立信任，安全卡必须匹配本人渠道收到的完整公钥', () async {
    final a = InvitationDeviceStore(serverUrl: 'https://one.test', userId: 'a');
    final b = InvitationDeviceStore(serverUrl: 'https://one.test', userId: 'b');
    const peer = SocialPerson(id: 'b', name: 'B', friendCode: 'ABCDEFGHJKLM');
    final remote = (await b.current()).device;
    expect(await a.isTrusted(remote), isFalse);
    final raw = await b.securityCard(peer.friendCode);
    expect(raw.contains('privateKey'), isFalse);
    final checked = a.checkCard(raw, peer, [remote]);
    await a.trust(checked);
    expect(await a.isTrusted(remote), isTrue);
    final changed = SocialDevice(
      id: remote.id,
      userId: remote.userId,
      keyId: 'new-key',
      publicKey: remote.publicKey,
      fingerprint: remote.fingerprint,
      label: remote.label,
    );
    expect(await a.isTrusted(changed), isFalse);
    final card = jsonDecode(raw) as Map<String, dynamic>;
    for (final field in [
      'origin',
      'userId',
      'friendCode',
      'deviceId',
      'keyId',
      'publicKey',
      'fingerprint',
    ]) {
      expect(
        () => a.checkCard(jsonEncode({...card, field: 'changed'}), peer, [
          remote,
        ]),
        throwsA(isA<SocialException>()),
      );
    }
    await a.forgetTrust(remote);
    expect(await a.isTrusted(remote), isFalse);
    a.close();
    expect(() => a.current(), throwsA(isA<SocialException>()));
  });
}
