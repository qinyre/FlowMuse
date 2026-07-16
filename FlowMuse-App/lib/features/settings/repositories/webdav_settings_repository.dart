import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../shared/storage/local_settings_repository.dart';

/// Immutable snapshot of the WebDAV connection configuration.
class WebDavConfig {
  const WebDavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  final String serverUrl;
  final String username;
  final String password;
  final String remotePath;

  bool get isConfigured =>
      serverUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  WebDavConfig copyWith({
    String? serverUrl,
    String? username,
    String? password,
    String? remotePath,
  }) {
    return WebDavConfig(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remotePath: remotePath ?? this.remotePath,
    );
  }
}

/// Persists WebDAV settings.
///
/// Non-sensitive fields (server URL, username, remote path, last backup time)
/// are stored in [LocalSettingsRepository] (SQLite).  The password is kept in
/// [FlutterSecureStorage] so it is encrypted by the OS keychain/keystore.
class WebDavSettingsRepository {
  WebDavSettingsRepository(this._settings, this._secure);

  static const _keyServerUrl = 'webdav.server_url';
  static const _keyUsername = 'webdav.username';
  static const _keyRemotePath = 'webdav.remote_path';
  static const _keyLastBackupAt = 'webdav.last_backup_at';
  static const _secureKeyPassword = 'webdav_password';

  static const _defaultRemotePath = '/FlowMuse/';

  final LocalSettingsRepository _settings;
  final FlutterSecureStorage _secure;

  Future<WebDavConfig> loadConfig() async {
    final serverUrl = await _settings.readString(_keyServerUrl) ?? '';
    final username = await _settings.readString(_keyUsername) ?? '';
    final remotePath =
        await _settings.readString(_keyRemotePath) ?? _defaultRemotePath;
    // flutter_secure_storage may not be available on all platforms (e.g. OHOS
    // without the ohos plugin). Degrade to empty password rather than throwing.
    String password = '';
    try {
      password = await _secure.read(key: _secureKeyPassword) ?? '';
    } catch (_) {}
    return WebDavConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
      remotePath: remotePath,
    );
  }

  Future<void> saveConfig(WebDavConfig config) async {
    await _settings.writeString(_keyServerUrl, config.serverUrl.trim());
    await _settings.writeString(_keyUsername, config.username.trim());
    await _settings.writeString(
        _keyRemotePath,
        config.remotePath.trim().isEmpty
            ? _defaultRemotePath
            : config.remotePath.trim());
    try {
      await _secure.write(key: _secureKeyPassword, value: config.password);
    } catch (_) {}
  }

  Future<void> clearConfig() async {
    await _settings.writeString(_keyServerUrl, '');
    await _settings.writeString(_keyUsername, '');
    await _settings.writeString(_keyRemotePath, _defaultRemotePath);
    try {
      await _secure.delete(key: _secureKeyPassword);
    } catch (_) {}
  }

  Future<DateTime?> loadLastBackupAt() async {
    final raw = await _settings.readString(_keyLastBackupAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> saveLastBackupAt(DateTime time) async {
    await _settings.writeString(_keyLastBackupAt, time.toIso8601String());
  }
}

const _secureStorageOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);

final defaultWebDavSettingsRepository = WebDavSettingsRepository(
  defaultLocalSettingsRepository,
  const FlutterSecureStorage(aOptions: _secureStorageOptions),
);
