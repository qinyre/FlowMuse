import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The result of a cache cleanup: how many bytes were reclaimed and how many
/// files were removed.
class CacheCleanupResult {
  const CacheCleanupResult({this.filesRemoved = 0, this.bytesFreed = 0});

  final int filesRemoved;
  final int bytesFreed;

  /// Human-readable size, e.g. "1.2 MB" or "340 KB".
  String get formattedBytes {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytesFreed.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

/// Clears **safe, rebuildable** caches only — never user data.
///
/// Removed:
/// - Files under `getTemporaryDirectory()/flowmuse-share` (share/export
///   artifacts; see `ShareArtifactStore`).
/// - The Flutter in-memory image cache (`PaintingBinding.imageCache`), which
///   holds decoded avatar/share images.
///
/// **Not** touched: the SQLite database (6 tables), `.scene` overflow files,
/// `local_settings`, or any user-authored content.
Future<CacheCleanupResult> clearRebuildableCache() async {
  var filesRemoved = 0;
  var bytesFreed = 0;

  // 1. Temporary share/export artifacts.
  try {
    final temp = await getTemporaryDirectory();
    final shareDir = Directory(p.join(temp.path, 'flowmuse-share'));
    if (shareDir.existsSync()) {
      await for (final entity in shareDir.list()) {
        if (entity is File) {
          try {
            final size = await entity.length();
            await entity.delete();
            filesRemoved++;
            bytesFreed += size;
          } catch (_) {
            // Skip files that cannot be deleted (e.g. locked).
          }
        }
      }
    }
  } catch (_) {
    // Temporary directory unavailable on this platform/config — ignore.
  }

  // 2. In-memory image cache (framework-level, all platforms).
  try {
    PaintingBinding.instance.imageCache.clear();
  } catch (_) {
    // Defensive: imageCache is always present, but never let cleanup fail.
  }

  return CacheCleanupResult(
    filesRemoved: filesRemoved,
    bytesFreed: bytesFreed,
  );
}

/// Returns the current size (in bytes) of the temporary share/export cache,
/// for display before the user confirms cleanup.  The in-memory image cache
/// size is intentionally excluded — it is transient and not worth surfacing.
Future<int> temporaryCacheSizeBytes() async {
  var total = 0;
  try {
    final temp = await getTemporaryDirectory();
    final shareDir = Directory(p.join(temp.path, 'flowmuse-share'));
    if (shareDir.existsSync()) {
      await for (final entity in shareDir.list()) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Skip unreadable files.
          }
        }
      }
    }
  } catch (_) {
    // Platform without a temporary directory.
  }
  return total;
}
