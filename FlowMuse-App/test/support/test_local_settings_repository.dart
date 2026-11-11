import 'package:flow_muse/shared/storage/local_settings_repository.dart';

/// In-memory preferences; a widget test must never open the real local store.
class TestLocalSettingsRepository extends LocalSettingsRepository {
  TestLocalSettingsRepository()
    : super(() => throw StateError('No database in tests'));

  final values = <String, String>{};
  bool failRead = false, failWrite = false;

  @override
  Future<String?> readString(String key) async {
    if (failRead) throw StateError('Read failed');
    return values[key];
  }

  @override
  Future<void> writeString(String key, String value) async {
    if (failWrite) throw StateError('Write failed');
    values[key] = value;
  }
}
