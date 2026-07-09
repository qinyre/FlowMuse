import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

Future<DatabaseFactory> createPlatformLocalDatabaseFactory() async {
  if (_usesNativeSqflitePlugin) {
    return sqflite.databaseFactory;
  }
  ffi.sqfliteFfiInit();
  _ensureSqlite3Loaded();
  return ffi.databaseFactoryFfi;
}

Future<String> platformLocalDatabaseDirectory() async {
  if (_usesNativeSqflitePlugin) {
    return sqflite.getDatabasesPath();
  }
  final directory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}databases',
  );
  if (!databaseDirectory.existsSync()) {
    databaseDirectory.createSync(recursive: true);
  }
  return databaseDirectory.path;
}

/// On HarmonyOS, the `@ffi.Native` fallback uses `DynamicLibrary.process()`
/// which only finds symbols already loaded into the process. We must
/// explicitly load `libsqlite3.so` before any sqlite3 FFI calls so that
/// the symbol lookup succeeds.
void _ensureSqlite3Loaded() {
  if (Platform.operatingSystem != 'ohos') {
    return;
  }
  const libraries = [
    'libsqlite3.so',
    'libsqlite3.so.0',
  ];
  for (final name in libraries) {
    try {
      DynamicLibrary.open(name);
      return;
    } catch (_) {
      // Try the next one.
    }
  }
  // If none of the short names work, the bundled .so might not be in the
  // default linker search path. The caller will get the original
  // MissingPluginException in that case.
}

bool get _usesNativeSqflitePlugin {
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
