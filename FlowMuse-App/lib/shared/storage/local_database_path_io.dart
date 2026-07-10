import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

Future<DatabaseFactory> createPlatformLocalDatabaseFactory() async {
  if (_isOhos) {
    _preloadOhosSqlite();
    ffi.sqfliteFfiInit();
    return ffi.databaseFactoryFfi;
  }
  if (_usesNativeSqflitePlugin) {
    return sqflite.databaseFactory;
  }
  ffi.sqfliteFfiInit();
  return ffi.databaseFactoryFfi;
}

Future<String> platformLocalDatabaseDirectory() async {
  if (_isOhos) {
    final directory = await getApplicationSupportDirectory();
    final databaseDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}databases',
    );
    if (!databaseDirectory.existsSync()) {
      databaseDirectory.createSync(recursive: true);
    }
    return databaseDirectory.path;
  }
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

bool get _usesNativeSqflitePlugin {
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

bool get _isOhos => Platform.operatingSystem == 'ohos';

DynamicLibrary? _ohosSqliteLibrary;

void _preloadOhosSqlite() {
  final library = _ohosSqliteLibrary ??=
      DynamicLibrary.open('libharmony_sqlite.z.so');
  final promote = library.lookupFunction<Int32 Function(), int Function()>(
    'harmony_sqlite_make_global',
  );
  if (promote() != 0) {
    throw StateError('Unable to make the OHOS SQLite shim globally visible.');
  }
  library.lookup<Void>('sqlite3_initialize');
}
