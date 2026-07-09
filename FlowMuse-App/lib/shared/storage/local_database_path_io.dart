import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DatabaseFactory> createPlatformLocalDatabaseFactory() async {
  sqfliteFfiInit();
  return databaseFactoryFfi;
}

Future<String> platformLocalDatabaseDirectory() async {
  final directory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory(
    '${directory.path}${Platform.pathSeparator}databases',
  );
  if (!databaseDirectory.existsSync()) {
    databaseDirectory.createSync(recursive: true);
  }
  return databaseDirectory.path;
}
