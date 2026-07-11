import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart'
    as ohos_secure_storage;
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_muse/features/whiteboard/collaboration/repositories/collaboration_owner_key_store.dart';

void main() {
  setUp(() {
    ohos_secure_storage.FlutterSecureStorage.setMockInitialValues({});
  });

  test('房主密钥存储使用鸿蒙兼容的安全存储 facade', () async {
    final store = CollaborationOwnerKeyStore(
      storage: const ohos_secure_storage.FlutterSecureStorage(),
    );

    await store.writeOwnerKey('room-1', 'owner-key');

    expect(await store.readOwnerKey('room-1'), 'owner-key');
  });
}
