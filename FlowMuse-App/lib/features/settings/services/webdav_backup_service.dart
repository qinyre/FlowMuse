import 'dart:convert';
import 'dart:typed_data';

import '../repositories/local_backup_repository.dart';
import 'webdav_client.dart';

/// A backup entry listed on the WebDAV server.
class WebDavBackupEntry {
  const WebDavBackupEntry({
    required this.href,
    required this.fileName,
    this.sizeBytes,
    this.lastModified,
  });

  final String href;
  final String fileName;
  final int? sizeBytes;
  final DateTime? lastModified;

  String get displaySize {
    if (sizeBytes == null) return '';
    final kb = sizeBytes! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// Orchestrates cloud backup and restore using [WebDavClient] and
/// [LocalBackupRepository].
///
/// Backup format: the same JSON produced by [LocalBackupRepository.exportBackup],
/// UTF-8 encoded, uploaded as a single `.json` file.
///
/// File naming: `FlowMuse_YYYY-MM-DD_HH-mm-ss.json`
class WebDavBackupService {
  const WebDavBackupService();

  static const _filePrefix = 'FlowMuse_';
  static const _fileSuffix = '.json';

  /// Creates a backup of all local data and uploads it to WebDAV.
  ///
  /// [remotePath] is the directory path on the server (e.g. `/FlowMuse/`).
  /// Returns the remote file path of the created backup.
  Future<String> createBackup({
    required WebDavClient client,
    required String remotePath,
    required LocalBackupRepository localRepo,
  }) async {
    // 1. Export local data to JSON map
    final payload = await localRepo.exportBackup();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );

    // 2. Ensure the target directory exists
    await client.ensureDirectory(remotePath);

    // 3. Generate a timestamped filename and upload
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '-${now.minute.toString().padLeft(2, '0')}'
        '-${now.second.toString().padLeft(2, '0')}';
    final fileName = '$_filePrefix$stamp$_fileSuffix';
    final sep = remotePath.endsWith('/') ? '' : '/';
    final remoteFilePath = '$remotePath$sep$fileName';

    await client.putFile(remoteFilePath, bytes);
    return remoteFilePath;
  }

  /// Lists FlowMuse backup files in [remotePath], newest first.
  Future<List<WebDavBackupEntry>> listBackups({
    required WebDavClient client,
    required String remotePath,
  }) async {
    final entries = await client.listDirectory(remotePath);
    final backups = entries
        .where((e) => e.name.startsWith(_filePrefix) && e.name.endsWith(_fileSuffix))
        .map((e) => WebDavBackupEntry(
              href: e.href,
              fileName: e.name,
              sizeBytes: e.sizeBytes,
              lastModified: e.lastModified,
            ))
        .toList();
    // Newest first (filename is lexicographically sortable by date)
    backups.sort((a, b) => b.fileName.compareTo(a.fileName));
    return backups;
  }

  /// Downloads a backup file from WebDAV and restores it into the local DB.
  ///
  /// [remoteDirectory] is the user-configured directory (e.g. `/FlowMuse/`).
  /// [fileName] is the bare filename (e.g. `FlowMuse_2026-07-16_12-00-00.json`).
  ///
  /// The path is rebuilt from directory + filename rather than using the raw
  /// PROPFIND href, which would be an absolute server path (e.g. `/dav/FlowMuse/…`)
  /// and would cause _resolve() to double the WebDAV base path, resulting in
  /// a 409 Conflict error.
  Future<void> restoreBackup({
    required WebDavClient client,
    required String remoteDirectory,
    required String fileName,
    required LocalBackupRepository localRepo,
  }) async {
    final sep = remoteDirectory.endsWith('/') ? '' : '/';
    final path = '$remoteDirectory$sep$fileName';
    final bytes = await client.getFile(path);
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    await localRepo.importBackup(decoded);
  }
}

const webDavBackupService = WebDavBackupService();
