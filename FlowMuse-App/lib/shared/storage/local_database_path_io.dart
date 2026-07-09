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

bool get _usesNativeSqflitePlugin {
  return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}
