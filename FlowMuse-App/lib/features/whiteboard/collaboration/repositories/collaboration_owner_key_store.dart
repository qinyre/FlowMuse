import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';

class CollaborationOwnerKeyStore {
  CollaborationOwnerKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'flowmuse.collaboration.ownerKey.';

  final FlutterSecureStorage _storage;

  Future<String?> readOwnerKey(String roomId) {
    return _storage.read(key: '$_prefix$roomId');
  }

  Future<void> writeOwnerKey(String roomId, String ownerKey) {
    return _storage.write(key: '$_prefix$roomId', value: ownerKey);
  }

  Future<void> clearOwnerKey(String roomId) {
    return _storage.delete(key: '$_prefix$roomId');
  }
}
